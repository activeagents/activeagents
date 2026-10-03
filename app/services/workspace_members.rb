# Used to change who belongs to a workspace: inviting teammates, changing
# their roles and removing them. Every change is made by an actor who must be
# a verified owner or admin of the workspace.
#
# Changes lock the workspace row, so the seat count and the last-owner rule
# hold when two people change members at once.
class WorkspaceMembers
  class NotAuthorized < StandardError; end
  # Carries a message for the person who asked for the change.
  class Refused < StandardError; end

  # Returns +actor+'s membership in +account+ when they may manage its
  # members. Raises NotAuthorized otherwise, including for a nil account,
  # a nil actor or an actor whose email is unverified.
  def self.authorize!(account, actor)
    membership = account.account_memberships.find_by(user: actor) if account && actor&.email_verified?
    raise NotAuthorized unless membership&.manages_members?
    membership
  end

  attr_reader :account, :actor

  def initialize(account, actor:)
    @account = account
    @actor = actor
  end

  # Creates a teammate invitation and queues its email. Raises Refused for a
  # role other than admin or member, ActiveRecord::RecordInvalid for an
  # invalid email, a current member or an email already invited, then Refused
  # when every seat is taken.
  def invite!(email_address:, role:)
    # A blank role would read as a pilot invitation, so it is refused here
    # rather than left to the model's validations.
    raise Refused, "Choose admin or member." unless role.in?(AccountMembership::INVITABLE_ROLES)

    account.with_lock do
      self.class.authorize!(account, actor)
      invitation = WorkspaceInvitation.new(account: account, email_address: email_address, role: role,
        invited_by: actor, workspace_name: account.name, source: "teammate")
      invitation.validate!
      ensure_seat_available!
      invitation.save!
      invitation.queue_delivery!(actor: actor)
      invitation
    end
  end

  # Emails +invitation+ again with a new link. The previous link stops
  # working. Raises ActiveRecord::RecordInvalid for an accepted or revoked
  # invitation, then Refused unless a seat is free, not counting the
  # invitation itself.
  def resend!(invitation)
    account.with_lock do
      self.class.authorize!(account, actor)
      raise ActiveRecord::RecordInvalid, invitation unless invitation.outstanding?
      ensure_seat_available!(except: invitation)
      invitation.queue_delivery!(actor: actor)
    end
  end

  def revoke!(invitation)
    invitation.revoke!(actor: actor)
  end

  # Gives +membership+ the admin or member role. Demoting an admin to member
  # revokes the invitations they sent that are still outstanding.
  def change_role!(membership, role)
    account.with_lock do
      self.class.authorize!(account, actor)
      membership.lock!
      raise Refused, "An owner's role can't be changed." if membership.owner?
      raise Refused, "Choose admin or member." unless role.in?(AccountMembership::INVITABLE_ROLES)

      membership.update!(role: role)
      revoke_invitations_sent_by(membership.user) if membership.member?
      membership
    end
  end

  # Removes +membership+ and ends the workspace access it carried:
  #
  # - API keys: the ones the member created in this workspace are deleted.
  # - invitations: the ones they sent that are still outstanding are revoked.
  # - sessions: their sessions stop selecting this workspace.
  # - Action Cable: their connections opened for this workspace are closed.
  #
  # Only an owner can remove an owner, and never the last owner or the
  # account's billing owner (`Account#owner`), who keeps access through
  # `owner_id` whatever the memberships say.
  def remove!(membership)
    account.with_lock do
      manager = self.class.authorize!(account, actor)
      membership.lock!
      refuse_owner_removal!(membership, manager) if membership.owner?

      membership.destroy!
      account.api_keys.where(user_id: membership.user_id).destroy_all
      revoke_invitations_sent_by(membership.user)
      membership.user.sessions.where(account: account).update_all(account_id: nil, updated_at: Time.current)
    end
    disconnect(membership.user)
    membership
  end

  private

  def ensure_seat_available!(except: nil)
    return if account.seat_available?(except: except)

    seats = account.seat_limit
    raise Refused, "Your plan includes #{seats} #{"seat".pluralize(seats)} and none are free. " \
      "Remove a member, revoke an invitation or upgrade the plan to invite someone."
  end

  def refuse_owner_removal!(membership, manager)
    raise Refused, "Only an owner can remove an owner." unless manager.owner?
    raise Refused, "The workspace's last owner can't be removed." if account.account_memberships.where(role: "owner").count <= 1
    raise Refused, "The workspace's billing owner can't be removed." if membership.user_id == account.owner_id
  end

  def revoke_invitations_sent_by(user)
    account.teammate_invitations.outstanding.where(invited_by: user)
      .update_all(revoked_at: Time.current, token_digest: nil, updated_at: Time.current)
  end

  # ApplicationCable::Connection is identified by the user and the workspace
  # it resolved at connect time, and RemoteConnections needs every declared
  # identifier, so this matches exactly the connections carrying this
  # workspace. A reconnect resolves the workspace from the session again.
  def disconnect(user)
    ActionCable.server.remote_connections.where(current_user: user, current_account: account, anonymous_id: nil).disconnect
  end
end
