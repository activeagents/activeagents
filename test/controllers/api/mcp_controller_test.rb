# frozen_string_literal: true

require "test_helper"

class Api::McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @api_key = @account.api_keys.create!(name: "mcp client")
    @agent = create_agent(user: @user, name: "Support Bot", description: "Answers support questions")
  end

  def rpc(method, rpc_params = {}, id: 1, token: @api_key.token)
    post "/mcp",
      params: { jsonrpc: "2.0", id: id, method: method, params: rpc_params },
      as: :json,
      headers: { "Authorization" => "Bearer #{token}" }
  end

  test "rejects requests without a valid API key" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize" }, as: :json
    assert_response :unauthorized

    rpc("initialize", token: "aa_bogus")
    assert_response :unauthorized
  end

  test "initialize advertises tools and resources" do
    rpc("initialize")

    assert_response :success
    result = json_response["result"]
    assert result["protocolVersion"].present?
    assert result["capabilities"].key?("tools")
    assert result["capabilities"].key?("resources")
    assert_equal "activeagents", result.dig("serverInfo", "name")
  end

  test "notifications get no JSON-RPC response" do
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }, as: :json,
      headers: { "Authorization" => "Bearer #{@api_key.token}" }

    assert_response :accepted
  end

  test "tools/list exposes the account's agents as tools" do
    archived = create_agent(user: @user, name: "Old Bot", status: :archived)

    rpc("tools/list")
    tools = json_response.dig("result", "tools")

    assert_includes tools.map { |t| t["name"] }, "run_#{@agent.slug}"
    assert_not_includes tools.map { |t| t["name"] }, "run_#{archived.slug}"
    tool = tools.find { |t| t["name"] == "run_#{@agent.slug}" }
    assert_equal "Answers support questions", tool["description"]
    assert_equal [ "message" ], tool.dig("inputSchema", "required")
  end

  test "tools/call runs the agent and returns its output" do
    rpc("tools/call", { name: "run_#{@agent.slug}", arguments: { message: "Hello there" } })

    assert_response :success
    result = json_response["result"]
    assert_not result["isError"]
    assert result.dig("content", 0, "text").present?
    assert result.dig("structuredContent", "trace_id").present?
    assert_equal 1, @agent.agent_runs.count
    assert_equal 1, @account.reload.agent_runs_this_period
  end

  test "tools/call enforces the plan run quota" do
    @account.update!(agent_runs_this_period: Account::USAGE_LIMITS["free"], usage_period_start: Time.current)

    rpc("tools/call", { name: "run_#{@agent.slug}", arguments: { message: "Hello" } })

    assert json_response["error"]["message"].include?("quota"), json_response.inspect
    assert_equal 0, @agent.agent_runs.count
  end

  test "tools/call rejects unknown tools and missing arguments" do
    rpc("tools/call", { name: "run_nonexistent", arguments: { message: "hi" } })
    assert_equal(-32602, json_response.dig("error", "code"))

    rpc("tools/call", { name: "run_#{@agent.slug}", arguments: {} })
    assert_equal(-32602, json_response.dig("error", "code"))
  end

  test "keys from another account cannot see this account's agents" do
    other_key = create_account(owner: create_user).api_keys.create!(name: "other")

    rpc("tools/list", token: other_key.token)
    assert_equal [], json_response.dig("result", "tools")
  end

  test "resources/read returns the agent's live scorecard" do
    create_run(agent: @agent, status: :complete, total_tokens: 50)
    @agent.memory.remember("Customer prefers email follow-ups", source_agent: "SupportBotAgent")

    rpc("resources/read", { uri: "agent://#{@agent.slug}" })

    contents = json_response.dig("result", "contents", 0)
    assert_equal "application/json", contents["mimeType"]
    card = JSON.parse(contents["text"])
    assert_equal "Support Bot", card["name"]
    assert_equal 1, card.dig("stats", "runs")
    assert_includes card["memory"], "Customer prefers email follow-ups"
  end

  test "unknown methods return method-not-found" do
    rpc("bogus/method")
    assert_equal(-32601, json_response.dig("error", "code"))
  end
end
