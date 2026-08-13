# frozen_string_literal: true

require "test_helper"

class Api::MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    sign_in_as(@user)
  end

  def create_trace(account: @account, agent_class: "SupportAgent", status: "OK", timestamp: Time.current, duration: 1000.0, input: 100, output: 50, model: nil)
    spans = [
      {
        "span_id" => "r1", "parent_span_id" => nil, "name" => "#{agent_class}.respond",
        "type" => "root", "duration_ms" => duration, "status" => status,
        "attributes" => { "agent.class" => agent_class, "agent.action" => "respond" },
        "tokens" => { "input" => input, "output" => output, "thinking" => 0 }
      }
    ]
    if model
      # Token-free llm span: pricing reads the model from here, and the
      # totals stay on the root span where this helper puts them.
      spans << {
        "span_id" => "l1", "parent_span_id" => "r1", "name" => "chat",
        "type" => "llm", "duration_ms" => duration, "status" => status,
        "attributes" => { "llm.model" => model }
      }
    end

    TelemetryTrace.create_from_payload(
      {
        "trace_id" => SecureRandom.hex(16),
        "service_name" => "customer-app",
        "environment" => "production",
        "timestamp" => timestamp.iso8601(6),
        "spans" => spans
      },
      {},
      account: account
    )
  end

  test "returns gem-parity summary metrics" do
    create_trace(duration: 1000.0)
    create_trace(duration: 3000.0, status: "ERROR", agent_class: "BillingAgent")
    create_trace(account: create_account(owner: create_user)) # other account

    get "/dashboard/api/metrics", params: { hours: 24 }

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

    get "/dashboard/api/metrics", params: { hours: 24 }

    hourly = json_response["hourly_requests"]
    assert_equal 24, hourly.length
    assert_equal 1, hourly.sum { |h| h["count"] }
    assert hourly.last["active"]
  end

  test "returns per-agent statistics like the gem dashboard" do
    2.times { create_trace(agent_class: "SupportAgent") }
    create_trace(agent_class: "BillingAgent", status: "ERROR")

    get "/dashboard/api/metrics"

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

  test "includes estimated cost totals and per-agent costs" do
    trace = create_trace(input: 1_000_000, output: 1_000_000)
    llm_span = {
      "span_id" => "l1", "parent_span_id" => "r1", "type" => "llm", "name" => "llm.generate",
      "attributes" => { "llm.model" => "gpt-4o" }, "tokens" => {}
    }
    trace.update_columns(spans: trace.spans + [ llm_span ])

    get "/dashboard/api/metrics"

    # gpt-4o: $2.50/1M input + $10.00/1M output = $12.50
    assert_in_delta 12.5, json_response.dig("summary", "total_cost"), 0.01
    agent_row = json_response["by_agent"].find { |a| a["name"] == "SupportAgent" }
    assert_in_delta 12.5, agent_row["cost"], 0.01
  end

  # ===========================================
  # Agent table sorting
  # ===========================================

  test "agent table ranks by request count by default" do
    2.times { create_trace(agent_class: "SupportAgent") }
    create_trace(agent_class: "BillingAgent")

    get "/dashboard/api/metrics"

    assert_response :success
    assert_equal %w[SupportAgent BillingAgent], json_response["by_agent"].map { |a| a["name"] }
    assert_equal "popular", json_response["sort"]
  end

  test "agent table ranks by longest average duration" do
    2.times { create_trace(agent_class: "SupportAgent", duration: 100.0) }
    create_trace(agent_class: "BillingAgent", duration: 9000.0)

    get "/dashboard/api/metrics", params: { sort: "longest" }

    assert_equal %w[BillingAgent SupportAgent], json_response["by_agent"].map { |a| a["name"] }
  end

  # The point of a cost ranking: the busiest agent is not the dearest when
  # models differ, so cost order must not collapse back to request order.
  test "agent table ranks by estimated cost, not by traffic" do
    2.times { create_trace(agent_class: "SupportAgent", model: "gpt-4o-mini", input: 1_000, output: 1_000) }
    create_trace(agent_class: "BillingAgent", model: "claude-3-opus-20240229", input: 1_000, output: 1_000)

    get "/dashboard/api/metrics", params: { sort: "cost" }

    names = json_response["by_agent"].map { |a| a["name"] }
    assert_equal %w[BillingAgent SupportAgent], names
    assert_equal %w[SupportAgent BillingAgent], json_response["by_agent"].sort_by { |a| -a["requests"] }.map { |a| a["name"] },
                 "traffic order is the reverse — the sort really is on cost"
  end

  test "agent table ranks by error count" do
    3.times { create_trace(agent_class: "SupportAgent") }
    create_trace(agent_class: "BillingAgent", status: "ERROR")

    get "/dashboard/api/metrics", params: { sort: "errors" }

    assert_equal "BillingAgent", json_response["by_agent"].first["name"]
  end

  test "unknown sort falls back to the default ranking" do
    2.times { create_trace(agent_class: "SupportAgent") }
    create_trace(agent_class: "BillingAgent")

    get "/dashboard/api/metrics", params: { sort: "nonsense" }

    assert_response :success
    assert_equal "popular", json_response["sort"]
    assert_equal %w[SupportAgent BillingAgent], json_response["by_agent"].map { |a| a["name"] }
  end

  test "computes previous-period change" do
    create_trace(timestamp: 30.hours.ago)
    create_trace
    create_trace

    get "/dashboard/api/metrics", params: { hours: 24 }

    assert_equal 100.0, json_response["summary"]["requests_change"]
  end
end
