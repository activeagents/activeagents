# frozen_string_literal: true

require "test_helper"

class EvaluationRunnerServiceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Eval Bot")
    @context = AgentContext.create!(contextable: @agent, agent_name: "EvalBotAgent", action_name: "ask")
  end

  def create_generation(content: "A sufficiently long answer with plenty of substance here.", output_tokens: 50, duration: 0.5)
    @context.generations.create!(
      content: content, model: "mock-model", input_tokens: 20,
      output_tokens: output_tokens, duration_seconds: duration, finish_reason: "stop"
    )
  end

  def build_evaluation(criteria)
    @agent.evaluations.create!(name: "Eval #{SecureRandom.hex(3)}", criteria: criteria, sample_size: 10)
  end

  test "scores rule-based criteria against real generations" do
    2.times { create_generation }
    create_generation(content: "short", output_tokens: 2000, duration: 20)

    run = build_evaluation([
      { "key" => "response_present", "type" => "response_present", "config" => {} },
      { "key" => "response_length", "type" => "min_length", "config" => { "chars" => 40 } },
      { "key" => "latency", "type" => "max_latency_ms", "config" => { "ms" => 5000 } },
      { "key" => "token_budget", "type" => "token_budget", "config" => { "output_tokens" => 1000 } }
    ]).run!

    assert run.complete?
    assert_equal 3, run.samples_evaluated
    assert_equal 1.0, run.scores.dig("response_present", "score")
    assert_operator run.scores.dig("response_length", "score"), :<, 1.0
    assert_operator run.scores.dig("latency", "score"), :<, 1.0
    assert_operator run.scores.dig("token_budget", "score"), :<, 1.0
    assert_equal 2, run.samples_passed
    assert run.average_score.between?(0.0, 1.0)
  end

  test "contains and not_contains criteria" do
    create_generation(content: "Please reset your password via the emailed link.")
    create_generation(content: "I cannot help with that.")

    run = build_evaluation([
      { "key" => "mentions_reset", "type" => "contains", "config" => { "pattern" => "reset" } },
      { "key" => "no_refusals", "type" => "not_contains", "config" => { "pattern" => "cannot help" } }
    ]).run!

    assert_equal 0.5, run.scores.dig("mentions_reset", "score")
    assert_equal 0.5, run.scores.dig("no_refusals", "score")
  end

  test "llm_judge is skipped without provider credentials" do
    create_generation

    run = build_evaluation([
      { "key" => "response_present", "type" => "response_present", "config" => {} },
      { "key" => "quality", "type" => "llm_judge", "config" => { "prompt" => "Helpful?" } }
    ]).run!

    assert run.complete?
    assert run.scores.dig("quality", "skipped")
    assert_match(/provider credentials/, run.scores.dig("quality", "reason"))
    assert_equal 1.0, run.scores.dig("response_present", "score")
  end

  test "fails cleanly when the agent has no generations" do
    run = build_evaluation([ { "key" => "response_present", "type" => "response_present", "config" => {} } ]).run!

    assert run.failed?
    assert_match(/No generations/, run.error_message)
  end
end
