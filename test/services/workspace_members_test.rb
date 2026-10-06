require "test_helper"
require_relative "../support/teammate_helpers"

class WorkspaceMembersTest < ActiveSupport::TestCase
  include TeammateHelpers
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    create_seat_plans
    @owner = create_user
    @account = team_account(owner: @owner)
  end

  test "::authorize! admits verified owners and admins only" do
    admin = add_member(@account, role: "admin")
    member = add_member(@account)
    outsider = create_user

    assert WorkspaceMembers.authorize!(@account, @owner).owner?
    assert WorkspaceMembers.authorize!(@account, admin).admin?
    assert_raises(WorkspaceMembers::NotAuthorized) { WorkspaceMembers.authorize!(@account, member) }
    assert_raises(WorkspaceMembers::NotAuthorized) { WorkspaceMembers.authorize!(@account, outsider) }
    assert_raises(WorkspaceMembers::NotAuthorized) { WorkspaceMembers.authorize!(@account, nil) }
    assert_raises(WorkspaceMembers::NotAuthorized) { WorkspaceMembers.authorize!(nil, @owner) }

    admin.update!(email_verified: false)
    assert_raises(WorkspaceMembers::NotAuthorized) { WorkspaceMembers.authorize!(@account, admin) }
  end

  test "#invite! creates a teammate invitation and queues its email" do
    invitation = nil
    assert_enqueued_with(job: WorkspaceInvitationDeliveryJob) do
      invitation = members(@owner).invite!(email_address: " New@Example.com ", role: "admin")
    end

    assert invitation.teammate?
    assert_equal "new@example.com", invitation.email_address
    assert_equal "admin", invitation.role
    assert_equal @account, invitation.account
    assert_equal "queued", invitation.delivery_state
  end

  test "#invite! lets an admin invite admins and members but nobody can invite an owner" do
    account = team_account(plan: "enterprise")
    admin = add_member(account, role: "admin")

    assert members(admin, account).invite!(email_address: "a@example.com", role: "admin")
    assert members(admin, account).invite!(email_address: "b@example.com", role: "member")
    [ admin, account.owner ].each do |actor|
      assert_raises(WorkspaceMembers::Refused) { members(actor, account).invite!(email_address: "c@example.com", role: "owner") }
    end
  end

  test "#invite! refuses a blank role rather than creating a pilot invitation" do
    [ nil, "" ].each do |role|
      assert_raises(WorkspaceMembers::Refused) { members(@owner).invite!(email_address: "x@example.com", role: role) }
    end
    assert_equal 0, WorkspaceInvitation.count
  end

  test "#invite! refuses members and outsiders" do
    member = add_member(@account)

    [ member, create_user ].each do |actor|
      assert_raises(WorkspaceMembers::NotAuthorized) { members(actor).invite!(email_address: "x@example.com", role: "member") }
    end
    assert_equal 0, @account.teammate_invitations.count
  end

  test "#invite! counts members and outstanding invitations against the plan's seats" do
    add_member(@account)
    members(@owner).invite!(email_address: "third@example.com", role: "member")

    error = assert_raises(WorkspaceMembers::Refused) do
      members(@owner).invite!(email_address: "fourth@example.com", role: "member")
    end
    assert_match "includes 3 seats", error.message
  end

  test "#invite! is refused on the Free plan, whose one seat is the owner's" do
    account = team_account(plan: "free")

    assert_raises(WorkspaceMembers::Refused) { members(account.owner, account).invite!(email_address: "x@example.com", role: "member") }
  end

  test "#resend! rotates the link and needs a free seat, not counting the invitation itself" do
    invitation, first_token = send_teammate_invitation(account: @account, actor: @owner, email: "new@example.com")
    members(@owner).resend!(invitation)
    second_token = deliver_teammate_invitation(invitation)

    assert_nil WorkspaceInvitation.for_token(first_token)
    assert WorkspaceInvitation.for_token(second_token).usable?

    invitation.update!(token_expires_at: 1.minute.ago)
    add_member(@account)
    members(@owner).invite!(email_address: "other@example.com", role: "member")
    assert_raises(WorkspaceMembers::Refused) { members(@owner).resend!(invitation) }
  end

  test "#resend! refuses a revoked invitation as not resendable, even with every seat taken" do
    invitation, = send_teammate_invitation(account: @account, actor: @owner, email: "new@example.com")
    members(@owner).revoke!(invitation)
    add_member(@account)
    add_member(@account)

    assert_raises(ActiveRecord::RecordInvalid) { members(@owner).resend!(invitation.reload) }
  end

  test "#revoke! invalidates the link, and only for the workspace's owners and admins" do
    invitation, token = send_teammate_invitation(account: @account, actor: @owner, email: "new@example.com")
    member = add_member(@account)

    assert_raises(WorkspaceMembers::NotAuthorized) { members(member).revoke!(invitation) }
    members(@owner).revoke!(invitation)

    assert invitation.reload.revoked_at?
    assert_nil WorkspaceInvitation.for_token(token)
  end

  test "#change_role! switches between admin and member but never touches an owner" do
    admin = add_member(@account, role: "admin")
    membership = @account.account_memberships.find_by!(user: add_member(@account))

    members(admin).change_role!(membership, "admin")
    assert membership.reload.admin?

    owner_membership = @account.account_memberships.find_by!(user: @owner)
    assert_raises(WorkspaceMembers::Refused) { members(admin).change_role!(owner_membership, "member") }
    assert_raises(WorkspaceMembers::Refused) { members(@owner).change_role!(membership, "owner") }
    assert owner_membership.reload.owner?
  end

  test "#change_role! revokes the invitations a demoted admin sent" do
    admin = add_member(@account, role: "admin")
    invitation = members(admin).invite!(email_address: "new@example.com", role: "member")

    members(@owner).change_role!(@account.account_memberships.find_by!(user: admin), "member")

    assert invitation.reload.revoked_at?
  end

  test "#remove! ends the member's access to the workspace and nothing else" do
    member = add_member(@account, role: "admin")
    other_account = create_account(owner: member)
    member_key = @account.api_keys.create!(name: "member's key", user_id: member.id)
    owner_key = @account.api_keys.create!(name: "owner's key", user_id: @owner.id)
    own_workspace_key = other_account.api_keys.create!(name: "member's own workspace", user_id: member.id)
    invitation = members(member).invite!(email_address: "new@example.com", role: "member")
    workspace_session = member.sessions.create!(account: @account)
    other_session = member.sessions.create!(account: other_account)

    assert_broadcast_on(cable_channel_for(member, @account), { "type" => "disconnect", "reconnect" => true }) do
      members(@owner).remove!(@account.account_memberships.find_by!(user: member))
    end

    assert_not @account.members.include?(member)
    assert_not ApiKey.exists?(member_key.id), "the member's key in this workspace is revoked"
    assert ApiKey.exists?(owner_key.id)
    assert ApiKey.exists?(own_workspace_key.id)
    assert invitation.reload.revoked_at?
    assert_nil workspace_session.reload.account_id
    assert_equal other_account.id, other_session.reload.account_id
    assert_nil member.accessible_accounts.find_by(id: @account.id)
  end

  test "#remove! lets an admin remove members and admins but not an owner" do
    admin = add_member(@account, role: "admin")
    other_admin = add_member(@account, role: "admin")
    member = add_member(@account)
    owner_membership = @account.account_memberships.find_by!(user: @owner)

    members(admin).remove!(@account.account_memberships.find_by!(user: member))
    members(admin).remove!(@account.account_memberships.find_by!(user: other_admin))
    error = assert_raises(WorkspaceMembers::Refused) { members(admin).remove!(owner_membership) }
    assert_equal "Only an owner can remove an owner.", error.message
    assert AccountMembership.exists?(owner_membership.id)
  end

  test "#remove! never removes the last owner or the billing owner" do
    owner_membership = @account.account_memberships.find_by!(user: @owner)

    error = assert_raises(WorkspaceMembers::Refused) { members(@owner).remove!(owner_membership) }
    assert_equal "The workspace's last owner can't be removed.", error.message

    co_owner = add_member(@account, role: "owner")
    error = assert_raises(WorkspaceMembers::Refused) { members(co_owner).remove!(owner_membership) }
    assert_equal "The workspace's billing owner can't be removed.", error.message

    members(@owner).remove!(@account.account_memberships.find_by!(user: co_owner))
    assert_not @account.members.include?(co_owner)
  end

  test "#remove! refuses members" do
    member = add_member(@account)
    other = add_member(@account)

    assert_raises(WorkspaceMembers::NotAuthorized) { members(member).remove!(@account.account_memberships.find_by!(user: other)) }
  end

  private

  def members(actor, account = @account)
    WorkspaceMembers.new(account, actor: actor)
  end

  # The internal channel a real ApplicationCable::Connection for +user+ in
  # +account+ listens on.
  def cable_channel_for(user, account)
    connection = ApplicationCable::Connection.allocate
    connection.current_user = user
    connection.current_account = account
    connection.send(:internal_channel)
  end
end
