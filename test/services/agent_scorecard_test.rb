# frozen_string_literal: true

require "test_helper"

class AgentScorecardTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Scored Bot")
  end

  # Mirrors what AgentRegistrar writes for an SDK-reported execution:
  # a trace attributed to the Agent record.
  def ingest_trace(agent:, status: "OK", duration_ms: 500, input: 0, output: 0, trace_id: nil)
    TelemetryTrace.create!(
      account: @account,
      agent: agent,
      trace_id: trace_id || SecureRandom.hex(16),
      agent_class: agent.telemetry_agent_class,
      status: status,
      timestamp: Time.current,
      total_duration_ms: duration_ms,
      total_input_tokens: input,
      total_output_tokens: output
    )
  end

  test "aggregates runs, success rate, latency and tokens over the window" do
    create_run(agent: @agent, status: :complete, duration_ms: 1000, total_tokens: 100)
    create_run(agent: @agent, status: :complete, duration_ms: 3000, total_tokens: 200)
    create_run(agent: @agent, status: :failed, duration_ms: nil, total_tokens: nil)

    stats = AgentScorecard.for_agents([ @agent ])[@agent.id]

    assert_equal 3, stats[:runs]
    assert_in_delta 66.7, stats[:success_rate], 0.1
    assert_equal 2000, stats[:avg_duration_ms]
    assert_equal 300, stats[:tokens]
    assert stats[:last_run_at].present?
    assert_nil stats[:eval_score]
  end

  # An agent registered by observation (AgentRegistrar) has traces but no
  # AgentRun rows — the case that made every tile read zero.
  test "counts SDK-reported traces for agents the platform never executed" do
    observed = create_agent(user: @user, name: "Observed Bot", status: :observed)
    ingest_trace(agent: observed, duration_ms: 400, input: 60, output: 40)
    ingest_trace(agent: observed, duration_ms: 600, input: 40, output: 60)
    ingest_trace(agent: observed, status: "ERROR", duration_ms: 200)

    stats = AgentScorecard.for_agents([ observed ])[observed.id]

    assert_equal 3, stats[:runs]
    assert_in_delta 66.7, stats[:success_rate], 0.1
    assert_equal 400, stats[:avg_duration_ms]
    assert_equal 200, stats[:tokens]
    assert stats[:last_run_at].present?
    assert_equal [ "telemetry" ], stats[:run_sources]
  end

  # A platform execution writes an AgentRun *and* a trace sharing a trace_id;
  # counting both would double every platform agent's volume.
  test "does not double-count platform runs that also recorded a trace" do
    run = create_run(agent: @agent, status: :complete, duration_ms: 1000, total_tokens: 100)
    run.update!(trace_id: SecureRandom.hex(16))
    ingest_trace(agent: @agent, trace_id: run.trace_id, duration_ms: 1000, input: 60, output: 40)

    stats = AgentScorecard.for_agents([ @agent ])[@agent.id]

    assert_equal 1, stats[:runs], "trace sharing the run's trace_id must not count twice"
    assert_equal 100, stats[:tokens]
    assert_equal [ "platform" ], stats[:run_sources]
  end

  test "blends platform runs with unmatched telemetry traces" do
    create_run(agent: @agent, status: :complete, duration_ms: 1000, total_tokens: 100)
    ingest_trace(agent: @agent, duration_ms: 500, input: 30, output: 20)

    stats = AgentScorecard.for_agents([ @agent ])[@agent.id]

    assert_equal 2, stats[:runs]
    assert_equal 100.0, stats[:success_rate]
    assert_equal 750, stats[:avg_duration_ms]
    assert_equal 150, stats[:tokens]
    assert_equal %w[platform telemetry], stats[:run_sources]
  end

  test "runs outside the window are excluded from windowed stats" do
    old = create_run(agent: @agent, status: :complete, total_tokens: 999)
    old.update_columns(created_at: 60.days.ago)

    stats = AgentScorecard.for_agents([ @agent ])[@agent.id]

    assert_equal 0, stats[:runs]
    assert_equal 0, stats[:tokens]
    # last_run_at is all-time, so the old run still shows there.
    assert stats[:last_run_at].present?
  end

  test "eval_score comes from the latest complete evaluation run" do
    evaluation = @agent.evaluations.create!(name: "quality", criteria: [ { "key" => "k", "type" => "response_present" } ])
    older = evaluation.evaluation_runs.create!(status: :complete, scores: { "k" => { "score" => 0.4 } }, samples_evaluated: 5, samples_passed: 2)
    older.update_columns(created_at: 2.days.ago)
    evaluation.evaluation_runs.create!(status: :complete, scores: { "k" => { "score" => 0.9 } }, samples_evaluated: 5, samples_passed: 5)
    evaluation.evaluation_runs.create!(status: :failed, error_message: "boom")

    stats = AgentScorecard.for_agents([ @agent ])[@agent.id]

    assert_in_delta 0.9, stats[:eval_score], 0.001
    assert_equal 5, stats[:eval_samples_passed]
  end

  test "returns a row per agent without N+1 per-agent queries" do
    other = create_agent(user: @user, name: "Other Bot")
    create_run(agent: @agent, status: :complete)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      AgentScorecard.for_agents([ @agent, other ])
    end

    assert_operator queries, :<=, 8, "expected grouped queries, got #{queries}"
  end

  test "empty agent list returns an empty hash" do
    assert_equal({}, AgentScorecard.for_agents([]))
  end
end
