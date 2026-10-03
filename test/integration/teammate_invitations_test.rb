require "test_helper"
require_relative "../support/pilot_helpers"
require_relative "../support/teammate_helpers"

class TeammateInvitationsTest < ActionDispatch::IntegrationTest
  include PilotHelpers
  include TeammateHelpers
  include ActiveJob::TestHelper

  setup do
    create_seat_plans
    @owner = create_user
    @account = team_account(owner: @owner)
    @agent = create_agent(user: @owner, name: "Shared workspace agent")
  end

  test "an owner invites a teammate who accepts by signing in as the invited email" do
    invitee = create_user(email: "teammate@example.com")
    sign_in_as(@owner)
    get workspace_path
    assert_select "a[href=?]", workspace_members_path

    assert_enqueued_with(job: WorkspaceInvitationDeliveryJob) do
      post workspace_teammate_invitations_path, params: { invitation: { email_address: "Teammate@Example.com", role: "member" } }
    end
    assert_redirected_to workspace_members_path
    invitation = @account.teammate_invitations.sole
    token = deliver_teammate_invitation(invitation)
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "teammate@example.com" ], mail.to
    assert_equal "Join #{@account.name} on ActiveAgents", mail.subject
    delete session_path

    get workspace_invitation_path(token: token)
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_includes response.body, "Sign in to accept"
    assert_not @account.members.include?(invitee), "opening the link adds no one"

    sign_in_as(invitee)
    assert_redirected_to workspace_invitation_path(token: token)
    other = create_account(owner: create_user)
    post workspace_invitation_path, params: { token: token, role: "owner", account_id: other.id }
    assert_redirected_to workspace_path
    follow_redirect!
    assert_includes response.body, "You joined as a member"

    assert_equal "member", @account.account_memberships.find_by!(user: invitee).role, "the role comes from the invitation"
    assert_not other.members.include?(invitee)
    get "/dashboard/api/agents/#{@agent.id}", as: :json
    assert_response :success
  end

  test "a new person is asked to create and verify an account before accepting" do
    sign_in_as(@owner)
    post workspace_teammate_invitations_path, params: { invitation: { email_address: "newcomer@example.com", role: "admin" } }
    token = deliver_teammate_invitation(@account.teammate_invitations.sole)
    delete session_path

    get workspace_invitation_path(token: token)
    assert_response :success
    assert_includes response.body, "Create your account"
    assert_no_difference [ "User.count", "AccountMembership.count" ] do
      post workspace_invitation_path, params: { token: token, password: "password123", password_confirmation: "password123" }
      assert_response :forbidden
    end
  end

  test "another signed-in user or an unverified invitee cannot accept" do
    invitee = create_user(email: "teammate@example.com", email_verified: false)
    _, token = send_teammate_invitation(account: @account, actor: @owner, email: invitee.email_address)

    sign_in_as(create_user)
    get workspace_invitation_path(token: token)
    assert_includes response.body, "Sign out"
    post workspace_invitation_path, params: { token: token }
    assert_response :forbidden

    delete session_path
    sign_in_as(invitee)
    post workspace_invitation_path, params: { token: token }
    assert_response :forbidden
    assert_not @account.members.include?(invitee)
  end

  test "members see the team but cannot invite, remove or change roles" do
    member = add_member(@account)
    admin = add_member(@account, role: "admin")
    admin_membership = @account.account_memberships.find_by!(user: admin)
    sign_in_as(member)
    patch workspace_path, params: { account_id: @account.id }

    get workspace_members_path
    assert_response :success
    assert_includes response.body, admin.email_address
    assert_select "form[action=?]", workspace_teammate_invitations_path, count: 0

    assert_no_difference [ "WorkspaceInvitation.count", "AccountMembership.count" ] do
      post workspace_teammate_invitations_path, params: { invitation: { email_address: "x@example.com", role: "member" } }
      assert_redirected_to workspace_members_path
      delete workspace_member_path(admin_membership)
      patch workspace_member_path(admin_membership), params: { membership: { role: "member" } }
    end
    assert admin_membership.reload.admin?
    follow_redirect!
    assert_includes response.body, "Only the workspace&#39;s owners and admins can manage members."
  end

  test "an admin manages roles and invitations but cannot invite an owner" do
    admin = add_member(@account, role: "admin")
    member_membership = @account.account_memberships.find_by!(user: add_member(@account))
    sign_in_as(admin)
    patch workspace_path, params: { account_id: @account.id }

    assert_no_difference "WorkspaceInvitation.count" do
      post workspace_teammate_invitations_path, params: { invitation: { email_address: "boss@example.com", role: "owner" } }
    end
    follow_redirect!
    assert_includes response.body, "Choose admin or member."

    patch workspace_member_path(member_membership), params: { membership: { role: "admin" } }
    assert member_membership.reload.admin?

    delete workspace_member_path(member_membership)
    assert_not AccountMembership.exists?(member_membership.id)

    post workspace_teammate_invitations_path, params: { invitation: { email_address: "next@example.com", role: "member" } }
    invitation = @account.teammate_invitations.sole
    first_token = deliver_teammate_invitation(invitation)
    assert_enqueued_with(job: WorkspaceInvitationDeliveryJob) do
      post resend_workspace_teammate_invitation_path(invitation)
    end
    assert_nil WorkspaceInvitation.for_token(first_token), "a resend replaces the link"
    delete workspace_teammate_invitation_path(invitation)
    assert invitation.reload.revoked_at?
  end

  test "removing a member ends their access to the workspace at once" do
    member = add_member(@account)
    member_session = open_session
    member_session.sign_in_as(member)
    member_session.patch workspace_path, params: { account_id: @account.id }
    member_session.get "/dashboard/api/agents/#{@agent.id}", as: :json
    assert_equal 200, member_session.response.status

    sign_in_as(@owner)
    delete workspace_member_path(@account.account_memberships.find_by!(user: member))
    assert_redirected_to workspace_members_path

    member_session.get "/dashboard/api/agents/#{@agent.id}", as: :json
    assert_not_equal 200, member_session.response.status
    member_session.get workspace_members_path
    assert_not_includes member_session.response.body.to_s, @account.name
  end

  test "the seat count blocks invitations and the page says so" do
    add_member(@account)
    add_member(@account)
    sign_in_as(@owner)

    get workspace_members_path
    assert_includes response.body, "3 of 3 seats in use"
    assert_includes response.body, "Every seat on your plan is taken"
    post workspace_teammate_invitations_path, params: { invitation: { email_address: "x@example.com", role: "member" } }
    follow_redirect!
    assert_includes response.body, "none are free"
    assert_equal 0, @account.teammate_invitations.count
  end

  test "members and invitations of another workspace are not found" do
    other_owner = create_user
    other = team_account(owner: other_owner)
    other_membership = other.account_memberships.find_by!(user: other_owner)
    other_invitation, = send_teammate_invitation(account: other, actor: other_owner, email: "x@example.com")
    sign_in_as(@owner)

    delete workspace_member_path(other_membership)
    assert_response :not_found
    delete workspace_teammate_invitation_path(other_invitation)
    assert_response :not_found
    post resend_workspace_teammate_invitation_path(other_invitation)
    assert_response :not_found
    assert AccountMembership.exists?(other_membership.id)
    assert_not other_invitation.reload.revoked_at?
  end

  test "pilot administration cannot see or act on teammate invitations" do
    invitation, = send_teammate_invitation(account: @account, actor: @owner, email: "teammate@example.com")
    sign_in_as(create_user(admin: true))

    get admin_pilots_path
    assert_not_includes response.body, "teammate@example.com"
    post revoke_admin_pilot_invitation_path(invitation)
    assert_response :not_found
    assert_not invitation.reload.revoked_at?
  end

  test "managers are told that removal leaves workspace API keys working" do
    sign_in_as(@owner)
    get workspace_members_path
    assert_select "a[href=?]", "/dashboard/settings", text: "Settings → API Keys"

    sign_in_as(add_member(@account))
    patch workspace_path, params: { account_id: @account.id }
    get workspace_members_path
    assert_select "a[href=?]", "/dashboard/settings", count: 0
  end

  test "invitation sends are rate limited per workspace" do
    sign_in_as(@owner)

    with_method(Rails.cache, :increment, ->(*, **) { 21 }) do
      assert_no_enqueued_jobs only: WorkspaceInvitationDeliveryJob do
        post workspace_teammate_invitations_path, params: { invitation: { email_address: "x@example.com", role: "member" } }
      end
    end
    assert_redirected_to workspace_members_path
    assert_equal "This workspace has sent too many invitations. Try again in an hour.", flash[:alert]
    assert_equal 0, @account.teammate_invitations.count
  end
end
