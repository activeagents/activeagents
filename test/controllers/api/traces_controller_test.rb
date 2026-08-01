# frozen_string_literal: true

require "test_helper"

class Api::TracesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    sign_in_as(@user)
  end

  def create_trace(account: @account, agent_class: "SupportAgent", status: "OK", timestamp: Time.current)
    TelemetryTrace.create_from_payload(
      {
        "trace_id" => SecureRandom.hex(16),
        "service_name" => "customer-app",
        "environment" => "production",
        "timestamp" => timestamp.iso8601(6),
        "spans" => [
          {
            "span_id" => "r1", "parent_span_id" => nil, "name" => "#{agent_class}.respond",
            "type" => "root", "start_time" => (timestamp - 1.second).iso8601(6),
            "end_time" => timestamp.iso8601(6), "duration_ms" => 1000.0, "status" => status,
            "attributes" => { "agent.class" => agent_class, "agent.action" => "respond" },
            "tokens" => { "input" => 10, "output" => 5, "thinking" => 0 }
          },
          {
            "span_id" => "l1", "parent_span_id" => "r1", "name" => "llm.generate",
            "type" => "llm", "start_time" => (timestamp - 0.9.seconds).iso8601(6),
            "end_time" => timestamp.iso8601(6), "duration_ms" => 900.0, "status" => status,
            "attributes" => { "llm.provider" => "openai", "llm.model" => "gpt-4o" },
            "tokens" => { "input" => 10, "output" => 5, "thinking" => 0 }
          }
        ]
      },
      {},
      account: account
    )
  end

  test "index returns account traces with serialized spans" do
    create_trace

    get "/api/traces", params: { minutes: 30 }

    assert_response :success
    data = json_response
    assert_equal 1, data["traces"].length

    trace = data["traces"].first
    assert_equal "SupportAgent", trace["agent"]
    assert_equal "respond", trace["action"]
    assert_equal "OK", trace["status"]
    assert_equal({ "input" => 10, "output" => 5, "thinking" => 0, "total" => 15 }, trace["tokens"])
    assert_equal [ "SupportAgent" ], data["agents"]

    spans = trace["spans"]
    assert_equal 2, spans.length
    root, llm = spans
    assert_equal [ "root", 0 ], [ root["type"], root["nested"] ]
    assert_equal [ "llm", 1 ], [ llm["type"], llm["nested"] ]
    assert_in_delta 100.0, llm["start"], 1.0
  end

  test "index does not leak other accounts' traces" do
    create_trace(account: create_account(owner: create_user))

    get "/api/traces"

    assert_response :success
    assert_empty json_response["traces"]
  end

  test "index filters by agent and status" do
    create_trace(agent_class: "SupportAgent")
    create_trace(agent_class: "BillingAgent", status: "ERROR")

    get "/api/traces", params: { agent: "BillingAgent" }
    assert_equal [ "BillingAgent" ], json_response["traces"].map { |t| t["agent"] }.uniq

    get "/api/traces", params: { status: "error" }
    assert_equal [ "ERROR" ], json_response["traces"].map { |t| t["status"] }.uniq
  end

  test "index excludes traces outside the window" do
    create_trace(timestamp: 2.hours.ago)

    get "/api/traces", params: { minutes: 30 }

    assert_empty json_response["traces"]
  end

  test "show returns trace detail" do
    trace = create_trace

    get "/api/traces/#{trace.id}"

    assert_response :success
    assert_equal trace.trace_id, json_response["trace"]["trace_id"]
    assert json_response["trace"].key?("resource_attributes")
  end

  test "index reports context occupancy at the time of each call" do
    trace = create_trace
    agent = create_agent(user: @user, name: "Support Bot")
    context = AgentContext.create!(contextable: agent, agent_name: "SupportAgent", action_name: "respond")
    context.generations.create!(
      model: "gpt-4o-mini", input_tokens: 118_000, output_tokens: 400,
      cached_tokens: 32_000, finish_reason: "stop", trace_id: trace.trace_id
    )

    get "/api/traces", params: { minutes: 30 }

    assert_response :success
    payload = json_response["traces"].first["context"]

    # input_tokens is exactly what the provider read for this call.
    assert_equal 118_000, payload["used"]
    assert_equal 128_000, payload["limit"]
    assert_equal "critical", payload["state"]
    assert_equal 32_000, payload["cached"]
  end

  test "index falls back to trace tokens when no generation was recorded" do
    create_trace

    get "/api/traces", params: { minutes: 30 }

    payload = json_response["traces"].first["context"]

    assert_equal 10, payload["used"]
    assert_equal "ok", payload["state"]
  end

  test "show adds the per-source breakdown for the drilled-in trace" do
    trace = create_trace
    agent = create_agent(user: @user, name: "Support Bot")
    context = AgentContext.create!(
      contextable: agent, agent_name: "SupportAgent", action_name: "respond",
      instructions: "You answer support questions."
    )
    context.add_user_message("How do I reset my password?")
    context.generations.create!(
      model: "gpt-4o-mini", input_tokens: 20_000, output_tokens: 300,
      finish_reason: "stop", trace_id: trace.trace_id
    )

    get "/api/traces/#{trace.id}"

    assert_response :success
    payload = json_response["trace"]["context"]

    assert_equal 20_000, payload["used"]
    assert_equal payload["used"], payload["segments"].sum { |segment| segment["tokens"] }
    assert payload["segments"].any? { |segment| segment["key"] == "instructions" }
  end

  test "show 404s for other accounts' traces" do
    other = create_trace(account: create_account(owner: create_user))

    get "/api/traces/#{other.id}"

    assert_response :not_found
  end

  test "requires authentication" do
    delete "/session"
    get "/api/traces"

    assert_response :redirect
  end
end
