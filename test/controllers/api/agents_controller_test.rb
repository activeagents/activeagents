# frozen_string_literal: true

require "test_helper"

class Api::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "test@example.com")
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Test Agent", status: :active)
    sign_in_as(@user)
  end

  # ===========================================
  # Index Tests
  # ===========================================

  test "index returns user's agents" do
    create_agent(user: @user, name: "Second Agent")

    get "/api/agents"

    assert_response :success
    data = json_response

    assert_equal 2, data["agents"].length
    assert data["meta"]["providers"].present?
    assert data["meta"]["preset_types"].present?
  end

  test "index ranks agents by run count" do
    busy = create_agent(user: @user, name: "Busy Agent")
    2.times { create_run(agent: busy) }
    create_run(agent: @agent)

    get "/api/agents", params: { sort: "popular" }

    assert_response :success
    assert_equal [ busy.id, @agent.id ], json_response["agents"].map { |a| a["id"] }
    assert_equal "popular", json_response.dig("meta", "sort")
  end

  test "index ranks agents by estimated cost" do
    cheap = create_agent(user: @user, name: "Cheap Agent")
    create_run(agent: cheap, input_tokens: 1_000, output_tokens: 1_000,
               output_metadata: { "model" => "gpt-4o-mini" })
    create_run(agent: @agent, input_tokens: 1_000, output_tokens: 1_000,
               output_metadata: { "model" => "claude-3-opus-20240229" })

    get "/api/agents", params: { sort: "cost" }

    assert_equal [ @agent.id, cheap.id ], json_response["agents"].map { |a| a["id"] }
  end

  # Agents with nothing to rank belong at the bottom, not interleaved as
  # zeroes ahead of agents that have actually run.
  test "index puts agents with no priced spend last" do
    unpriced = create_agent(user: @user, name: "Never Run")
    create_run(agent: @agent, input_tokens: 1_000, output_tokens: 1_000,
               output_metadata: { "model" => "gpt-4o" })

    get "/api/agents", params: { sort: "cost" }

    assert_equal [ @agent.id, unpriced.id ], json_response["agents"].map { |a| a["id"] }
  end

  test "index falls back to recently-updated for an unknown sort" do
    get "/api/agents", params: { sort: "; drop table" }

    assert_response :success
    assert_equal "recent", json_response.dig("meta", "sort")
  end

  test "index filters by status" do
    draft_agent = create_agent(user: @user, name: "Draft Agent", status: :draft)

    get "/api/agents", params: { status: "draft" }

    assert_response :success
    data = json_response

    assert_equal 1, data["agents"].length
    assert_equal draft_agent.id, data["agents"].first["id"]
  end

  test "index filters by provider" do
    anthropic_agent = create_agent(user: @user, name: "Anthropic Agent", provider: "anthropic")

    get "/api/agents", params: { provider: "anthropic" }

    assert_response :success
    data = json_response

    assert_equal 1, data["agents"].length
    assert_equal anthropic_agent.id, data["agents"].first["id"]
  end

  test "index searches by name" do
    create_agent(user: @user, name: "Code Review Bot")

    get "/api/agents", params: { q: "code" }

    assert_response :success
    data = json_response

    assert_equal 1, data["agents"].length
    assert_includes data["agents"].first["name"], "Code"
  end

  test "index does not return other users agents" do
    other_user = create_user(email: "other@example.com")
    create_agent(user: other_user, name: "Other User Agent")

    get "/api/agents"

    assert_response :success
    data = json_response

    agent_names = data["agents"].map { |a| a["name"] }
    assert_not_includes agent_names, "Other User Agent"
  end

  # ===========================================
  # Show Tests
  # ===========================================

  test "show returns agent details" do
    get "/api/agents/#{@agent.id}"

    assert_response :success
    data = json_response

    assert_equal @agent.id, data["agent"]["id"]
    assert_equal @agent.name, data["agent"]["name"]
    assert data["agent"]["instructions"].present?
    assert data["versions"].present?
    assert data["recent_runs"].is_a?(Array)
  end

  test "show returns 404 for nonexistent agent" do
    get "/api/agents/99999"

    assert_response :not_found
  end

  test "show returns 404 for other users agent" do
    other_user = create_user(email: "other@example.com")
    other_agent = create_agent(user: other_user)

    get "/api/agents/#{other_agent.id}"

    assert_response :not_found
  end

  # ===========================================
  # Create Tests
  # ===========================================

  test "create creates agent with valid params" do
    assert_difference "Agent.count", 1 do
      post "/api/agents", params: {
        agent: {
          name: "New Agent",
          description: "A new test agent",
          provider: "openai",
          model: "gpt-4o"
        }
      }
    end

    assert_response :created
    data = json_response

    assert_equal "New Agent", data["agent"]["name"]
    assert_equal "openai", data["agent"]["provider"]
  end

  test "create associates agent with current user" do
    post "/api/agents", params: {
      agent: {
        name: "My Agent",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514"
      }
    }

    assert_response :created

    agent = Agent.last
    assert_equal @user.id, agent.user_id
  end

  test "create returns errors for invalid params" do
    post "/api/agents", params: {
      agent: {
        name: "",
        provider: "openai",
        model: "gpt-4o"
      }
    }

    assert_response :unprocessable_entity
    data = json_response

    assert data["errors"].present?
    assert_includes data["errors"].first, "Name"
  end

  test "create with full configuration" do
    post "/api/agents", params: {
      agent: {
        name: "Full Config Agent",
        description: "Agent with all options",
        provider: "anthropic",
        model: "claude-sonnet-4-20250514",
        instructions: "Be helpful and concise.",
        preset_type: "terminal",
        tools: [ "terminal", "filesystem" ],
        instruction_sets: [ "github", "ruby" ],
        model_config: { temperature: 0.7 }
      }
    }

    assert_response :created
    data = json_response

    assert_equal [ "terminal", "filesystem" ], data["agent"]["tools"]
    assert_equal [ "github", "ruby" ], data["agent"]["instruction_sets"]
    # model_config is stored as JSON, values may be strings or numbers
    assert data["agent"]["model_config"]["temperature"].present?
  end

  # ===========================================
  # Update Tests
  # ===========================================

  test "update modifies agent" do
    patch "/api/agents/#{@agent.id}", params: {
      agent: {
        name: "Updated Name",
        instructions: "New instructions"
      }
    }

    assert_response :success
    data = json_response

    assert_equal "Updated Name", data["agent"]["name"]
    assert_equal "New instructions", data["agent"]["instructions"]
  end

  test "update returns errors for invalid params" do
    patch "/api/agents/#{@agent.id}", params: {
      agent: { name: "" }
    }

    assert_response :unprocessable_entity
  end

  test "update cannot modify other users agent" do
    other_user = create_user(email: "other@example.com")
    other_agent = create_agent(user: other_user)

    patch "/api/agents/#{other_agent.id}", params: {
      agent: { name: "Hacked" }
    }

    assert_response :not_found
    assert_equal "Test Agent", other_agent.reload.name
  end

  # ===========================================
  # Destroy Tests
  # ===========================================

  test "destroy deletes agent" do
    assert_difference "Agent.count", -1 do
      delete "/api/agents/#{@agent.id}"
    end

    assert_response :success
    data = json_response

    assert data["success"]
  end

  test "destroy cannot delete other users agent" do
    other_user = create_user(email: "other@example.com")
    other_agent = create_agent(user: other_user)

    assert_no_difference "Agent.count" do
      delete "/api/agents/#{other_agent.id}"
    end

    assert_response :not_found
  end

  # ===========================================
  # Versions Tests
  # ===========================================

  test "versions returns agent version history" do
    @agent.update!(instructions: "Updated v2")
    @agent.update!(instructions: "Updated v3")

    get "/api/agents/#{@agent.id}/versions"

    assert_response :success
    data = json_response

    assert_equal 3, data["versions"].length
    assert_equal 3, data["versions"].first["version_number"]
    assert_equal 1, data["versions"].last["version_number"]
  end

  # ===========================================
  # Restore Tests
  # ===========================================

  test "restore restores agent to previous version" do
    @agent.update!(instructions: "Original")
    original_version = @agent.latest_version

    @agent.update!(instructions: "Updated")
    assert_equal "Updated", @agent.instructions

    post "/api/agents/#{@agent.id}/restore", params: { version_id: original_version.id }

    assert_response :success
    data = json_response

    assert_equal "Original", data["agent"]["instructions"]
  end

  # ===========================================
  # Runs Tests
  # ===========================================

  test "runs returns agent run history" do
    create_run(agent: @agent, input_prompt: "Prompt 1")
    create_run(agent: @agent, input_prompt: "Prompt 2")

    get "/api/agents/#{@agent.id}/runs"

    assert_response :success
    data = json_response

    assert_equal 2, data["runs"].length
    assert data["meta"]["total"].present?
  end

  test "runs filters by status" do
    create_run(agent: @agent, status: :complete)
    create_run(agent: @agent, status: :failed)

    get "/api/agents/#{@agent.id}/runs", params: { status: "complete" }

    assert_response :success
    data = json_response

    assert_equal 1, data["runs"].length
    assert_equal "complete", data["runs"].first["status"]
  end

  test "runs supports pagination" do
    5.times { create_run(agent: @agent) }

    get "/api/agents/#{@agent.id}/runs", params: { page: 1, per_page: 2 }

    assert_response :success
    data = json_response

    assert_equal 2, data["runs"].length
    assert_equal 1, data["meta"]["page"]
    assert_equal 2, data["meta"]["per_page"]
    assert_equal 5, data["meta"]["total"]
  end

  # A query value can arrive as a container (`minutes[]=1&minutes[]=2`, or
  # `page[x]=1`), and neither Array nor ActionController::Parameters
  # responds to `to_i`. Reading them directly raised NoMethodError and
  # turned a malformed query into a 500 (#126).
  test "runs coerces container-valued minutes, page and per_page instead of raising" do
    create_run(agent: @agent)

    get "/api/agents/#{@agent.id}/runs", params: { minutes: [ 1, 2 ], page: { x: 1 }, per_page: [ 5 ] }

    assert_response :success, "container-valued params were not coerced: #{response.body}"
    assert_equal 1, json_response["runs"].length
    # A multi-valued param means its first value, never the concatenation.
    assert_equal 5, json_response["meta"]["per_page"]
    assert_equal 1, json_response["meta"]["page"], "a nested object is malformed and floors to the default page"
  end

  test "analytics coerces a container-valued days param instead of raising" do
    get "/api/agents/#{@agent.id}/analytics", params: { days: [ 7, 30 ] }

    assert_response :success, "container-valued days was not coerced: #{response.body}"
    assert json_response["summary"].key?("total_runs")
  end

  # ===========================================
  # Execute Tests
  # ===========================================

  test "execute creates pending run and queues job" do
    assert_difference "AgentRun.count", 1 do
      post "/api/agents/#{@agent.id}/execute", params: {
        prompt: "Review this code"
      }
    end

    assert_response :accepted
    data = json_response

    assert_equal "pending", data["run"]["status"]
    assert_includes data["run"]["input_preview"], "Review this code"
  end

  test "execute counts against the account's monthly usage" do
    assert_difference -> { @account.reload.agent_runs_this_period }, 1 do
      post "/api/agents/#{@agent.id}/execute", params: { prompt: "Hello" }
    end

    assert_response :accepted
  end

  test "execute is blocked with 402 when the plan run limit is reached" do
    @account.update!(
      agent_runs_this_period: Account::USAGE_LIMITS["free"],
      usage_period_start: Time.current
    )

    assert_no_difference "AgentRun.count" do
      post "/api/agents/#{@agent.id}/execute", params: { prompt: "Hello" }
    end

    assert_response :payment_required
    data = json_response

    assert data["upgrade_required"]
    assert_equal Account::USAGE_LIMITS["free"], data["usage"]["runs_limit"]
    assert_equal false, data["usage"]["can_run"]
  end

  test "execute requires an account" do
    user_without_account = create_user
    agent = create_agent(user: user_without_account, status: :active)
    sign_in_as(user_without_account)

    post "/api/agents/#{agent.id}/execute", params: { prompt: "Hello" }

    assert_response :unauthorized
  end

  # ===========================================
  # Test Execution Tests
  # ===========================================

  test "test executes synchronously and returns result" do
    # Execute through the gem's mock provider — the test-environment double;
    # without credentials real providers now fail instead of falling back.
    @agent.update!(provider: "mock")

    post "/api/agents/#{@agent.id}/test", params: {
      prompt: "What is 2+2?"
    }

    assert_response :success
    data = json_response

    assert_equal "complete", data["run"]["status"]
    assert data["output"].present?
  end

  test "test counts against the account's monthly usage" do
    assert_difference -> { @account.reload.agent_runs_this_period }, 1 do
      post "/api/agents/#{@agent.id}/test", params: { prompt: "Hello" }
    end

    assert_response :success
  end

  test "test is blocked with 402 when the plan run limit is reached" do
    @account.update!(
      agent_runs_this_period: Account::USAGE_LIMITS["free"],
      usage_period_start: Time.current
    )

    post "/api/agents/#{@agent.id}/test", params: { prompt: "Hello" }

    assert_response :payment_required
    assert json_response["upgrade_required"]
  end

  # ===========================================
  # Duplicate Tests
  # ===========================================

  test "duplicate creates copy of agent" do
    assert_difference "Agent.count", 1 do
      post "/api/agents/#{@agent.id}/duplicate"
    end

    assert_response :created
    data = json_response

    assert_includes data["agent"]["name"], "(Copy)"
    assert_equal "draft", data["agent"]["status"]
    assert_equal @agent.provider, data["agent"]["provider"]
    assert_equal @agent.model, data["agent"]["model"]
  end

  # ===========================================
  # Export Tests
  # ===========================================

  test "export returns agent configuration and code" do
    get "/api/agents/#{@agent.id}/export"

    assert_response :success
    data = json_response

    assert data["agent"].present?
    assert data["code"].present?
    assert data["manifest"].present?
    assert_includes data["code"], "ApplicationAgent"
    assert_equal @agent.slug, data["manifest"]["name"]
  end

  # ===========================================
  # Analytics Tests
  # ===========================================

  test "analytics returns agent statistics" do
    # Create a new agent without the setup agent to have clean state
    analytics_agent = create_agent(user: @user, name: "Analytics Test Agent", status: :active)
    create_run(agent: analytics_agent, status: :complete, total_tokens: 100, duration_ms: 1000)
    create_run(agent: analytics_agent, status: :complete, total_tokens: 200, duration_ms: 2000)
    create_run(agent: analytics_agent, status: :failed, total_tokens: 0, error_message: "API Error")

    get "/api/agents/#{analytics_agent.id}/analytics"

    assert_response :success
    data = json_response

    assert_equal 30, data["period_days"]
    assert_equal 3, data["summary"]["total_runs"]
    assert_equal 2, data["summary"]["completed_runs"]
    assert_equal 1, data["summary"]["failed_runs"]
    assert_equal 300, data["summary"]["total_tokens"]
    assert data["summary"]["success_rate"].present?
    assert data["runs_by_day"].is_a?(Array)
    assert data["status_breakdown"].present?
    assert data["recent_errors"].is_a?(Array)
  end

  test "analytics filters by days parameter" do
    get "/api/agents/#{@agent.id}/analytics", params: { days: 7 }

    assert_response :success
    data = json_response

    assert_equal 7, data["period_days"]
  end
end
