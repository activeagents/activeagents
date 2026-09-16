# frozen_string_literal: true

require "test_helper"

class AgentExecutionsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Unified Bot")
  end

  def ingest_trace(agent: @agent, status: "OK", duration_ms: 500, trace_id: nil, at: Time.current,
                   tokens: 0, input_tokens: 0, output_tokens: nil, model: nil)
    TelemetryTrace.create!(
      account: @account,
      agent: agent,
      trace_id: trace_id || SecureRandom.hex(16),
      agent_class: agent.telemetry_agent_class,
      agent_action: "ask",
      status: status,
      timestamp: at,
      total_duration_ms: duration_ms,
      total_input_tokens: input_tokens,
      total_output_tokens: output_tokens || tokens,
      # The model lives on the llm span, which is where pricing reads it.
      spans: model ? [ { "type" => "llm", "attributes" => { "llm.model" => model } } ] : []
    )
  end

  def executions(**options)
    AgentExecutions.new(agents: [ @agent ], owner: @account, **options)
  end

  test "lists dashboard runs and reported traces as one stream of executions" do
    create_run(agent: @agent, status: :complete, duration_ms: 1000, total_tokens: 50)
    ingest_trace(tokens: 25)

    rows = executions.rows

    assert_equal 2, rows.size
    assert_equal %w[dashboard reported], rows.map(&:source).sort
  end

  # The defining constraint: a platform run writes an AgentRun *and* a trace
  # under the same trace_id. Counting both would double every platform agent.
  test "a trace claimed by a run is not listed twice" do
    run = create_run(agent: @agent, status: :complete, duration_ms: 1000)
    run.update!(trace_id: SecureRandom.hex(16))
    ingest_trace(trace_id: run.trace_id)

    rows = executions.rows

    assert_equal 1, rows.size
    assert_equal "dashboard", rows.first.source, "the run is authoritative when both exist"
  end

  # Runs that fail before a root span exists have no trace at all, which is
  # why runs cannot simply be replaced by traces.
  test "keeps runs that never produced a trace" do
    create_run(agent: @agent, status: :failed)

    assert_equal [ "dashboard" ], executions.rows.map(&:source)
  end

  test "source filter selects one kind" do
    create_run(agent: @agent, status: :complete)
    ingest_trace

    assert_equal [ "dashboard" ], executions(source: "dashboard").rows.map(&:source)
    assert_equal [ "reported" ], executions(source: "reported").rows.map(&:source)
  end

  test "status filter maps onto trace status" do
    create_run(agent: @agent, status: :complete)
    ingest_trace(status: "ERROR")

    failed = executions(status: "failed").rows
    assert_equal [ "reported" ], failed.map(&:source)
    assert_equal "failed", failed.first.status

    complete = executions(status: "complete").rows
    assert_equal [ "dashboard" ], complete.map(&:source)
  end

  test "window excludes older executions from both sources" do
    old_run = create_run(agent: @agent, status: :complete)
    old_run.update_columns(created_at: 3.days.ago)
    ingest_trace(at: 3.days.ago)
    ingest_trace(at: 2.minutes.ago)

    assert_equal 1, executions(window_minutes: 60).rows.size
    assert_equal 3, executions.rows.size
  end

  test "page orders newest first across both sources and reports the total" do
    old = create_run(agent: @agent, status: :complete)
    old.update_columns(created_at: 2.hours.ago)
    ingest_trace(at: 1.minute.ago)

    result = executions.page(page: 1, per_page: 1)

    assert_equal 2, result[:total]
    assert_equal 1, result[:rows].size
    assert_equal "reported", result[:rows].first.source, "newest first"
  end

  test "longest sort ranks by duration across both sources" do
    create_run(agent: @agent, status: :complete, duration_ms: 200)
    ingest_trace(duration_ms: 9_000, at: 1.hour.ago)
    ingest_trace(duration_ms: 1_500)

    assert_equal [ 9_000, 1_500, 200 ], executions(sort: "longest").sorted_rows.map(&:duration_ms)
  end

  test "cost sort prices each execution by its own model" do
    # Same token count, wildly different rates: cost order is not token order.
    cheap = ingest_trace(model: "gpt-4o-mini", input_tokens: 1_000, output_tokens: 1_000)
    dear = ingest_trace(model: "claude-3-opus-20240229", input_tokens: 1_000, output_tokens: 1_000)

    rows = executions(sort: "cost").sorted_rows

    assert_equal [ dear.id, cheap.id ], rows.map(&:id)
    assert rows.first.cost > rows.last.cost
  end

  # A running execution has no duration yet; it must not outrank finished
  # ones by sorting as nil, nor disappear from the list.
  test "executions missing the sorted value fall to the end, newest first" do
    running = create_run(agent: @agent, status: :running, duration_ms: nil, completed_at: nil)
    finished = create_run(agent: @agent, status: :complete, duration_ms: 500)

    assert_equal [ finished.id, running.id ], executions(sort: "longest").sorted_rows.map(&:id)
  end

  test "unknown sort falls back to recent rather than raising" do
    old = create_run(agent: @agent, status: :complete)
    old.update_columns(created_at: 2.hours.ago)
    recent = create_run(agent: @agent, status: :complete)

    assert_equal [ recent.id, old.id ], executions(sort: "'; drop table").sorted_rows.map(&:id)
  end

  test "reported executions are addressable by trace, runs by record id" do
    run = create_run(agent: @agent, status: :complete)
    trace = ingest_trace

    rows = executions.rows.index_by(&:source)

    assert_equal run.id.to_s, rows["dashboard"].to_param
    assert_equal "trace-#{trace.id}", rows["reported"].to_param
  end

  test "omits reported executions when no account is given" do
    ingest_trace

    assert_empty AgentExecutions.new(agents: [ @agent ]).rows
  end
end
