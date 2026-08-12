# frozen_string_literal: true

require "test_helper"

class Api::AgentRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "test@example.com")
    @agent = create_agent(user: @user, name: "Test Agent", status: :active)
    @run = create_run(
      agent: @agent,
      input_prompt: "Test prompt",
      output: "Test response",
      input_tokens: 50,
      output_tokens: 100,
      total_tokens: 150,
      duration_ms: 1500
    )
    sign_in_as(@user)
  end

  # ===========================================
  # Show Tests
  # ===========================================

  test "show returns run details with all tracking fields" do
    get "/api/runs/#{@run.id}"

    assert_response :success
    data = json_response

    # Verify run tracking fields
    assert_equal @run.id, data["run"]["id"]
    assert_equal "Test prompt", data["run"]["input_prompt"]
    assert_equal "Test response", data["run"]["output"]
    assert_equal "complete", data["run"]["status"]

    # Verify token tracking
    assert_equal 50, data["run"]["input_tokens"]
    assert_equal 100, data["run"]["output_tokens"]
    assert_equal 150, data["run"]["total_tokens"]

    # Verify duration tracking
    assert_equal 1500, data["run"]["duration_ms"]

    # Verify trace_id for debugging
    assert data["run"]["trace_id"].present?

    # Verify agent association
    assert_equal @agent.id, data["agent"]["id"]
    assert_equal @agent.name, data["agent"]["name"]
  end

  test "show returns 404 for nonexistent run" do
    get "/api/runs/99999"

    assert_response :not_found
  end

  test "show includes input params and output metadata" do
    run = @agent.agent_runs.create!(
      input_prompt: "Custom prompt",
      input_params: { context: "testing", mode: "verbose" },
      output: "Custom response",
      output_metadata: { model: "gpt-4o", finish_reason: "stop" },
      status: :complete
    )

    get "/api/runs/#{run.id}"

    assert_response :success
    data = json_response

    assert_equal({ "context" => "testing", "mode" => "verbose" }, data["run"]["input_params"])
    assert_equal({ "model" => "gpt-4o", "finish_reason" => "stop" }, data["run"]["output_metadata"])
  end

  test "show includes timestamps" do
    get "/api/runs/#{@run.id}"

    assert_response :success
    data = json_response

    assert data["run"]["started_at"].present?
    assert data["run"]["completed_at"].present?
    assert data["run"]["created_at"].present?
  end

  # ===========================================
  # Index Tests
  # ===========================================

  test "index returns all runs" do
    create_run(agent: @agent, input_prompt: "Second prompt")

    get "/api/runs"

    assert_response :success
    data = json_response

    assert_equal 2, data["runs"].length
    assert data["meta"]["total"] >= 2
  end

  test "index includes agent info with each run" do
    get "/api/runs"

    assert_response :success
    data = json_response

    run_data = data["runs"].first
    assert run_data["agent"].present?
    assert_equal @agent.id, run_data["agent"]["id"]
  end

  test "index filters by agent_id" do
    other_agent = create_agent(user: @user, name: "Other Agent")
    create_run(agent: other_agent, input_prompt: "Other prompt")

    get "/api/runs", params: { agent_id: @agent.id }

    assert_response :success
    data = json_response

    assert_equal 1, data["runs"].length
    assert_equal @agent.id, data["runs"].first["agent"]["id"]
  end

  test "index filters by status" do
    create_run(agent: @agent, status: :failed, error_message: "API Error")

    get "/api/runs", params: { status: "failed" }

    assert_response :success
    data = json_response

    data["runs"].each do |run|
      assert_equal "failed", run["status"]
    end
  end

  test "index supports pagination" do
    4.times { create_run(agent: @agent) }

    get "/api/runs", params: { page: 2, per_page: 2 }

    assert_response :success
    data = json_response

    assert_equal 2, data["runs"].length
    assert_equal 2, data["meta"]["page"]
    assert_equal 2, data["meta"]["per_page"]
  end

  test "index orders by created_at desc (recent first)" do
    old_run = @agent.agent_runs.create!(
      input_prompt: "Old prompt",
      status: :complete,
      created_at: 2.days.ago
    )
    new_run = create_run(agent: @agent, input_prompt: "New prompt")

    get "/api/runs"

    assert_response :success
    data = json_response

    run_ids = data["runs"].map { |r| r["id"] }
    assert run_ids.index(new_run.id) < run_ids.index(old_run.id)
  end

  # ===========================================
  # Cancel Tests
  # ===========================================

  test "cancel cancels a pending run" do
    pending_run = @agent.agent_runs.create!(
      input_prompt: "Pending prompt",
      status: :pending
    )

    post "/api/runs/#{pending_run.id}/cancel"

    assert_response :success
    data = json_response

    assert_equal "cancelled", data["run"]["status"]
    assert pending_run.reload.cancelled?
    assert_equal "Cancelled by user", pending_run.error_message
  end

  test "cancel cancels a running run" do
    running_run = @agent.agent_runs.create!(
      input_prompt: "Running prompt",
      status: :running,
      started_at: Time.current
    )

    post "/api/runs/#{running_run.id}/cancel"

    assert_response :success
    assert running_run.reload.cancelled?
  end

  test "cancel does not change completed run" do
    complete_run = create_run(agent: @agent, status: :complete)

    post "/api/runs/#{complete_run.id}/cancel"

    assert_response :success
    assert complete_run.reload.complete?
  end

  # ===========================================
  # Error Tracking Tests
  # ===========================================

  test "show returns error details for failed runs" do
    failed_run = @agent.agent_runs.create!(
      input_prompt: "Failed prompt",
      status: :failed,
      error_message: "Connection timeout after 30s",
      error_backtrace: "lib/client.rb:42\nlib/client.rb:28"
    )

    get "/api/runs/#{failed_run.id}"

    assert_response :success
    data = json_response

    assert_equal "failed", data["run"]["status"]
    assert_equal "Connection timeout after 30s", data["run"]["error_message"]
  end

  # ===========================================
  # Logs Tests
  # ===========================================

  test "show includes run logs" do
    run_with_logs = @agent.agent_runs.create!(
      input_prompt: "Test",
      status: :complete,
      logs: [
        { timestamp: Time.current.iso8601, level: "info", message: "Starting" },
        { timestamp: Time.current.iso8601, level: "debug", message: "Processing" }
      ]
    )

    get "/api/runs/#{run_with_logs.id}"

    assert_response :success
    data = json_response

    assert_equal 2, data["run"]["logs"].length
    assert_equal "Starting", data["run"]["logs"].first["message"]
  end

  # ===========================================
  # Token Aggregation Tests
  # ===========================================

  test "index runs can be aggregated for token usage" do
    # Create runs with varying token counts
    create_run(agent: @agent, total_tokens: 100)
    create_run(agent: @agent, total_tokens: 200)
    create_run(agent: @agent, total_tokens: 300)

    get "/api/runs", params: { agent_id: @agent.id }

    assert_response :success
    data = json_response

    # Verify we can calculate totals from the response
    total_tokens = data["runs"].sum { |r| r["total_tokens"].to_i }
    assert total_tokens >= 600 # At least our created runs
  end

  # ===========================================
  # Multi-tenancy Tests
  # ===========================================

  # This previously asserted the opposite, documenting that "runs are
  # globally accessible" as current behavior. Reading another account's run
  # (its prompts, outputs and errors) is a leak, not a feature.
  test "show does not return a run belonging to another user" do
    other_user = create_user(email: "other@example.com")
    other_agent = create_agent(user: other_user, name: "Other Agent")
    other_run = create_run(agent: other_agent, input_prompt: "Other user prompt")

    get "/api/runs/#{other_run.id}"

    assert_response :not_found
    assert_not_includes response.body, "Other user prompt"
  end

  test "index lists only the current user's runs" do
    other_user = create_user(email: "stranger@example.com")
    other_agent = create_agent(user: other_user, name: "Stranger Agent")
    create_run(agent: other_agent, input_prompt: "Stranger prompt")
    mine = create_run(agent: @agent, input_prompt: "My prompt")

    get "/api/runs"

    assert_response :success
    ids = json_response["runs"].map { |run| run["id"] }
    assert_includes ids, mine.id
    assert_not_includes response.body, "Stranger prompt"
    assert_equal json_response["runs"].size, json_response.dig("meta", "total")
  end
end
