# frozen_string_literal: true

require "test_helper"

class AgentExecutionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Support Bot", provider: "openai", model: "gpt-4o-mini")
    @run = @agent.agent_runs.create!(input_prompt: "Hello there", status: :running, started_at: Time.current)
  end

  test "falls back to the gem's mock provider when the requested provider is not configured" do
    result = AgentExecutionService.call(@agent, @run)

    assert result[:output].present?
    assert result[:metadata][:mock]
    assert_equal "mock", result[:metadata][:provider]
    assert_equal "openai", result[:metadata][:requested_provider]
    assert_operator result[:usage][:input_tokens], :>, 0
    assert_operator result[:usage][:output_tokens], :>, 0
  end

  test "records a telemetry trace correlated with the run" do
    AgentExecutionService.call(@agent, @run)

    trace = TelemetryTrace.for_account(@account).find_by(trace_id: @run.trace_id)
    assert trace, "expected a telemetry trace for the run's trace_id"
    assert_equal "SupportBotAgent", trace.agent_class
    assert_equal "OK", trace.status
    assert_operator trace.total_input_tokens, :>, 0
    assert_operator trace.total_duration_ms.to_f, :>, 0

    llm_span = trace.llm_spans.first
    assert llm_span
    assert_equal "mock", llm_span.dig("attributes", "llm.provider")
  end

  test "skips trace recording when the agent has no account" do
    orphan_user = create_user # no account
    agent = create_agent(user: orphan_user, name: "No Account Agent")
    run = agent.agent_runs.create!(input_prompt: "hi", status: :running, started_at: Time.current)

    assert_nothing_raised { AgentExecutionService.call(agent, run) }
    assert_equal 0, TelemetryTrace.where(trace_id: run.trace_id).count
  end

  test "records an error trace when generation fails" do
    failing_agent = create_agent(user: @user, name: "Failing Agent", provider: "mock")
    run = failing_agent.agent_runs.create!(input_prompt: "hi", status: :running, started_at: Time.current)

    service = AgentExecutionService.new(failing_agent, run)
    service.define_singleton_method(:generate!) { raise StandardError, "provider exploded" }

    assert_raises(StandardError) { service.call }

    trace = TelemetryTrace.for_account(@account).find_by(trace_id: run.trace_id)
    assert trace
    assert_equal "ERROR", trace.status
    assert_equal "provider exploded", trace.error_message
  end

  test "test_execute persists run results from real execution" do
    run = @agent.test_execute("Ping")

    assert run.complete?
    assert run.output.present?
    assert_operator run.total_tokens, :>, 0
    assert_operator run.duration_ms, :>, 0
  end
end
