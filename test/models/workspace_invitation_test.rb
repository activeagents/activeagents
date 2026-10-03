require "test_helper"
require_relative "../support/teammate_helpers"

class WorkspaceInvitationTest < ActiveSupport::TestCase
  include TeammateHelpers

  setup do
    create_seat_plans
    @owner = create_user
    @account = team_account(owner: @owner)
  end

  test "a teammate invitation takes the admin or member role, never owner" do
    assert build_teammate(role: "admin").valid?
    assert build_teammate(role: "member").valid?

    invitation = build_teammate(role: "owner")
    assert_not invitation.valid?
    assert_includes invitation.errors[:role], "is not included in the list"
  end

  test "the database refuses a role outside admin and member" do
    invitation = build_teammate
    invitation.save!

    assert_raises(ActiveRecord::StatementInvalid) { invitation.update_column(:role, "owner") }
  end

  test "a teammate invitation needs a workspace but no pilot review fields" do
    assert build_teammate.valid?, "reason and review_on are pilot-only"

    invitation = build_teammate(account: nil)
    assert_not invitation.valid?
    assert_includes invitation.errors[:account], "can't be blank"
  end

  test "a current member of the workspace cannot be invited, in any letter case" do
    member = add_member(@account, user: create_user(email: "teammate@example.com"))

    invitation = build_teammate(email_address: member.email_address.upcase)
    assert_not invitation.valid?
    assert_includes invitation.errors[:email_address], "already belongs to this workspace"
  end

  test "one outstanding invitation per email per workspace, while other workspaces may invite the same email" do
    build_teammate.save!

    duplicate = build_teammate(email_address: "NEW@example.com")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email_address], "already has a pending invitation to this workspace"

    other = team_account
    assert build_teammate(account: other, invited_by: other.owner).valid?
  end

  test "teammate invitations do not block a pilot invitation for the same email" do
    build_teammate.save!
    admin = create_user(admin: true)

    pilot = WorkspaceInvitation.new(invited_by: admin, email_address: "new@example.com", workspace_name: "Pilot",
      reason: "Retainer", review_on: Date.current + 30)
    assert pilot.valid?
  end

  test "::holding_seat counts outstanding teammate invitations that have not expired" do
    holding = build_teammate.tap(&:save!)
    expired = build_teammate(email_address: "expired@example.com").tap(&:save!)
    expired.update!(token_expires_at: 1.minute.ago)
    revoked = build_teammate(email_address: "revoked@example.com").tap(&:save!)
    revoked.update!(revoked_at: Time.current)

    assert_equal [ holding.id ], WorkspaceInvitation.holding_seat.pluck(:id)
  end

  test "#inviter_authorized? follows the inviter's current role in the workspace" do
    admin = add_member(@account, role: "admin")
    invitation = build_teammate(invited_by: admin).tap(&:save!)
    assert invitation.inviter_authorized?

    @account.account_memberships.find_by!(user: admin).update!(role: "member")
    assert_not invitation.reload.inviter_authorized?
  end

  private

  def build_teammate(account: @account, invited_by: @owner, email_address: "new@example.com", role: "member")
    WorkspaceInvitation.new(account: account, invited_by: invited_by, email_address: email_address, role: role,
      workspace_name: account&.name || "Workspace", source: "teammate")
  end
end
