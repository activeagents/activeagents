# frozen_string_literal: true

module Api
  # Read API for telemetry traces, backing the dashboard Traces view.
  #
  # Query logic mirrors the gem's ActiveAgent::Dashboard::TracesController
  # (same scopes on ActiveAgent::TelemetryTrace), scoped to the current
  # account for the hosted platform.
  class TracesController < BaseController
    before_action :require_account!

    DEFAULT_WINDOW_MINUTES = 60
    MAX_WINDOW_MINUTES = 60 * 24 * 90
    DEFAULT_LIMIT = 500

    # GET /api/traces
    def index
      window = params.fetch(:minutes, DEFAULT_WINDOW_MINUTES).to_i.clamp(1, MAX_WINDOW_MINUTES)
      window_scope = traces_scope.for_date_range(window.minutes.ago, Time.current)

      scope = window_scope
      scope = scope.for_agent(params[:agent]) if params[:agent].present?
      scope = scope.for_service(params[:service]) if params[:service].present?
      scope = scope.with_errors if params[:status] == "error"

      limit = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, 1000)
      traces = scope.recent.limit(limit)

      render json: {
        traces: traces.map { |trace| TelemetryTraceSerializer.summary(trace) },
        agents: window_scope.distinct.pluck(:agent_class).compact.sort,
        window_minutes: window
      }
    end

    # GET /api/traces/:id — accepts the record id or the OTel trace_id
    # (full or 8-char short form), so generation refs can deep-link.
    def show
      trace = traces_scope.find_by(trace_id: params[:id]) ||
        traces_scope.where("trace_id LIKE ?", "#{TelemetryTrace.sanitize_sql_like(params[:id].to_s)}%").first ||
        traces_scope.find(params[:id])
      render json: { trace: TelemetryTraceSerializer.detail(trace) }
    end

    private

    def traces_scope
      TelemetryTrace.for_account(current_account)
    end
  end
end
