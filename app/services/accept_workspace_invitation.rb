class AcceptWorkspaceInvitation
  class Invalid < StandardError; end
  class SignInRequired < StandardError; end
  class NoSeatAvailable < StandardError; end

  # A teammate invitation is accepted only by a signed-in user whose verified
  # email is the invited one, so +password+ is read only for a pilot
  # invitation, which can create its invitee's user.
  def self.call(token:, signed_in_user:, password: nil, password_confirmation: nil)
    invitation = WorkspaceInvitation.for_token(token)
    raise Invalid, "This invitation is invalid or no longer available." unless invitation
    return join_workspace(invitation, token, signed_in_user) if invitation.teammate?

    invitation.with_lock do
      # Check again after locking: another acceptance/resend may have won.
      unless invitation.usable? && invitation.token_digest == Digest::SHA256.hexdigest(token)
        raise Invalid, "This invitation is invalid or no longer available."
      end
      ProAccess.authorize!(invitation.invited_by)
      user = User.find_by(email_address: invitation.email_address)
      if signed_in_user && signed_in_user.email_address != invitation.email_address
        raise SignInRequired, "Sign in with the invited email address to accept."
      end
      if user && signed_in_user&.id != user.id
        raise SignInRequired, "Sign in with the invited email address to accept."
      end
      user ||= User.create!(email_address: invitation.email_address, password: password,
        password_confirmation: password_confirmation, email_verified: true,
        profile_completed: true, signup_source: "retainer_pilot")
      user.with_lock do
        user.update!(email_verified: true, email_verification_token: nil)
        account = invitation.account || user.owned_accounts.create!(name: invitation.workspace_name)
        raise Invalid, "The workspace owner has changed." unless account.owner_id == user.id
        account.account_memberships.find_or_initialize_by(user: user).update!(role: "owner")
        ProAccess.grant!(account: account, actor: invitation.invited_by, source: invitation.source,
          reason: invitation.reason, starts_at: Time.current, review_on: invitation.review_on, expires_at: invitation.grant_expires_at)
        invitation.update!(account: account, accepted_by: user, accepted_at: Time.current, token_digest: nil)
      end
      invitation
    end
  rescue ActiveRecord::RecordNotUnique
    # A simultaneous public registration must authenticate before accepting.
    raise SignInRequired, "This email is now registered. Sign in to accept your invitation."
  end

  # Adds +user+ to the invitation's workspace with the role the inviter
  # chose. The workspace is locked before the invitation, the same order
  # WorkspaceMembers uses, and the invitation is re-read under the lock.
  def self.join_workspace(invitation, token, user)
    unless user && user.email_address.casecmp?(invitation.email_address)
      raise SignInRequired, "Sign in as #{invitation.email_address} to accept this invitation."
    end
    raise SignInRequired, "Verify your email address, then open this invitation again." unless user.email_verified?

    account = invitation.account
    account.with_lock do
      invitation.lock!
      unless invitation.usable? && invitation.token_digest == Digest::SHA256.hexdigest(token) && invitation.inviter_authorized?
        raise Invalid, "This invitation is invalid or no longer available."
      end
      unless account.seat_limit.negative? || account.account_memberships.count < account.seat_limit
        raise NoSeatAvailable, "#{account.name} has no free seats. Ask an owner or admin to free one or upgrade the plan."
      end

      account.account_memberships.create!(user: user, role: invitation.role)
      invitation.update!(accepted_by: user, accepted_at: Time.current, token_digest: nil)
    end
    invitation
  end
  private_class_method :join_workspace
end
