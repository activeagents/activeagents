require "test_helper"
require_relative "../support/pilot_helpers"

class PilotOnboardingTest < ActionDispatch::IntegrationTest
  include PilotHelpers
  include ActiveJob::TestHelper

  setup do
    create_pilot_plans
    @admin = create_user(admin: true)
    @invitation = prepare_invitation(admin: @admin)
    @token = deliver_invitation(@invitation)
  end

  test "GET does not activate and explicit acceptance creates exactly one isolated Pro workspace" do
    assert_no_difference [ "User.count", "Account.count", "ProAccessGrant.count" ] do
      get workspace_invitation_path(token: @token)
      assert_response :success
    end
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil @invitation.reload.accepted_at
    assert_difference [ "User.count", "Account.count", "AccountMembership.count", "ProAccessGrant.count" ], 1 do
      accept(@token, account_id: 999, source: "enterprise", plan_slug: "enterprise", email_address: "attacker@example.com")
    end
    assert_redirected_to workspace_path
    user = User.find_by!(email_address: "pilot@example.com")
    assert user.email_verified?
    assert user.authenticate("my-new-password")
    assert_equal "owner", @invitation.reload.account.account_memberships.find_by!(user: user).role
    assert_equal "pro", @invitation.account.current_plan.slug
    assert_equal 0, Pay::Subscription.count
    assert_equal 0, NewsletterSubscription.count
    follow_redirect!
    assert_includes response.body, "Pro included during your pilot/retainer"
    get "/dashboard/api/agents", as: :json
    assert_response :success
    assert_no_difference [ "User.count", "Account.count", "ProAccessGrant.count" ] do
      accept(@token)
      assert_response :gone
    end
  end

  test "invalid password rolls the entire acceptance back and the token remains usable" do
    assert_no_difference [ "User.count", "Account.count", "AccountMembership.count", "ProAccessGrant.count" ] do
      post "/workspace_invitation", params: { token: @token, password: "short", password_confirmation: "short" }
      assert_response :unprocessable_entity
    end
    assert @invitation.reload.usable?
  end

  test "existing recipients must authenticate and acceptance cannot reset their password" do
    user = create_user(email: @invitation.email_address)
    original = create_account(owner: user, name: "Original workspace")
    private_agent = create_agent(user: user, name: "Original private agent")
    original_digest = user.password_digest
    accept(@token)
    assert_response :forbidden
    sign_in_as(create_user)
    accept(@token)
    assert_response :forbidden
    sign_in_as(user)
    assert_no_difference "User.count" do
      accept(@token)
      assert_redirected_to workspace_path
    end
    assert_equal original_digest, user.reload.password_digest
    invited_account = @invitation.reload.account
    assert_not_equal original.id, invited_account.id
    follow_redirect!
    assert_includes response.body, invited_account.name
    get "/dashboard/api/agents", as: :json
    assert_not_includes json_response["agents"].map { |agent| agent["id"] }, private_agent.id
    get "/dashboard/api/agents/#{private_agent.id}", as: :json
    assert_response :not_found
    patch "/workspace", params: { account_id: original.id }
    get "/dashboard/api/agents/#{private_agent.id}", as: :json
    assert_response :success
  end

  test "an explicitly selected existing owned workspace is reused" do
    user = create_user(email: "existing@example.com")
    account = create_account(owner: user)
    invitation = prepare_invitation(admin: @admin, email: user.email_address, account: account)
    token = deliver_invitation(invitation)
    sign_in_as(user)
    assert_no_difference [ "Account.count", "AccountMembership.count" ] do
      accept(token)
      assert_redirected_to workspace_path
    end
    assert_equal "pro", account.reload.current_plan.slug
  end

  test "expiry revocation resend and malformed tokens are rejected on GET and POST" do
    travel 8.days do
      get workspace_invitation_path(token: @token)
      assert_response :gone
      accept(@token)
      assert_response :gone
    end
    replacement = deliver_invitation(@invitation)
    assert_not_equal @token, replacement
    accept(@token)
    assert_response :gone
    @invitation.revoke!(actor: @admin)
    get workspace_invitation_path(token: replacement)
    assert_response :gone
    accept(replacement)
    assert_response :gone
    get workspace_invitation_path, params: { token: [ "malformed" ] }
    assert_response :gone
  end

  test "two synthetic client workspaces cannot access each other's agents keys or workspace selection" do
    accept(@token)
    first = @invitation.reload.account
    agent = create_agent(user: first.owner, name: "First private agent")
    first.api_keys.create!(name: "First secret")
    other = prepare_invitation(admin: @admin, email: "second@example.com", workspace_name: "Second client")
    other_token = deliver_invitation(other)
    delete session_path
    accept(other_token)
    second = other.reload.account
    assert_equal "pro", second.current_plan.slug
    assert_not_equal first.id, second.id
    get "/dashboard/api/agents/#{agent.id}", as: :json
    assert_response :not_found
    get "/dashboard/api/api_keys", as: :json
    assert_response :success
    assert_not_includes response.body, "First secret"
    patch "/workspace", params: { account_id: first.id }
    assert_response :not_found
  end

  test "unverified sessions cannot access dashboard keys billing or profile mutation" do
    user = create_user(email_verified: false)
    account = create_account(owner: user)
    sign_in_as(user)
    [ "/dashboard/api/agents", "/dashboard/api/provider_keys", "/dashboard/api/api_keys" ].each do |path|
      get path, as: :json
      assert_response :unauthorized
    end
    post "/subscriptions/checkout", params: { plan_id: Plan.find_by!(slug: "pro").id }
    assert_redirected_to "/pending_verification"
    patch "/complete_profile", params: { user: { first_name: "Changed", password: "different-password" } }
    assert_redirected_to "/pending_verification"
    assert_nil user.reload.first_name
    assert_equal "free", account.current_plan.slug
  end

  private

  def accept(token, **extra)
    post "/workspace_invitation", params: { token: token, password: "my-new-password", password_confirmation: "my-new-password", **extra }
  end
end
