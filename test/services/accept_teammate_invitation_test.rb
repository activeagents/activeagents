require "test_helper"
require_relative "../support/teammate_helpers"

class AcceptTeammateInvitationTest < ActiveSupport::TestCase
  include TeammateHelpers
  include ActiveJob::TestHelper

  setup do
    create_seat_plans
    @owner = create_user
    @account = team_account(owner: @owner)
    @invitee = create_user(email: "teammate@example.com")
    @invitation, @token = send_teammate_invitation(account: @account, actor: @owner, email: "teammate@example.com", role: "admin")
  end

  test "the signed-in invitee joins with the role the inviter chose, once" do
    accept(user: @invitee)

    assert_equal "admin", @account.account_memberships.find_by!(user: @invitee).role
    assert_equal @invitee, @invitation.reload.accepted_by
    assert_nil @invitation.token_digest
    assert_raises(AcceptWorkspaceInvitation::Invalid) { accept(user: @invitee) }
    assert_equal 1, @account.account_memberships.where(user: @invitee).count
  end

  test "the invited email matches in any letter case" do
    @invitee.update_column(:email_address, "Teammate@Example.com")

    accept(user: @invitee)
    assert @account.members.include?(@invitee)
  end

  test "a signed-out visitor, another user or an unverified invitee cannot accept" do
    @invitee.update!(email_verified: false)

    [ nil, create_user, @invitee ].each do |user|
      assert_raises(AcceptWorkspaceInvitation::SignInRequired) { accept(user: user) }
    end
    assert_not @account.members.include?(@invitee)
    assert @invitation.reload.usable?, "a refused acceptance leaves the link usable"
  end

  test "a signed-out visitor is never given a new user, whatever password they send" do
    @invitee.destroy!

    assert_no_difference "User.count" do
      assert_raises(AcceptWorkspaceInvitation::SignInRequired) do
        AcceptWorkspaceInvitation.call(token: @token, signed_in_user: nil, password: "password123", password_confirmation: "password123")
      end
    end
  end

  test "an expired, revoked or replaced link is invalid" do
    travel 8.days do
      assert_raises(AcceptWorkspaceInvitation::Invalid) { accept(user: @invitee) }
    end

    WorkspaceMembers.new(@account, actor: @owner).resend!(@invitation)
    replacement = deliver_teammate_invitation(@invitation)
    assert_raises(AcceptWorkspaceInvitation::Invalid) { accept(user: @invitee) }

    @invitation.revoke!(actor: @owner)
    assert_raises(AcceptWorkspaceInvitation::Invalid) { accept(user: @invitee, token: replacement) }
    assert_not @account.members.include?(@invitee)
  end

  test "the link stops working once the inviter can no longer invite" do
    @invitation.revoke!(actor: @owner)
    admin = add_member(@account, role: "admin")
    _, token = send_teammate_invitation(account: @account, actor: admin, email: "second@example.com")
    second = create_user(email: "second@example.com")
    @account.account_memberships.find_by!(user: admin).update_column(:role, "member")

    assert_raises(AcceptWorkspaceInvitation::Invalid) { accept(user: second, token: token) }
  end

  test "acceptance is refused when the workspace has no free seat" do
    @account.payment_processor.subscription.cancel_now!
    @account.reload

    error = assert_raises(AcceptWorkspaceInvitation::NoSeatAvailable) { accept(user: @invitee) }
    assert_match "has no free seats", error.message
    assert @invitation.reload.usable?
  end

  private

  def accept(user:, token: @token)
    AcceptWorkspaceInvitation.call(token: token, signed_in_user: user)
  end
end
