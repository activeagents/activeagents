# frozen_string_literal: true

module Api
  # BenchmarksController — receives benchmark results from ragents/bin/bench
  # and serves them back to the ActiveAgents dashboard.
  #
  # Results are stored in the Rails cache (not the database) so no migration
  # is needed.  The cache key is shared between all processes via Solid Cache.
  # The last 20 benchmark runs are retained.
  #
  # Every action requires an authenticated session (inherited from
  # ApplicationController's Authentication concern).  The endpoints both
  # trigger real CPU/IO work and write into a process-shared cache that the
  # authenticated dashboard renders, so neither the read nor the writes may be
  # reachable anonymously.
  class BenchmarksController < BaseController
    CACHE_KEY    = "ragents:benchmarks:runs"
    MAX_RETAINED = 20

    # Upper bounds for the knobs that drive real work in the request/job.
    # `cpu_iters` in particular feeds Ragents::Providers::SimulatedProvider's
    # busy loop, so an unclamped value pins a CPU core for as long as it runs.
    MAX_REQUESTS  = 25
    MAX_IO_MS     = 1_000
    MAX_CPU_ITERS = 100_000

    # Above this many requests the run is handed to a background job instead of
    # blocking the Puma worker.
    SYNC_REQUEST_LIMIT = 10

    # The only provider whose work the clamps above actually bound.
    # BenchmarkRunnerService's other providers do work no knob here caps:
    # "realistic" carries its own multi-second latency model that ignores
    # io_ms, and "openai"/"anthropic" spend the deployment's real API keys.
    ALLOWED_PROVIDERS = %w[ mock ].freeze

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

    # POST /api/benchmarks/run
    # Triggers a benchmark run within the Rails application.
    # Useful for running benchmarks in deployed cloud infrastructure.
    def run
      # Ractors are experimental and may not work reliably in Cloud Run.
      # Default to disabled in Cloud Run (production/staging) unless explicitly enabled.
      # Cloud Run sets K_SERVICE environment variable.
      in_cloud_run = ENV["K_SERVICE"].present?
      ractor_default = !in_cloud_run
      include_ractors = if params[:include_ractors].present?
                          params[:include_ractors] == "true"
      else
                          ractor_default
      end

      provider = params[:provider].presence || "mock"
      unless ALLOWED_PROVIDERS.include?(provider)
        return render json: { error: "provider must be one of: #{ALLOWED_PROVIDERS.join(', ')}" },
                      status: :unprocessable_entity
      end

      options = {
        requests: clamped_param(:requests, default: 5, min: 1, max: MAX_REQUESTS),
        io_ms: clamped_param(:io_ms, default: 100, min: 0, max: MAX_IO_MS),
        cpu_iters: clamped_param(:cpu_iters, default: 50_000, min: 0, max: MAX_CPU_ITERS),
        provider: provider,
        include_ractors: include_ractors
      }

      # Run benchmarks (synchronous for small N, async for larger)
      if options[:requests] <= SYNC_REQUEST_LIMIT
        service = BenchmarkRunnerService.new(**options)
        results = service.run

        # Store results in cache (same as create action)
        run_record = {
          id: SecureRandom.hex(6),
          run_at: results[:run_at],
          hardware: results[:hardware],
          config: results[:config],
          strategies: results[:strategies],
          winner: results[:winner],
          received_at: Time.now.iso8601,
          source: "cloud_runner"
        }

        runs = cached_runs
        runs.unshift(run_record)
        runs = runs.first(MAX_RETAINED)
        Rails.cache.write(CACHE_KEY, runs, expires_in: 7.days)

        render json: { ok: true, id: run_record[:id], results: results }
      else
        # Queue async job for larger benchmarks
        BenchmarkRunJob.perform_later(options)
        render json: { ok: true, status: "queued", message: "Benchmark queued for async execution" }
      end
    rescue => e
      render json: { error: e.message, backtrace: e.backtrace.first(5) }, status: :internal_server_error
    end

    # POST /api/benchmarks
    # Accepts JSON body from ragents/bin/bench.
    # Requires an authenticated session: the records written here are served
    # verbatim to the authenticated dashboard, so anonymous ingest would let
    # any client inject trusted-looking benchmark content.
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

    # This is a JSON API, so answer an unauthenticated request with 401 rather
    # than the HTML sign-in redirect the Authentication concern defaults to.
    def request_authentication
      render json: { error: "Authentication required" }, status: :unauthorized
    end

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
