# frozen_string_literal: true

# One execution of an Evaluation over a sample of the agent's generations.
# scores: { criterion_key => { "score", "min", "max", "passed", "total" } }
# Comparison runs instead store a cohort map per criterion,
# { criterion_key => { model => { "score", ... } } }, plus underscore-prefixed
# metadata keys ("_missing_models" — an Array, "_verdict" — a Hash) that are
# not criterion stats at all.
class EvaluationRun < ApplicationRecord
  belongs_to :evaluation
  belongs_to :account, optional: true

  enum :status, { pending: 0, running: 1, complete: 2, failed: 3 }

  scope :recent, -> { order(created_at: :desc) }

  def self.links_for_trace(trace)
    matches = [
      { results: [ { metadata: { trace_id: trace.trace_id } } ] },
      { results: [ { metadata: { judge_trace_ids: [ trace.trace_id ] } } ] },
      { metadata: { judge_trace_ids: [ trace.trace_id ] } }
    ]
    where(account_id: trace.account_id)
      .where(matches.map { "external_report @> ?::jsonb" }.join(" OR "), *matches.map(&:to_json))
      .recent.limit(20).map do |run|
        { run_id: run.external_run_id, evaluation_id: run.evaluation_id, id: run.id,
          url: "/dashboard/evaluations?evaluation=#{run.evaluation_id}&run=#{run.id}" }
      end
  end

  def average_score
    values = external_report ? external_report.fetch("results").filter_map { |result| result["score"] } : criterion_scores
    return nil if values.empty?

    (values.sum.to_f / values.size).round(3)
  end

  private

  # Every recorded criterion score, flattening comparison runs' per-model
  # cohort maps. Skips metadata keys and any non-stat value so a payload like
  # scores["_missing_models"] = ["gpt-4o"] cannot raise. The scores column is
  # nullable, so a NULL row falls back to an empty payload.
  def criterion_scores
    (scores || {})
      .reject { |key, _| key.to_s.start_with?("_") }
      .values
      .select { |stats| stats.is_a?(Hash) }
      .flat_map do |stats|
        if stats.key?("score")
          [ stats["score"] ]
        else
          stats.values.filter_map { |cohort| cohort["score"] if cohort.is_a?(Hash) }
        end
      end
      .compact
  end
end
