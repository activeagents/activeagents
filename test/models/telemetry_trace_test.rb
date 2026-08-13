# frozen_string_literal: true

require "test_helper"

class TelemetryTraceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  def trace_payload(trace_id: SecureRandom.hex(16), status: "OK")
    {
      "trace_id" => trace_id,
      "service_name" => "customer-app",
      "environment" => "production",
      "timestamp" => Time.current.iso8601(6),
      "resource_attributes" => {},
      "spans" => [
        {
          "span_id" => "root1",
          "parent_span_id" => nil,
          "name" => "SupportAgent.respond",
          "type" => "root",
          "duration_ms" => 1200.0,
          "status" => status,
          "attributes" => { "agent.class" => "SupportAgent", "agent.action" => "respond" },
          # Mirrored totals, like the gem's telemetry instrumentation emits
          "tokens" => { "input" => 500, "output" => 220, "thinking" => 10, "total" => 730 }
        },
        {
          "span_id" => "llm1",
          "parent_span_id" => "root1",
          "name" => "llm.generate",
          "type" => "llm",
          "duration_ms" => 1100.0,
          "status" => status,
          "attributes" => { "llm.provider" => "anthropic", "llm.model" => "claude-sonnet-4-5" },
          "tokens" => { "input" => 500, "output" => 220, "thinking" => 10, "total" => 730 }
        }
      ]
    }
  end

  test "inherits the gem's table and scopes" do
    assert_equal "active_agent_telemetry_traces", TelemetryTrace.table_name
    assert_operator TelemetryTrace.ancestors, :include?, ActionAgent::TelemetryTrace
  end

  test "create_from_payload normalizes the gem payload" do
    trace = TelemetryTrace.create_from_payload(trace_payload, { "name" => "activeagent" }, account: @account)

    assert_equal @account, trace.account
    assert_equal "SupportAgent", trace.agent_class
    assert_equal "respond", trace.agent_action
    assert_equal "SupportAgent.respond", trace.display_name
    assert_equal "anthropic", trace.provider
    assert_equal "claude-sonnet-4-5", trace.model
    assert_equal 1200.0, trace.total_duration_ms.to_f
  end

  test "create_from_payload does not double-count tokens mirrored on the root span" do
    trace = TelemetryTrace.create_from_payload(trace_payload, {}, account: @account)

    assert_equal 500, trace.total_input_tokens
    assert_equal 220, trace.total_output_tokens
    assert_equal 10, trace.total_thinking_tokens
  end

  test "trace_id is unique per account but reusable across accounts" do
    other_account = create_account(owner: create_user)
    payload = trace_payload

    TelemetryTrace.create_from_payload(payload, {}, account: @account)
    assert_raises(ActiveRecord::RecordInvalid) do
      TelemetryTrace.create_from_payload(payload, {}, account: @account)
    end
    assert TelemetryTrace.create_from_payload(payload, {}, account: other_account).persisted?
  end

  test "for_account scope isolates accounts" do
    mine = TelemetryTrace.create_from_payload(trace_payload, {}, account: @account)
    TelemetryTrace.create_from_payload(trace_payload, {}, account: create_account(owner: create_user))

    assert_equal [ mine.id ], TelemetryTrace.for_account(@account).pluck(:id)
  end

  test "with_errors scope and error extraction" do
    payload = trace_payload(status: "ERROR")
    payload["spans"][0]["attributes"]["error.message"] = "Rate limit exceeded"
    payload["spans"][1]["attributes"]["error.message"] = "Rate limit exceeded"

    trace = TelemetryTrace.create_from_payload(payload, {}, account: @account)

    assert trace.error?
    assert_equal "Rate limit exceeded", trace.error_message
    assert_includes TelemetryTrace.for_account(@account).with_errors, trace
  end
end
