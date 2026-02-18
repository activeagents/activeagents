# frozen_string_literal: true

require "test_helper"

class AgentRunTest < ActiveSupport::TestCase
  # ===========================================
  # Association Tests
  # ===========================================

  test "belongs to agent" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent)

    assert_equal agent, run.agent
    assert_includes agent.agent_runs, run
  end

  test "can access user through agent" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent)

    assert_equal user, run.agent.user
  end

  # ===========================================
  # Prompt and Output Tracking Tests
  # ===========================================

  test "tracks input prompt" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, input_prompt: "Explain Ruby blocks")

    assert_equal "Explain Ruby blocks", run.input_prompt
  end

  test "tracks output response" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, output: "Ruby blocks are anonymous functions...")

    assert_equal "Ruby blocks are anonymous functions...", run.output
  end

  test "tracks input parameters" do
    user = create_user
    agent = create_agent(user: user)
    run = agent.agent_runs.create!(
      input_prompt: "Test",
      input_params: { context: "rails", priority: "high" },
      status: :complete
    )

    assert_equal({ "context" => "rails", "priority" => "high" }, run.input_params)
  end

  test "tracks output metadata" do
    user = create_user
    agent = create_agent(user: user)
    run = agent.agent_runs.create!(
      input_prompt: "Test",
      output: "Response",
      output_metadata: { model: "gpt-4o", provider: "openai" },
      status: :complete
    )

    assert_equal({ "model" => "gpt-4o", "provider" => "openai" }, run.output_metadata)
  end

  # ===========================================
  # Token Usage Tracking Tests
  # ===========================================

  test "tracks input tokens" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, input_tokens: 150)

    assert_equal 150, run.input_tokens
  end

  test "tracks output tokens" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, output_tokens: 250)

    assert_equal 250, run.output_tokens
  end

  test "tracks total tokens" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, input_tokens: 100, output_tokens: 200, total_tokens: 300)

    assert_equal 300, run.total_tokens
  end

  test "can aggregate tokens across runs" do
    user = create_user
    agent = create_agent(user: user)

    create_run(agent: agent, total_tokens: 100)
    create_run(agent: agent, total_tokens: 200)
    create_run(agent: agent, total_tokens: 150)

    total = agent.agent_runs.sum(:total_tokens)
    assert_equal 450, total
  end

  # ===========================================
  # Duration Tracking Tests
  # ===========================================

  test "tracks duration in milliseconds" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, duration_ms: 2500)

    assert_equal 2500, run.duration_ms
  end

  test "calculates duration from timestamps" do
    user = create_user
    agent = create_agent(user: user)
    started = Time.current
    completed = started + 3.seconds

    run = agent.agent_runs.create!(
      input_prompt: "Test",
      status: :complete,
      started_at: started,
      completed_at: completed,
      duration_ms: nil
    )

    assert_equal 3000, run.calculated_duration_ms
  end

  test "calculated_duration_ms returns nil if timestamps missing" do
    user = create_user
    agent = create_agent(user: user)
    run = agent.agent_runs.create!(
      input_prompt: "Test",
      status: :pending,
      duration_ms: nil
    )

    assert_nil run.calculated_duration_ms
  end

  # ===========================================
  # Status Tests
  # ===========================================

  test "status enum values" do
    user = create_user
    agent = create_agent(user: user)

    run = agent.agent_runs.create!(input_prompt: "Test", status: :pending)
    assert run.pending?

    run.running!
    assert run.running?

    run.complete!
    assert run.complete?
  end

  test "in_progress returns true for pending and running" do
    user = create_user
    agent = create_agent(user: user)

    pending_run = create_run(agent: agent, status: :pending)
    running_run = create_run(agent: agent, status: :running)
    complete_run = create_run(agent: agent, status: :complete)

    assert pending_run.in_progress?
    assert running_run.in_progress?
    assert_not complete_run.in_progress?
  end

  test "finished returns true for complete, failed, cancelled" do
    user = create_user
    agent = create_agent(user: user)

    complete_run = create_run(agent: agent, status: :complete)
    failed_run = create_run(agent: agent, status: :failed)
    cancelled_run = create_run(agent: agent, status: :cancelled)
    pending_run = create_run(agent: agent, status: :pending)

    assert complete_run.finished?
    assert failed_run.finished?
    assert cancelled_run.finished?
    assert_not pending_run.finished?
  end

  # ===========================================
  # Error Tracking Tests
  # ===========================================

  test "tracks error message on failure" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(
      agent: agent,
      status: :failed,
      error_message: "API rate limit exceeded"
    )

    assert run.failed?
    assert_equal "API rate limit exceeded", run.error_message
  end

  test "tracks error backtrace" do
    user = create_user
    agent = create_agent(user: user)
    backtrace = "line1\nline2\nline3"
    run = agent.agent_runs.create!(
      input_prompt: "Test",
      status: :failed,
      error_message: "Connection timeout",
      error_backtrace: backtrace
    )

    assert_equal backtrace, run.error_backtrace
  end

  # ===========================================
  # Cancel Tests
  # ===========================================

  test "can cancel a pending run" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, status: :pending)

    run.cancel!

    assert run.cancelled?
    assert run.completed_at.present?
    assert_equal "Cancelled by user", run.error_message
  end

  test "can cancel a running run" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, status: :running)

    run.cancel!

    assert run.cancelled?
  end

  test "cannot cancel a completed run" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent, status: :complete)

    run.cancel!

    assert run.complete? # Status unchanged
  end

  # ===========================================
  # Log Tests
  # ===========================================

  test "can add log entries" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent)

    run.add_log("Starting execution")
    run.add_log("Processing input", level: :debug)
    run.add_log("API call failed", level: :error)

    assert_equal 3, run.logs.length
    assert_equal "info", run.logs[0]["level"]
    assert_equal "Starting execution", run.logs[0]["message"]
    assert_equal "error", run.logs[2]["level"]
  end

  # ===========================================
  # Summary Tests
  # ===========================================

  test "summary includes all relevant fields" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(
      agent: agent,
      input_prompt: "A very long prompt that should be truncated",
      output: "A detailed response",
      total_tokens: 300,
      duration_ms: 1500
    )

    summary = run.summary

    assert_equal run.id, summary[:id]
    assert_equal "complete", summary[:status]
    assert summary[:input_preview].present?
    assert summary[:output_preview].present?
    assert_equal 1500, summary[:duration_ms]
    assert_equal 300, summary[:tokens]
  end

  # ===========================================
  # Scope Tests
  # ===========================================

  test "recent scope orders by created_at desc" do
    user = create_user
    agent = create_agent(user: user)

    old_run = agent.agent_runs.create!(input_prompt: "Old", status: :complete, created_at: 2.days.ago)
    new_run = agent.agent_runs.create!(input_prompt: "New", status: :complete, created_at: Time.current)

    recent = agent.agent_runs.recent

    assert_equal new_run, recent.first
    assert_equal old_run, recent.last
  end

  test "successful scope returns only complete runs" do
    user = create_user
    agent = create_agent(user: user)

    complete_run = create_run(agent: agent, status: :complete)
    create_run(agent: agent, status: :failed)
    create_run(agent: agent, status: :pending)

    assert_equal [complete_run], agent.agent_runs.successful.to_a
  end

  test "failed_runs scope returns only failed runs" do
    user = create_user
    agent = create_agent(user: user)

    create_run(agent: agent, status: :complete)
    failed_run = create_run(agent: agent, status: :failed)

    assert_equal [failed_run], agent.agent_runs.failed_runs.to_a
  end

  test "today scope returns only runs from today" do
    user = create_user
    agent = create_agent(user: user)

    today_run = create_run(agent: agent)
    yesterday_run = agent.agent_runs.create!(
      input_prompt: "Yesterday",
      status: :complete,
      created_at: 1.day.ago
    )

    today_runs = agent.agent_runs.today

    assert_includes today_runs, today_run
    assert_not_includes today_runs, yesterday_run
  end

  # ===========================================
  # Trace ID Tests
  # ===========================================

  test "generates trace_id on create" do
    user = create_user
    agent = create_agent(user: user)
    run = agent.agent_runs.create!(input_prompt: "Test", status: :pending)

    assert run.trace_id.present?
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, run.trace_id)
  end

  test "uses provided trace_id" do
    user = create_user
    agent = create_agent(user: user)
    custom_trace_id = "custom-trace-123"

    run = agent.agent_runs.create!(
      input_prompt: "Test",
      status: :pending,
      trace_id: custom_trace_id
    )

    assert_equal custom_trace_id, run.trace_id
  end

  # ===========================================
  # Multi-tenancy Tests
  # ===========================================

  test "runs are isolated to their agent user" do
    user1 = create_user(email: "user1@example.com")
    user2 = create_user(email: "user2@example.com")

    agent1 = create_agent(user: user1)
    agent2 = create_agent(user: user2)

    run1 = create_run(agent: agent1, input_prompt: "User1 prompt")
    run2 = create_run(agent: agent2, input_prompt: "User2 prompt")

    user1_runs = user1.agents.flat_map(&:agent_runs)
    user2_runs = user2.agents.flat_map(&:agent_runs)

    assert_includes user1_runs, run1
    assert_not_includes user1_runs, run2

    assert_includes user2_runs, run2
    assert_not_includes user2_runs, run1
  end

  # ===========================================
  # Aggregation Tests
  # ===========================================

  test "can calculate average tokens per run" do
    user = create_user
    agent = create_agent(user: user)

    create_run(agent: agent, total_tokens: 100)
    create_run(agent: agent, total_tokens: 200)
    create_run(agent: agent, total_tokens: 300)

    avg = agent.agent_runs.average(:total_tokens)
    assert_equal 200, avg
  end

  test "can calculate average duration" do
    user = create_user
    agent = create_agent(user: user)

    create_run(agent: agent, duration_ms: 1000)
    create_run(agent: agent, duration_ms: 2000)
    create_run(agent: agent, duration_ms: 3000)

    avg = agent.agent_runs.average(:duration_ms)
    assert_equal 2000, avg
  end

  test "can calculate success rate" do
    user = create_user
    agent = create_agent(user: user)

    create_run(agent: agent, status: :complete)
    create_run(agent: agent, status: :complete)
    create_run(agent: agent, status: :failed)
    create_run(agent: agent, status: :complete)

    total = agent.agent_runs.count
    successful = agent.agent_runs.successful.count
    success_rate = (successful.to_f / total * 100).round(1)

    assert_equal 75.0, success_rate
  end
end
