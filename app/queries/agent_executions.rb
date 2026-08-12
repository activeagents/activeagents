# frozen_string_literal: true

# One agent execution, whoever ran it.
#
# The platform records executions it initiates as AgentRun rows; agents
# running inside a customer's own app only ever produce a TelemetryTrace.
# They are the same grain — one attempt at one agent action — so the
# dashboard treats them as one list with a `source` discriminator rather
# than as two competing tabs:
#
#   dashboard — an AgentRun (we executed it; has lifecycle, logs, cancel)
#   reported  — a trace no AgentRun claims (their app executed it)
#
# A platform execution usually writes BOTH an AgentRun and a trace sharing a
# trace_id, so traces are counted only when unclaimed. The reverse is not
# symmetric: a run that fails before its root span exists has no trace at
# all, which is why runs — not traces — are the authoritative source when
# both exist.
#
# Distinct from AgentContext, which is a *stream*: one durable conversation
# per agent action that many executions append to. A stream is a parent of
# executions, not an alternative to them.
class AgentExecutions
  SOURCES = %w[dashboard reported].freeze

  Row = Struct.new(
    :id, :source, :status, :occurred_at, :duration_ms, :tokens,
    :trace_id, :agent_id, :action_name, :provider, :model,
    :input_preview, :output_preview, :error_message,
    keyword_init: true
  ) do
    def as_json(*)
      to_h.transform_values { |value| value.is_a?(Time) ? value.iso8601(3) : value }
    end

    # Runs are addressable by record id; reported executions only by trace.
    def to_param
      source == "dashboard" ? id.to_s : "trace-#{id}"
    end
  end

  # @param agents [ActiveRecord::Relation, Array<Agent>] scope to these agents
  # @param account [Account, nil] required to read reported traces
  # @param window_minutes [Integer, nil] nil means all time
  # @param source [String, nil] "dashboard" | "reported" | nil for both
  # @param status [String, nil] AgentRun status; also filters reported by OK/ERROR
  def initialize(agents:, account: nil, window_minutes: nil, source: nil, status: nil)
    @agent_ids = Array(agents.respond_to?(:pluck) ? agents.pluck(:id) : agents.map(&:id))
    @account = account
    @window_minutes = window_minutes
    @source = source.presence
    @status = status.presence
  end

  # Newest first, across both sources.
  def page(page: 1, per_page: 20)
    all = rows.sort_by { |row| row.occurred_at || Time.at(0) }.reverse
    offset = (page.to_i - 1) * per_page.to_i
    { rows: all[offset, per_page.to_i] || [], total: all.size }
  end

  def rows
    @rows ||= (include_dashboard? ? run_rows : []) + (include_reported? ? trace_rows : [])
  end

  # Traces attributed to these agents that no AgentRun already accounts for.
  # Shared with AgentScorecard so every surface counts the same executions.
  def self.unclaimed_traces(agent_ids, since: nil, account: nil)
    scope = TelemetryTrace.where(agent_id: agent_ids)
    scope = scope.for_account(account) if account
    scope = scope.where(timestamp: since..) if since
    scope
      .joins(<<~SQL.squish)
        LEFT JOIN agent_runs
          ON agent_runs.trace_id = active_agent_telemetry_traces.trace_id
         AND agent_runs.agent_id = active_agent_telemetry_traces.agent_id
      SQL
      .where(agent_runs: { id: nil })
  end

  private

  def include_dashboard? = @source.nil? || @source == "dashboard"
  def include_reported? = (@source.nil? || @source == "reported") && @account.present?

  def since = @window_minutes ? @window_minutes.to_i.minutes.ago : nil

  def run_rows
    scope = AgentRun.where(agent_id: @agent_ids)
    scope = scope.where(created_at: since..) if since
    scope = scope.where(status: @status) if @status

    scope.map do |run|
      Row.new(
        id: run.id,
        source: "dashboard",
        status: run.status,
        occurred_at: run.created_at,
        duration_ms: run.calculated_duration_ms,
        tokens: run.total_tokens.to_i,
        trace_id: run.trace_id,
        agent_id: run.agent_id,
        action_name: run.action_name,
        provider: run.output_metadata&.dig("provider"),
        model: run.output_metadata&.dig("model"),
        input_preview: run.input_prompt.to_s.truncate(160),
        output_preview: run.output.to_s.truncate(160).presence,
        error_message: run.error_message
      )
    end
  end

  def trace_rows
    scope = self.class.unclaimed_traces(@agent_ids, since: since, account: @account)
    # A run status filter has no exact analogue on a trace; map the two that
    # do rather than silently ignoring the filter.
    scope = scope.where(status: "ERROR") if @status == "failed"
    scope = scope.where.not(status: "ERROR") if @status == "complete"
    return [] if @status.present? && !%w[failed complete].include?(@status)

    scope.map do |trace|
      Row.new(
        id: trace.id,
        source: "reported",
        status: trace.status == "ERROR" ? "failed" : "complete",
        occurred_at: trace.timestamp,
        duration_ms: trace.total_duration_ms&.round,
        tokens: trace.total_tokens.to_i,
        trace_id: trace.trace_id,
        agent_id: trace.agent_id,
        action_name: trace.agent_action,
        provider: trace.provider,
        model: trace.model,
        input_preview: nil,
        output_preview: nil,
        error_message: trace.error_message
      )
    end
  end
end
