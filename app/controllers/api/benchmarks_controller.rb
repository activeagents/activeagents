# frozen_string_literal: true

module Api
  # BenchmarksController — receives benchmark results from ragents/bin/bench
  # and serves them back to the ActiveAgents dashboard.
  #
  # Results are stored in the Rails cache (not the database) so no migration
  # is needed.  The cache key is shared between all processes via Solid Cache.
  # The last 20 benchmark runs are retained.
  class BenchmarksController < BaseController
    skip_before_action :require_authentication, raise: false
    CACHE_KEY    = "ragents:benchmarks:runs"
    MAX_RETAINED = 20

    # GET /api/benchmarks
    # Returns the last MAX_RETAINED benchmark runs, newest first.
    def index
      runs = cached_runs
      render json: {
        runs: runs,
        hardware_summary: latest_hardware(runs),
        strategy_summary: build_strategy_summary(runs)
      }
    end

    # POST /api/benchmarks
    # Accepts JSON body from ragents/bin/bench.
    # No authentication required so bin/bench works without a session cookie.
    def create
      payload = parse_payload
      return render json: { error: "Invalid payload" }, status: :unprocessable_entity if payload.nil?

      run = {
        id:         SecureRandom.hex(6),
        run_at:     payload["run_at"] || Time.now.iso8601,
        hardware:   payload["hardware"],
        config:     payload["config"],
        strategies: payload["strategies"],
        winner:     payload["winner"],
        received_at: Time.now.iso8601
      }

      runs = cached_runs
      runs.unshift(run)
      runs = runs.first(MAX_RETAINED)
      Rails.cache.write(CACHE_KEY, runs, expires_in: 7.days)

      render json: { ok: true, id: run[:id] }, status: :created
    end

    private

    def parse_payload
      body = request.body.read
      return nil if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def cached_runs
      Rails.cache.read(CACHE_KEY) || []
    end

    def latest_hardware(runs)
      runs.first&.dig("hardware") || runs.first&.dig(:hardware)
    end

    def build_strategy_summary(runs)
      return [] if runs.empty?

      # Aggregate average throughput per strategy across all runs
      totals = Hash.new { |h, k| h[k] = { count: 0, throughput_sum: 0, wall_time_sum: 0 } }

      runs.each do |run|
        strategies = run["strategies"] || run[:strategies] || []
        strategies.each do |s|
          name = s["name"] || s[:name]
          totals[name][:count]          += 1
          totals[name][:throughput_sum] += (s["throughput"] || s[:throughput] || 0).to_f
          totals[name][:wall_time_sum]  += (s["wall_time_ms"] || s[:wall_time_ms] || 0).to_f
        end
      end

      totals.map do |name, agg|
        {
          name:              name,
          run_count:         agg[:count],
          avg_throughput:    (agg[:throughput_sum] / agg[:count]).round(2),
          avg_wall_time_ms:  (agg[:wall_time_sum] / agg[:count]).round(1)
        }
      end.sort_by { |s| -s[:avg_throughput] }
    end
  end
end
