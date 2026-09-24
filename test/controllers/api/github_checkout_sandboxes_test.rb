# frozen_string_literal: true

require "test_helper"

# GitHub connections, the Claude Code connection, and checkout sandboxes on
# the platform (activeagents/activeagent#479, #482). Here the credentials
# belong to accounts while sandboxes and agents belong to users, the split
# the engine's single-user dummy app never exercises.
class Api::GithubCheckoutSandboxesTest < ActionDispatch::IntegrationTest
  OAUTH_TOKEN = "sk-ant-oat01-platformTEST_value-1234"

  setup do
    @previous_backend = ActionAgent.sandbox_service
    ActionAgent.sandbox_service = "mock"

    @owner = create_user(email: "owner-#{SecureRandom.hex(4)}@example.com")
    @account = create_account(owner: @owner)
    @stranger = create_user(email: "stranger-#{SecureRandom.hex(4)}@example.com")
    create_account(owner: @stranger)

    GithubConnection.create!(
      account_id: @account.id, access_token: "gho_platform", github_user_id: 7, login: "octo-owner",
      repositories: [ { "id" => 1, "full_name" => "acme/shop", "private" => true, "default_branch" => "main" } ]
    )
  end

  teardown do
    ActionAgent.sandbox_service = @previous_backend
  end

  test "the account's GitHub connection is visible to its members only, never the token" do
    sign_in_as(@owner)
    get "/dashboard/api/github_connection"

    assert_response :success
    assert json_response["connected"]
    assert_equal "octo-owner", json_response.dig("connection", "login")
    assert_not_includes response.body, "gho_platform"

    sign_in_as(@stranger)
    get "/dashboard/api/github_connection"

    assert_response :success
    assert_not json_response["connected"]
  end

  test "a checkout sandbox boots from the account's selection with its Claude Code credential" do
    sign_in_as(@owner)
    post "/dashboard/api/provider_keys", params: { provider: "claude_code", credential: OAUTH_TOKEN }, as: :json
    assert_response :created

    post "/dashboard/api/sandboxes", params: { sandbox_type: "app_runtime", repository: "acme/shop" }, as: :json

    assert_response :created, response.body
    assert_equal "ready", json_response.dig("sandbox", "status")
    key = json_response.dig("sandbox", "runtime_server_key")
    assert key.start_with?("sandbox:")
    assert_not_includes response.body, OAUTH_TOKEN
    assert_not_includes response.body, "gho_platform"

    session = SandboxSession.find_by!(session_id: json_response.dig("sandbox", "session_id"))
    assert_equal @account.id, session.account_id
    assert_equal "gho_platform", session.checkout_spec[:token]
    assert_equal({ "CLAUDE_CODE_OAUTH_TOKEN" => OAUTH_TOKEN }, session.runtime_environment)

    # The runtime is an MCP server only to the owner's agents.
    assert SandboxSession.runtime_server_entry(key, owner: @owner)
    assert_nil SandboxSession.runtime_server_entry(key, owner: @stranger)
  end

  test "another account cannot check out the account's repositories" do
    sign_in_as(@stranger)

    post "/dashboard/api/sandboxes", params: { sandbox_type: "app_runtime", repository: "acme/shop" }, as: :json

    assert_response :unprocessable_entity
    assert_equal 0, SandboxSession.where(sandbox_type: "app_runtime").count
  end
end
