# frozen_string_literal: true

require "test_helper"

class Api::V1::TracesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  def ingest_payload(trace_id: SecureRandom.hex(16))
    {
      traces: [
        {
          trace_id: trace_id,
          service_name: "customer-app",
          environment: "production",
          timestamp: Time.current.iso8601(6),
          resource_attributes: {},
          spans: [
            {
              span_id: "root1", parent_span_id: nil, name: "SupportAgent.respond",
              type: "root", duration_ms: 900.0, status: "OK",
              attributes: { "agent.class" => "SupportAgent", "agent.action" => "respond" },
              tokens: { input: 100, output: 50, thinking: 0, total: 150 }
            }
          ]
        }
      ],
      sdk: { name: "activeagent", version: "1.0.3", language: "ruby" }
    }
  end

  test "rejects requests without an API key" do
    post "/v1/traces", params: ingest_payload, as: :json

    assert_response :unauthorized
    assert_equal "Missing Authorization header", json_response["error"]
  end

  test "rejects requests with an invalid API key" do
    post "/v1/traces", params: ingest_payload, as: :json,
      headers: { "Authorization" => "Bearer wrong" }

    assert_response :unauthorized
    assert_equal "Invalid API key", json_response["error"]
  end

  test "accepts traces and processes them for the authenticated account" do
    trace_id = SecureRandom.hex(16)

    perform_enqueued_jobs do
      post "/v1/traces", params: ingest_payload(trace_id: trace_id), as: :json,
        headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }
    end

    assert_response :accepted
    trace = TelemetryTrace.find_by(trace_id: trace_id)
    assert_equal @account, trace.account
    assert_equal "SupportAgent", trace.agent_class
    assert_equal 100, trace.total_input_tokens
  end

  test "ingestion is idempotent per trace_id" do
    trace_id = SecureRandom.hex(16)

    perform_enqueued_jobs do
      2.times do
        post "/v1/traces", params: ingest_payload(trace_id: trace_id), as: :json,
          headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }
      end
    end

    assert_equal 1, TelemetryTrace.where(trace_id: trace_id).count
  end

  test "enforces the plan trace quota" do
    # Shrink the free-plan limit so a single existing trace exhausts the quota.
    original = Account::TRACE_LIMITS
    Account.send(:remove_const, :TRACE_LIMITS)
    Account.const_set(:TRACE_LIMITS, original.merge("free" => 1).freeze)

    TelemetryTrace.create_from_payload(
      ingest_payload[:traces].first.deep_stringify_keys, {}, account: @account
    )

    post "/v1/traces", params: ingest_payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :too_many_requests
  ensure
    Account.send(:remove_const, :TRACE_LIMITS)
    Account.const_set(:TRACE_LIMITS, original)
  end

  test "alias route under /api/v1 also works" do
    post "/api/v1/traces", params: ingest_payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :accepted
  end
end
