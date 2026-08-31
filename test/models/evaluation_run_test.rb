# frozen_string_literal: true

require "test_helper"

class EvaluationRunTest < ActiveSupport::TestCase
  def create_evaluation(**attrs)
    user = create_user
    agent = create_agent(user: user)
    defaults = {
      name: "Eval #{SecureRandom.hex(3)}",
      criteria: [ { "key" => "response_present", "type" => "response_present", "config" => {} } ]
    }
    agent.evaluations.create!(defaults.merge(attrs))
  end

  def create_evaluation_run(scores:, **attrs)
    create_evaluation.evaluation_runs.create!({ status: :complete, scores: scores }.merge(attrs))
  end

  # ===========================================
  # average_score
  # ===========================================

  test "average_score averages per-criterion stat hashes" do
    run = create_evaluation_run(scores: {
      "response_present" => { "score" => 1.0, "passed" => 3, "total" => 3 },
      "min_length" => { "score" => 0.5, "passed" => 1, "total" => 2 }
    })

    assert_in_delta 0.75, run.average_score, 0.0001
  end

  test "average_score is nil when no criterion recorded a score" do
    run = create_evaluation_run(scores: {
      "llm_judge" => { "skipped" => true, "reason" => "no provider key configured" }
    })

    assert_nil run.average_score
  end

  test "average_score is nil for an empty scores payload" do
    assert_nil create_evaluation_run(scores: {}).average_score
  end

  # Regression: a comparison run stores scores["_missing_models"] as an Array
  # alongside the per-criterion cohort maps. Calling Array#[] with the String
  # "score" raised TypeError, permanently 500ing GET /api/evaluations for the
  # whole account (issue #108).
  test "average_score ignores _missing_models metadata and averages cohort maps" do
    run = create_evaluation_run(scores: {
      "_missing_models" => [ "gpt-4o" ],
      "_verdict" => { "winner" => "gpt-4o-mini", "rationale" => "Higher scores across both KPIs." },
      "response_present" => {
        "gpt-4o-mini" => { "score" => 1.0, "passed" => 3, "total" => 3 },
        "claude-haiku" => { "score" => 0.6, "passed" => 2, "total" => 3 }
      },
      "min_length" => {
        "gpt-4o-mini" => { "score" => 0.8, "passed" => 2, "total" => 3 },
        "claude-haiku" => { "skipped" => true, "reason" => "no samples scored" }
      }
    })

    average = nil
    assert_nothing_raised { average = run.average_score }
    # (1.0 + 0.6 + 0.8) / 3 — the skipped cohort contributes nothing.
    assert_in_delta 0.8, average, 0.0001
  end

  test "average_score is nil when a comparison run only recorded metadata" do
    run = create_evaluation_run(scores: { "_missing_models" => [ "gpt-4o", "claude-haiku" ] })

    assert_nil run.average_score
  end
end
