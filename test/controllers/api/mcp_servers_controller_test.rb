# frozen_string_literal: true

require "test_helper"

# The engine's Tools and MCP Services endpoints, exercised through this
# app's mount at /dashboard.
#
# The engine's own suite covers the single-user shape its dummy app has.
# These cover what only a multi-tenant host can reach: traffic scoped to an
# account, and a launched sandbox belonging to the user who opened it rather
# than to the tenant that `current_owner` resolves to.
class Api::McpServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    sign_in_as(@user)
  end

  def create_trace(tool_names, account: @account, agent_class: "SupportAgent")
    spans = [
      {
        "span_id" => "r1", "parent_span_id" => nil, "name" => "#{agent_class}.respond",
        "type" => "root", "duration_ms" => 900.0, "status" => "OK",
        "attributes" => { "agent.class" => agent_class, "agent.action" => "respond" }
      }
    ]
    Array(tool_names).each_with_index do |name, index|
      spans << {
        "span_id" => "t#{index}", "parent_span_id" => "r1", "name" => "tool.#{name}",
        "type" => "tool", "duration_ms" => 50.0, "status" => "OK",
        "attributes" => { "tool.name" => name }
      }
    end

    TelemetryTrace.create_from_payload(
      {
        "trace_id" => SecureRandom.hex(16), "service_name" => "app",
        "environment" => "production", "timestamp" => Time.current.iso8601(6), "spans" => spans
      },
      {},
      account: account
    )
  end

  test "tools are scoped to the signed-in account" do
    create_trace([ "mcp__playwright__browser_navigate" ])
    create_trace([ "someone_elses_tool" ], account: create_account(owner: create_user))

    get "/dashboard/api/tools"

    assert_response :success
    names = json_response["tools"].map { |tool| tool["name"] }
    assert_includes names, "mcp__playwright__browser_navigate"
    assert_not_includes names, "someone_elses_tool"
  end

  test "MCP services list detected servers alongside the default catalog" do
    create_trace([ "mcp__playwright__browser_navigate" ])

    get "/dashboard/api/mcp_servers"

    assert_response :success
    servers = json_response["servers"].index_by { |server| server["key"] }
    assert_equal "active", servers["playwright"]["status"]
    assert_equal "available", servers["fetch"]["status"]
  end

  test "a launched sandbox belongs to the user who opened it" do
    assert_difference -> { SandboxSession.count }, 1 do
      post "/dashboard/api/mcp_servers/playwright/launch"
    end

    assert_response :created

    sandbox = SandboxSession.order(:created_at).last
    # SandboxSession prefers :user, but current_owner is the account in a
    # multi-tenant install — assigning through the ownership seam would put
    # an Account in the user association and raise.
    assert_equal @user, sandbox.user
    assert_equal @account, sandbox.account
    assert_equal [ "playwright" ], sandbox.mcp_servers
  end

  test "a launched sandbox is listed as running for its owner only" do
    post "/dashboard/api/mcp_servers/filesystem/launch"
    assert_response :created

    get "/dashboard/api/mcp_servers"
    assert_equal [ [ "filesystem" ] ], json_response["sandboxes"].map { |s| s["mcp_servers"] }

    delete "/session"
    sign_in_as(create_user_with_account)
    get "/dashboard/api/mcp_servers"
    assert_empty json_response["sandboxes"]
  end

  test "servers needing host credentials are listed but not launchable" do
    assert_no_difference -> { SandboxSession.count } do
      post "/dashboard/api/mcp_servers/github/launch"
    end

    assert_response :unprocessable_entity
    assert_match(/GITHUB_TOKEN/, json_response["reason"])
  end

  private

  def create_user_with_account
    user = create_user
    create_account(owner: user)
    user
  end
end
