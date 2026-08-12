# frozen_string_literal: true

# Per-agent scorecard stats for the dashboard's agent cards, computed with
# grouped queries (no per-agent N+1) over two sources:
#
# * agent_runs — executions the platform itself ran, and
# * active_agent_telemetry_traces — executions reported by an SDK in the
#   customer's own app, attributed to an Agent by AgentRegistrar.
#
# Agents discovered by observation (status: :observed) only ever have the
# second kind, so a runs-only scorecard reported 0 for every tile while the
# Traces view showed real traffic.
#
# A platform run writes BOTH an AgentRun and a trace sharing a trace_id, so
# traces are counted only when no AgentRun claims the same trace_id —
# otherwise every platform execution would count twice.
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

    trace_stats = telemetry_stats(ids, window_start)
    trace_last = unclaimed_traces(ids, nil).group(:agent_id).maximum(:timestamp)

    ids.index_with do |id|
      runs = run_counts[id].to_i
      stats = trace_stats[id] || {}
      traced = stats[:count].to_i
      total = runs + traced
      succeeded = completed_counts[id].to_i + stats[:ok].to_i
      eval_run = eval_runs[id]

      {
        window_days: (WINDOW / 1.day).to_i,
        runs: total,
        # Which sources contributed, so the UI can say where numbers came from.
        run_sources: run_sources(runs, traced),
        success_rate: total.positive? ? (succeeded * 100.0 / total).round(1) : nil,
        avg_duration_ms: blended_duration(avg_durations[id], runs, stats[:avg_duration], traced),
        tokens: token_sums[id].to_i + stats[:tokens].to_i,
        eval_score: eval_run&.average_score,
        eval_samples_passed: eval_run&.samples_passed,
        eval_samples_evaluated: eval_run&.samples_evaluated,
        last_run_at: [ last_runs[id], trace_last[id] ].compact.max&.iso8601
      }
    end
  end

  # Count, success, latency and tokens for SDK-reported executions, in one
  # grouped query (FILTER keeps it to a single pass over the window).
  def self.telemetry_stats(agent_ids, window_start)
    rows = unclaimed_traces(agent_ids, window_start)
      .group("active_agent_telemetry_traces.agent_id")
      .pluck(
        Arel.sql("active_agent_telemetry_traces.agent_id"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE active_agent_telemetry_traces.status <> 'ERROR')"),
        Arel.sql("AVG(active_agent_telemetry_traces.total_duration_ms)"),
        Arel.sql(
          "SUM(COALESCE(total_input_tokens, 0) + COALESCE(total_output_tokens, 0) + " \
          "COALESCE(total_thinking_tokens, 0))"
        )
      )

    rows.to_h do |agent_id, count, ok, avg_duration, tokens|
      [ agent_id, { count: count, ok: ok, avg_duration: avg_duration, tokens: tokens } ]
    end
  end
  private_class_method :telemetry_stats

  # Traces attributed to these agents that no AgentRun already accounts for.
  # window_start nil scans all time (used for "last activity"). Shared with
  # AgentExecutions so the cards, the list and the counts never disagree.
  def self.unclaimed_traces(agent_ids, window_start)
    AgentExecutions.unclaimed_traces(agent_ids, since: window_start)
  end
  private_class_method :unclaimed_traces

  def self.run_sources(runs, traced)
    sources = []
    sources << "platform" if runs.positive?
    sources << "telemetry" if traced.positive?
    sources
  end
  private_class_method :run_sources

  # Duration averages weight by how many executions each source contributed,
  # so a blend of platform runs and traces isn't skewed by the smaller set.
  def self.blended_duration(run_avg, runs, trace_avg, traced)
    weighted = (run_avg.to_f * runs) + (trace_avg.to_f * traced)
    counted = (run_avg ? runs : 0) + (trace_avg ? traced : 0)
    return nil if counted.zero?

    (weighted / counted).round
  end
  private_class_method :blended_duration

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
