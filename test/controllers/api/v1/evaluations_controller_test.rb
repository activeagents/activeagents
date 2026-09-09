# frozen_string_literal: true

require "test_helper"

class Api::V1::EvaluationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  def payload
    {
      "version" => 1, "run_id" => "run-123", "source" => "sample-app", "agent_name" => "SupportBot", "suite" => "regression",
      "report" => {
        "models" => { "small" => { "provider" => "openai", "model" => "small" } },
        "judge" => "test-judge", "metadata" => { "scope" => "workspace-a", "judge_trace_ids" => [ "verdict-1" ] },
        "results" => [
          { "scenario_key" => "hello", "group" => "greetings", "label" => "small", "provider" => "openai", "model" => "small",
            "status" => "passed", "score" => 0.9, "scores" => { "quality" => 0.9 }, "answer" => "Hello, world!", "prompt" => "Say hello",
            "duration_ms" => 120, "input_tokens" => 10, "output_tokens" => 5,
            "metadata" => { "result_id" => "result-1", "trace_id" => "trace-1", "judge_trace_ids" => [ "judge-1" ] } },
          { "scenario_key" => "goodbye", "label" => "small", "provider" => "openai", "model" => "small",
            "status" => "failed", "score" => 0.2, "scores" => { "quality" => 0.2 }, "answer" => "Hello", "prompt" => "Say goodbye",
            "fault" => "low_quality", "recommendation" => "Answer the requested greeting.", "metadata" => { "result_id" => "result-2" } }
        ]
      }
    }
  end

  def publish(body = payload, account: @account, path: "/v1/evaluations")
    post path, params: body, as: :json, headers: { "Authorization" => "Bearer #{account.telemetry_api_key}" }
  end

  test "requires a valid bearer credential without browser sign-in" do
    post "/v1/evaluations", params: payload, as: :json
    assert_response :unauthorized
    post "/v1/evaluations", params: payload, as: :json, headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
    key = @account.api_keys.create!(name: "evaluation upload")
    token = key.token
    key.destroy!
    post "/v1/evaluations", params: payload, as: :json, headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
    assert_equal 0, EvaluationRun.count
  end

  test "generated key and API alias import the complete report without executing an agent" do
    key = @account.api_keys.create!(name: "evaluation upload")
    assert_no_difference "AgentRun.count" do
      post "/api/v1/evaluations", params: payload, as: :json, headers: { "Authorization" => "Bearer #{key.token}" }
    end
    assert_response :created
    run = EvaluationRun.find(json_response["id"])
    assert_equal payload["report"], run.external_report
    assert_equal @account, run.account
    assert_equal "complete", run.status
    assert_equal 2, run.samples_evaluated
    assert_equal 1, run.samples_passed
    assert_equal 0.55, run.average_score
    assert run.evaluation.external?
    assert run.evaluation.agent.observed?
    assert_equal "SupportBot", run.evaluation.agent.telemetry_agent_class
    assert key.reload.last_used_at
  end

  test "identical retries including reordered object keys return the same immutable run" do
    publish
    original = json_response
    publish(payload.to_a.reverse.to_h)
    assert_response :ok
    assert_equal true, json_response["duplicate"]
    assert_equal original["id"], json_response["id"]
    assert_equal 1, EvaluationRun.count
    changed = payload
    changed["report"]["results"][0]["answer"] = "Different answer"
    publish(changed)
    assert_response :conflict
    assert_equal payload["report"], EvaluationRun.find(original["id"]).external_report
  end

  test "run identity and grouping are scoped to account including accounts sharing an owner" do
    publish
    first = json_response
    second_account = create_account(owner: @user)
    publish(account: second_account)
    assert_response :created
    second = json_response
    assert_not_equal first["id"], second["id"]
    assert_not_equal first["evaluation_id"], second["evaluation_id"]
    assert_equal 2, EvaluationRun.count
    sign_in_as(@user)
    get "/api/evaluations"
    assert_equal [ first["evaluation_id"] ], json_response["evaluations"].map { |evaluation| evaluation["id"] }
    get "/api/evaluations/#{second['evaluation_id']}/runs/#{second['id']}"
    assert_response :not_found
  end

  test "different source and scope do not combine report histories" do
    publish
    first = json_response
    body = payload
    body["run_id"] = "run-456"
    body["report"]["metadata"]["scope"] = "workspace-b"
    publish(body)
    assert_response :created
    assert_not_equal first["evaluation_id"], json_response["evaluation_id"]
    body["run_id"] = "run-789"
    body["source"] = "another-app"
    publish(body)
    assert_response :created
    assert_equal 3, Evaluation.count
  end

  test "validates result shape grades numeric bounds and trace links atomically" do
    alterations = [
      ->(body) { body["version"] = 2 },
      ->(body) { body["report"] = [] },
      ->(body) { body["report"]["results"] = [] },
      ->(body) { body["report"]["results"][0]["status"] = "success" },
      ->(body) { body["report"]["results"][0]["score"] = 1.1 },
      ->(body) { body["report"]["results"][0]["input_tokens"] = "100" },
      ->(body) { body["report"]["results"][0]["metadata"]["trace_id"] = "javascript:alert(1)" },
      ->(body) { body["report"]["metadata"]["judge_trace_ids"] = "not-an-array" },
      ->(body) { body["report"]["results"] << body["report"]["results"].first.deep_dup },
      ->(body) { body["report"]["models"] = {} },
      ->(body) { body["report"]["metadata"] = false },
      ->(body) { body["report"]["results"][0]["metadata"] = false },
      ->(body) { body["report"]["results"][0]["scores"] = false }
    ]
    alterations.each do |alter|
      body = payload
      alter.call(body)
      publish(body)
      assert_response :unprocessable_entity
    end
    assert_equal 0, Evaluation.count
    assert_equal 0, EvaluationRun.count
    assert_equal 0, Agent.count
  end

  test "rejects oversized requests" do
    body = payload.merge("padding" => "x" * ExternalEvaluationImport::MAX_BYTES)
    publish(body)
    assert_response :payload_too_large
    assert_equal 0, EvaluationRun.count
  end

  test "report details preserve text and metadata while index stays compact and rerun is forbidden" do
    body = payload
    body["report"]["results"][0]["answer"] = '<script>alert("example")</script>'
    publish(body)
    imported = json_response
    sign_in_as(@user)
    get "/api/evaluations"
    summary = json_response["evaluations"].first
    assert_equal "regression", summary["name"]
    assert_equal true, summary["external"]
    assert_not summary["latest_run"].key?("report")
    get "/api/evaluations/#{imported['evaluation_id']}/runs/#{imported['id']}"
    assert_response :success
    assert_equal body["report"], json_response.dig("run", "report")
    post "/api/evaluations/#{imported['evaluation_id']}/run"
    assert_response :unprocessable_entity
    assert_equal 1, EvaluationRun.count
  end

  test "another user cannot read or append to an imported evaluation" do
    publish
    imported = json_response
    other = create_user
    create_account(owner: other)
    sign_in_as(other)
    get "/api/evaluations/#{imported['evaluation_id']}"
    assert_response :not_found
    get "/api/evaluations/#{imported['evaluation_id']}/runs/#{imported['id']}"
    assert_response :not_found
    post "/api/evaluations/#{imported['evaluation_id']}/run"
    assert_response :not_found
  end

  test "trace backlinks cover response judge and verdict traces with account isolation" do
    publish
    imported = json_response
    other_account = create_account(owner: create_user)
    publish(account: other_account)
    %w[trace-1 judge-1 verdict-1].each do |trace_id|
      trace = Struct.new(:account_id, :trace_id).new(@account.id, trace_id)
      assert_equal [ imported["id"] ], EvaluationRun.links_for_trace(trace).map { |link| link[:id] }
    end
    trace = Struct.new(:account_id, :trace_id).new(@account.id, "unrelated")
    assert_empty EvaluationRun.links_for_trace(trace)
  end

  test "authored agent telemetry names keep their existing suffix behavior" do
    agent = create_agent(user: @user, name: "Authored", agent_class_name: "SupportBot")
    assert_equal "SupportBotAgent", agent.telemetry_agent_class
  end

  test "observed imported agents cannot execute or become authored through update" do
    publish
    agent = Evaluation.find(json_response["evaluation_id"]).agent
    assert_raises(Agent::ObservedAgentError) { agent.execute("hello") }
    assert_raises(Agent::ObservedAgentError) { agent.test_execute("hello") }
    sign_in_as(@user)
    %w[execute test].each do |action|
      post "/api/agents/#{agent.id}/#{action}", params: { prompt: "hello", params: {} }, as: :json
      assert_response :unprocessable_entity
    end
    patch "/api/agents/#{agent.id}", params: { agent: { status: "draft" } }, as: :json
    assert_response :unprocessable_entity
    assert agent.reload.observed?
    assert_equal 0, AgentRun.count
    post "/api/agents/#{agent.id}/duplicate", as: :json
    assert_response :created
    assert_equal "draft", json_response.dig("agent", "status")
  end
end
