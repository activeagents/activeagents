# frozen_string_literal: true

module Api
  # Read API for telemetry metrics, backing the dashboard Metrics view.
  #
  # Exposes the same aggregates as the gem dashboard's metrics page
  # (ActiveAgent::Dashboard::TracesController#metrics / #calculate_metrics /
  # #agent_statistics): trace counts, token totals, average duration, error
  # rate, active agents and per-agent statistics — account-scoped, plus
  # previous-period deltas for trend indicators.
  class MetricsController < BaseController
    before_action :require_account!

    DEFAULT_WINDOW_HOURS = 24
    MAX_WINDOW_HOURS = 24 * 30

    # GET /api/metrics
    def show
      hours = params.fetch(:hours, DEFAULT_WINDOW_HOURS).to_i.clamp(1, MAX_WINDOW_HOURS)
      now = Time.current

      current = traces_scope.for_date_range(hours.hours.ago(now), now)
      previous = traces_scope.for_date_range((hours * 2).hours.ago(now), hours.hours.ago(now))

      render json: {
        summary: summary_for(current, previous),
        hourly_requests: hourly_requests(current, hours, now),
        by_agent: agent_statistics(current),
        window_hours: hours
      }
    end

    private

    def traces_scope
      TelemetryTrace.for_account(current_account)
    end

    # Same definitions as the gem dashboard's calculate_metrics, with
    # previous-period percentage changes layered on top.
    def summary_for(current, previous)
      total = current.count
      previous_total = previous.count

      input_tokens = current.sum(:total_input_tokens)
      output_tokens = current.sum(:total_output_tokens)
      thinking_tokens = current.sum(:total_thinking_tokens)

      avg_latency = current.average(:total_duration_ms)&.round(0)
      previous_avg_latency = previous.average(:total_duration_ms)&.round(0)

      error_rate = total.positive? ? (current.with_errors.count.to_f / total * 100).round(2) : 0.0

      {
        total_requests: total,
        requests_change: percent_change(previous_total, total),
        avg_latency_ms: avg_latency || 0,
        latency_change: percent_change(previous_avg_latency, avg_latency),
        error_rate: error_rate,
        errors: current.with_errors.count,
        unique_agents: current.distinct.count(:agent_class),
        tokens_used: input_tokens + output_tokens + thinking_tokens,
        tokens_input: input_tokens,
        tokens_output: output_tokens,
        tokens_thinking: thinking_tokens
      }
    end

    def hourly_requests(scope, hours, now)
      counts = scope.group(Arel.sql("date_trunc('hour', timestamp)")).count.transform_keys(&:to_i)
      latencies = scope.group(Arel.sql("date_trunc('hour', timestamp)")).average(:total_duration_ms).transform_keys(&:to_i)

      start_hour = (now - (hours - 1).hours).beginning_of_hour
      (0...hours).map do |offset|
        bucket = start_hour + offset.hours
        {
          hour: bucket.strftime("%H:00"),
          timestamp: bucket.iso8601,
          count: counts[bucket.to_i] || 0,
          avg_latency_ms: latencies[bucket.to_i]&.round(0) || 0,
          active: offset == hours - 1
        }
      end
    end

    # Mirrors the gem dashboard's agent_statistics grouped query.
    def agent_statistics(scope)
      scope
        .where.not(agent_class: nil)
        .group(:agent_class)
        .select(
          "agent_class",
          "COUNT(*) AS trace_count",
          "SUM(total_input_tokens + total_output_tokens + total_thinking_tokens) AS token_sum",
          "AVG(total_duration_ms) AS avg_duration",
          "SUM(CASE WHEN status = 'ERROR' THEN 1 ELSE 0 END) AS error_count"
        )
        .order(Arel.sql("trace_count DESC"))
        .map do |row|
          {
            name: row.agent_class,
            requests: row.trace_count,
            tokens: row.token_sum.to_i,
            avg_duration_ms: row.avg_duration&.round(0) || 0,
            errors: row.error_count.to_i
          }
        end
    end

    def percent_change(previous, current)
      return nil if previous.nil? || current.nil? || previous.to_f.zero?

      (((current.to_f - previous.to_f) / previous.to_f) * 100).round(1)
    end
  end
end
