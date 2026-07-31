# frozen_string_literal: true

# Per-agent scorecard stats for the dashboard's agent cards, computed with
# grouped queries (no per-agent N+1) over the solid_agent datasets:
# agent_runs for volume/success/latency/tokens and evaluation_runs for the
# latest quality score. Platform runs write telemetry-correlated records
# (AgentRun#trace_id == TelemetryTrace#trace_id), so these numbers agree
# with the Traces/Metrics views.
class AgentScorecard
  WINDOW = 30.days

  # @param agents [Enumerable<Agent>]
  # @return [Hash{Integer => Hash}] agent_id => stats
  def self.for_agents(agents)
    ids = agents.map(&:id)
    return {} if ids.empty?

    window_start = WINDOW.ago
    windowed = AgentRun.where(agent_id: ids, created_at: window_start..)

    run_counts = windowed.group(:agent_id).count
    completed_counts = windowed.where(status: :complete).group(:agent_id).count
    avg_durations = windowed.where.not(duration_ms: nil).group(:agent_id).average(:duration_ms)
    token_sums = windowed.group(:agent_id).sum("COALESCE(total_tokens, 0)")
    last_runs = AgentRun.where(agent_id: ids).group(:agent_id).maximum(:created_at)
    eval_runs = latest_evaluation_runs(ids)

    ids.index_with do |id|
      runs = run_counts[id].to_i
      completed = completed_counts[id].to_i
      eval_run = eval_runs[id]

      {
        window_days: (WINDOW / 1.day).to_i,
        runs: runs,
        success_rate: runs.positive? ? (completed * 100.0 / runs).round(1) : nil,
        avg_duration_ms: avg_durations[id]&.round,
        tokens: token_sums[id].to_i,
        eval_score: eval_run&.average_score,
        eval_samples_passed: eval_run&.samples_passed,
        eval_samples_evaluated: eval_run&.samples_evaluated,
        last_run_at: last_runs[id]&.iso8601
      }
    end
  end

  # Latest complete evaluation run per agent, one query via DISTINCT ON.
  def self.latest_evaluation_runs(agent_ids)
    EvaluationRun.complete.joins(:evaluation)
      .where(evaluations: { agent_id: agent_ids })
      .select("DISTINCT ON (evaluations.agent_id) evaluation_runs.*, evaluations.agent_id AS scored_agent_id")
      .order("evaluations.agent_id, evaluation_runs.created_at DESC")
      .index_by { |run| run[:scored_agent_id] }
  end
  private_class_method :latest_evaluation_runs
end
