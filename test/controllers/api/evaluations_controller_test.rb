# frozen_string_literal: true

require "test_helper"

class Api::EvaluationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Eval Bot")
    context = AgentContext.create!(contextable: @agent, agent_name: "EvalBotAgent", action_name: "ask")
    context.generations.create!(
      content: "A sufficiently long response with plenty of detail included.",
      model: "mock-model", input_tokens: 10, output_tokens: 30, duration_seconds: 0.2, finish_reason: "stop"
    )
    sign_in_as(@user)
  end

  test "create builds an evaluation with default criteria and runs it" do
    post "/dashboard/api/evaluations", params: { evaluation: { agent_id: @agent.id, name: "Quality Check" } }, as: :json

    assert_response :created
    evaluation = json_response["evaluation"]
    assert_equal "Quality Check", evaluation["name"]
    assert_equal "rules", evaluation["judge_kind"]
    assert_operator evaluation["criteria"].length, :>=, 3

    run = evaluation["latest_run"]
    assert_equal "complete", run["status"]
    assert_equal 1, run["samples_evaluated"]
    assert run["scores"].key?("response_present")
  end

  test "create with custom criteria" do
    post "/dashboard/api/evaluations", params: {
      evaluation: {
        agent_id: @agent.id, name: "Contains Check",
        criteria: [ { key: "mentions_detail", type: "contains", config: { pattern: "detail" } } ]
      }
    }, as: :json

    assert_response :created
    assert_equal 1.0, json_response.dig("evaluation", "latest_run", "scores", "mentions_detail", "score")
  end

  test "create rejects invalid criteria types" do
    post "/dashboard/api/evaluations", params: {
      evaluation: { agent_id: @agent.id, name: "Bad", criteria: [ { key: "x", type: "bogus" } ] }
    }, as: :json

    assert_response :unprocessable_entity
  end

  test "index and run rescore" do
    post "/dashboard/api/evaluations", params: { evaluation: { agent_id: @agent.id, name: "Quality" } }, as: :json
    evaluation_id = json_response.dig("evaluation", "id")

    get "/dashboard/api/evaluations"
    assert_equal [ "Quality" ], json_response["evaluations"].map { |e| e["name"] }

    post "/dashboard/api/evaluations/#{evaluation_id}/run"
    assert_response :success
    assert_equal "complete", json_response.dig("run", "status")
    assert_equal 2, Evaluation.find(evaluation_id).evaluation_runs.count
  end

  test "cannot create evaluations for other users' agents" do
    other_agent = create_agent(user: create_user, name: "Not Mine")

    post "/dashboard/api/evaluations", params: { evaluation: { agent_id: other_agent.id, name: "Nope" } }, as: :json

    assert_response :not_found
  end
end
