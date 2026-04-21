# frozen_string_literal: true

# BenchmarkRunJob
#
# Runs ragents concurrency benchmarks asynchronously and stores results.
# Triggered by POST /api/benchmarks/run with larger request counts.
#
class BenchmarkRunJob < ApplicationJob
  queue_as :default

  def perform(options = {})
    service = BenchmarkRunnerService.new(**options.symbolize_keys)
    results = service.run

    # Store results in cache
    run_record = {
      id: SecureRandom.hex(6),
      run_at: results[:run_at],
      hardware: results[:hardware],
      config: results[:config],
      strategies: results[:strategies],
      winner: results[:winner],
      received_at: Time.now.iso8601,
      source: "cloud_runner_async"
    }

    cache_key = Api::BenchmarksController::CACHE_KEY
    max_retained = Api::BenchmarksController::MAX_RETAINED

    runs = Rails.cache.read(cache_key) || []
    runs.unshift(run_record)
    runs = runs.first(max_retained)
    Rails.cache.write(cache_key, runs, expires_in: 7.days)

    Rails.logger.info "[BenchmarkRunJob] Completed benchmark run: #{run_record[:id]}"
  rescue => e
    Rails.logger.error "[BenchmarkRunJob] Failed: #{e.message}"
    raise
  end
end
