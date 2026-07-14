# frozen_string_literal: true

require "test_helper"

class Api::MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    sign_in_as(@user)
  end

  def create_trace(account: @account, agent_class: "SupportAgent", status: "OK", timestamp: Time.current, duration: 1000.0, input: 100, output: 50)
    TelemetryTrace.create_from_payload(
      {
        "trace_id" => SecureRandom.hex(16),
        "service_name" => "customer-app",
        "environment" => "production",
        "timestamp" => timestamp.iso8601(6),
        "spans" => [
          {
            "span_id" => "r1", "parent_span_id" => nil, "name" => "#{agent_class}.respond",
            "type" => "root", "duration_ms" => duration, "status" => status,
            "attributes" => { "agent.class" => agent_class, "agent.action" => "respond" },
            "tokens" => { "input" => input, "output" => output, "thinking" => 0 }
          }
        ]
      },
      {},
      account: account
    )
  end

  test "returns gem-parity summary metrics" do
    create_trace(duration: 1000.0)
    create_trace(duration: 3000.0, status: "ERROR", agent_class: "BillingAgent")
    create_trace(account: create_account(owner: create_user)) # other account

    get "/api/metrics", params: { hours: 24 }

    assert_response :success
    summary = json_response["summary"]

    assert_equal 2, summary["total_requests"]
    assert_equal 2000, summary["avg_latency_ms"]
    assert_equal 50.0, summary["error_rate"]
    assert_equal 1, summary["errors"]
    assert_equal 2, summary["unique_agents"]
    assert_equal 300, summary["tokens_used"]
    assert_equal 200, summary["tokens_input"]
    assert_equal 100, summary["tokens_output"]
  end

  test "returns zero-filled hourly buckets" do
    create_trace

    get "/api/metrics", params: { hours: 24 }

    hourly = json_response["hourly_requests"]
    assert_equal 24, hourly.length
    assert_equal 1, hourly.sum { |h| h["count"] }
    assert hourly.last["active"]
  end

  test "returns per-agent statistics like the gem dashboard" do
    2.times { create_trace(agent_class: "SupportAgent") }
    create_trace(agent_class: "BillingAgent", status: "ERROR")

    get "/api/metrics"

    by_agent = json_response["by_agent"]
    assert_equal [ "SupportAgent", "BillingAgent" ], by_agent.map { |a| a["name"] }

    support = by_agent.first
    assert_equal 2, support["requests"]
    assert_equal 300, support["tokens"]
    assert_equal 1000, support["avg_duration_ms"]
    assert_equal 0, support["errors"]

    billing = by_agent.last
    assert_equal 1, billing["errors"]
  end

  test "computes previous-period change" do
    create_trace(timestamp: 30.hours.ago)
    create_trace
    create_trace

    get "/api/metrics", params: { hours: 24 }

    assert_equal 100.0, json_response["summary"]["requests_change"]
  end
end
