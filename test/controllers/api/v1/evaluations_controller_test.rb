# frozen_string_literal: true

require "test_helper"

class Api::V1::EvaluationsControllerTest < ActionDispatch::IntegrationTest
  Evals = ActiveAgent::Evals

  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  # A report as ActiveAgent::Evals::Publisher sends it: two scenarios under two
  # models, the second model failing one of them.
  def envelope(run_id: "run-#{SecureRandom.hex(4)}", answer: "Order 1234 shipped on Monday.")
    specs = [
      Evals::ModelSpec.new(label: "gpt-5-mini", provider: "openai", model: "gpt-5-mini"),
      Evals::ModelSpec.new(label: "openrouter/anthropic/claude-sonnet-5", provider: "openrouter", model: "anthropic/claude-sonnet-5")
    ]
    scenarios = [
      Evals::Scenario.from_hash({ "key" => "status_1", "group" => "status", "prompt" => "Where is order 1234?" }),
      Evals::Scenario.from_hash({ "key" => "refund_1", "group" => "refunds", "prompt" => "Can I get a refund for order 1234?" })
    ]
    results = scenarios.product(specs).each_with_index.map do |(scenario, spec), index|
      failing = scenario.key == "refund_1" && spec.provider == "openrouter"
      Evals::Result.new(
        scenario: scenario,
        spec: spec,
        replay: Evals::Replay.new(
          answer: failing ? "I don't have access to refunds." : answer,
          tool_calls: [ { "name" => "lookup_order", "arguments" => { "order_id" => "1234" } } ],
          duration_ms: 1200, input_tokens: 100, output_tokens: 20, cost: 0.0004,
          metadata: { "run_id" => run_id, "result_id" => "result-#{index}", "trace_id" => "trace#{index}", "judge_trace_ids" => [ "judge#{index}" ] }
        ),
        scores: { "response_present" => 1.0 },
        score: failing ? 0.2 : 1.0,
        status: failing ? "failed" : "passed",
        diagnosis: failing ? { "fault" => "missing_capability", "summary" => "Declined", "recommendation" => "Add a refund tool" } : nil
      )
    end
    report = Evals::Report.new(
      results: results, models: specs, judge_label: "gpt-5-mini",
      metadata: { "run_id" => run_id, "suite" => "orders", "scope" => "eu", "role" => "support" }
    )

    { "version" => 1, "run_id" => run_id, "source" => "support-app", "agent_name" => "SupportBot", "suite" => "orders", "report" => report.to_h }
  end

  def publish(payload, token: @account.telemetry_api_key)
    post "/v1/evaluations", params: payload.to_json,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  test "rejects a request without an API key" do
    post "/v1/evaluations", params: envelope.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_equal "Missing Authorization header", json_response["error"]
  end

  test "rejects an unknown API key" do
    publish(envelope, token: "wrong")

    assert_response :unauthorized
    assert_equal "Invalid API key", json_response["error"]
  end

  test "stores the report as the dashboard's own evaluation rows and returns the publisher's receipt" do
    payload = envelope
    publish(payload)

    assert_response :created
    run = EvaluationRun.find(json_response["id"])
    assert_equal payload["run_id"], json_response["run_id"], "the receipt echoes the run_id"
    assert_equal "complete", json_response["status"]
    assert_equal run.evaluation_id, json_response["evaluation_id"]
    assert_equal false, json_response["duplicate"]
    assert_equal "/dashboard/evaluations?evaluation=#{run.evaluation_id}&run=#{run.id}", json_response["url"]

    evaluation = run.evaluation
    assert_equal "orders (eu, support)", evaluation.name, "the report's scope names the evaluation"
    assert_equal "llm", evaluation.judge_kind
    assert_equal %w[status_1 refund_1], evaluation.scenarios.ordered.pluck(:key)

    agent = evaluation.agent
    assert agent.observed?, "the reporting application's agent is read-only here"
    assert_equal [ @user.id, "support-app", "SupportBot", nil ], [ agent.user_id, agent.service_name, agent.agent_class_name, agent.action_name ]

    assert_equal [ 4, 3 ], [ run.samples_evaluated, run.samples_passed ]
    assert_equal [ "gpt-5-mini", "openrouter/anthropic/claude-sonnet-5" ], run.models
    failing = run.scenario_results.find_by(model: "anthropic/claude-sonnet-5", status: :failed)
    assert_equal "missing_capability", failing.fault
    assert_equal "Add a refund tool", failing.recommendation
    assert_equal "trace3", failing.replay_metadata["trace_id"], "the result keeps the trace it links to"
  end

  test "stores a run the engine can rebuild into the same report" do
    payload = envelope
    publish(payload)

    rebuilt = EvaluationRun.find(json_response["id"]).to_report.to_h
    assert_equal payload.dig("report", "models").keys, rebuilt["models"].keys
    assert_equal payload.dig("report", "results").map { |result| result.values_at("scenario_key", "label", "status") }.sort,
      rebuilt["results"].map { |result| result.values_at("scenario_key", "label", "status") }.sort
  end

  test "authenticates a generated API key" do
    api_key = @account.api_keys.create!(name: "support-app")
    publish(envelope, token: api_key.token)

    assert_response :created
    assert api_key.reload.last_used_at.present?, "expected the import to record key usage"
  end

  test "returns the stored run for an identical retry" do
    payload = envelope
    publish(payload)
    first_id = json_response["id"]

    assert_no_difference -> { EvaluationRun.count } do
      publish(payload)
    end
    assert_response :ok
    assert_equal [ first_id, true ], json_response.values_at("id", "duplicate")
  end

  test "refuses different content under a stored run_id" do
    publish(envelope(run_id: "run-fixed"))
    publish(envelope(run_id: "run-fixed", answer: "Order 1234 is delayed."))

    assert_response :conflict
  end

  test "keeps runs of one account apart from another account's same run_id" do
    publish(envelope(run_id: "run-shared"))
    other = create_account(owner: create_user)
    publish(envelope(run_id: "run-shared"), token: other.telemetry_api_key)

    assert_response :created
  end

  test "adds a later run to the same evaluation and scenarios" do
    publish(envelope)
    evaluation_id = json_response["evaluation_id"]
    publish(envelope)

    assert_response :created
    assert_equal evaluation_id, json_response["evaluation_id"]
    assert_equal 2, Evaluation.find(evaluation_id).evaluation_runs.count
    assert_equal 2, Evaluation.find(evaluation_id).scenarios.count
  end

  test "rejects a report that is not version 1" do
    publish(envelope.merge("version" => 2))

    assert_response :unprocessable_entity
    assert_equal "version must be 1", json_response["error"]
  end

  test "rejects a result whose label names no reported model" do
    payload = envelope
    payload["report"]["results"].first["label"] = "unknown-model"
    publish(payload)

    assert_response :unprocessable_entity
    assert_match "missing from report.models", json_response["error"]
  end

  test "rejects an unknown fault" do
    payload = envelope
    payload["report"]["results"].first["fault"] = "gremlins"
    publish(payload)

    assert_response :unprocessable_entity
  end

  test "rejects a body that is not JSON" do
    post "/v1/evaluations", params: "{not json",
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}", "Content-Type" => "application/json" }

    assert_response :bad_request
  end

  test "rejects a report over the size limit" do
    payload = envelope
    payload["report"]["results"].first["answer"] = "x" * (ExternalEvaluationImport::MAX_BYTES + 1)
    publish(payload)

    assert_response :content_too_large
  end

  test "serves the same route under the /api prefix" do
    post "/api/v1/evaluations", params: envelope.to_json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}", "Content-Type" => "application/json" }

    assert_response :created
  end
end
