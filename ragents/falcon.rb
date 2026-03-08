# frozen_string_literal: true

# =============================================================================
# Falcon Configuration for Ragents Async Sandbox
# =============================================================================
#
# Falcon is an async Ruby web server that uses fibers for cooperative
# multitasking. Combined with the async gem, it can handle thousands of
# concurrent LLM requests without threading overhead.
#
# Start with:
#   bundle exec falcon serve --bind http://localhost:9292
#
# Or for development with auto-reload:
#   bundle exec falcon serve --bind http://localhost:9292 --count 1
#
# Key advantages over Puma for LLM workloads:
#   - Fibers are ~4KB vs threads ~8MB stack
#   - No GVL contention during I/O waits
#   - Net::HTTP auto-yields to fiber scheduler
#   - Thousands of concurrent requests per process
#
# =============================================================================

require "async"
require "async/http/server"
require "async/http/endpoint"
require "protocol/http/response"
require "json"

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "ragents"

# Simple async agent endpoint for benchmarking
class AsyncAgentApp
  def initialize
    @provider_class = Ragents::Providers::SimulatedProvider
    @provider_opts = { io_ms: 100, cpu_iterations: 50_000 }
    @system_prompt = "You are a helpful assistant."
  end

  def call(request)
    path = request.path

    case path
    when "/health"
      health_response
    when "/api/agent"
      handle_agent_request(request)
    when "/api/benchmark"
      handle_benchmark_request(request)
    else
      not_found_response
    end
  end

  private

  def health_response
    Protocol::HTTP::Response[200, { "content-type" => "application/json" }, [JSON.generate({ status: "ok", server: "falcon" })]]
  end

  def handle_agent_request(request)
    body = request.body&.read || "{}"
    params = JSON.parse(body)
    input = params["input"] || "Hello"
    context_kb = params["context_kb"] || 0

    # Allocate context memory (simulates LLM context window)
    context = context_kb > 0 ? "x" * (context_kb * 1024) : nil

    # Create provider and run (async-safe, yields during I/O)
    provider = @provider_class.new(**@provider_opts)
    messages = [
      { role: "system", content: @system_prompt },
      { role: "user", content: input }
    ]

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    result = provider.chat(messages: messages)
    duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - start

    response = {
      content: result.content,
      duration_ms: duration_ms,
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      context_bytes: context&.bytesize || 0
    }

    Protocol::HTTP::Response[200, { "content-type" => "application/json" }, [JSON.generate(response)]]
  rescue => e
    Protocol::HTTP::Response[500, { "content-type" => "application/json" }, [JSON.generate({ error: e.message })]]
  end

  def handle_benchmark_request(request)
    body = request.body&.read || "{}"
    params = JSON.parse(body)
    n_requests = params["n"] || 10
    context_kb = params["context_kb"] || 0
    input = params["input"] || "Explain Ruby fibers"

    mem_before = (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(1) rescue 0
    gc_before = GC.count

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Run N concurrent fiber tasks (async cooperative scheduling)
    results = Async do |task|
      n_requests.times.map do |i|
        task.async do
          # Allocate context memory per request
          context = context_kb > 0 ? "x" * (context_kb * 1024) : nil

          provider = @provider_class.new(**@provider_opts)
          messages = [
            { role: "system", content: @system_prompt },
            { role: "user", content: "#{input} (request #{i + 1})" }
          ]

          req_start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          result = provider.chat(messages: messages)
          duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - req_start

          {
            content: result.content,
            duration_ms: duration_ms,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            context_bytes: context&.bytesize || 0
          }
        end
      end.map(&:wait)
    end

    wall_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
    mem_after = (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(1) rescue 0
    gc_after = GC.count

    durations = results.map { |r| r[:duration_ms] }
    errors = results.count { |r| r[:error] }
    total_input = results.sum { |r| r[:input_tokens] || 0 }
    total_output = results.sum { |r| r[:output_tokens] || 0 }
    context_total = results.sum { |r| r[:context_bytes] || 0 }

    response = {
      name: "Falcon Async Fibers (N=#{n_requests})",
      n_requests: n_requests,
      wall_time_ms: wall_ms,
      throughput: (n_requests / (wall_ms / 1000.0)).round(2),
      avg_latency_ms: durations.any? ? (durations.sum.to_f / durations.size).round(1) : 0,
      min_latency_ms: durations.min || 0,
      max_latency_ms: durations.max || 0,
      p50_latency_ms: percentile(durations, 50),
      p95_latency_ms: percentile(durations, 95),
      errors: errors,
      total_input_tokens: total_input,
      total_output_tokens: total_output,
      memory_mb_before: mem_before,
      memory_mb_after: mem_after,
      memory_delta_mb: (mem_after - mem_before).round(1),
      gc_runs: gc_after - gc_before,
      context_allocated_mb: (context_total / 1024.0 / 1024.0).round(2),
      server: "falcon",
      concurrency_model: "async_fibers"
    }

    Protocol::HTTP::Response[200, { "content-type" => "application/json" }, [JSON.generate(response)]]
  rescue => e
    Protocol::HTTP::Response[500, { "content-type" => "application/json" }, [JSON.generate({ error: e.message, backtrace: e.backtrace.first(5) })]]
  end

  def percentile(arr, pct)
    return 0 if arr.empty?
    sorted = arr.sort
    idx = ((pct / 100.0) * (sorted.size - 1)).round
    sorted[idx] || 0
  end

  def not_found_response
    Protocol::HTTP::Response[404, { "content-type" => "application/json" }, [JSON.generate({ error: "Not found" })]]
  end
end

# Middleware wrapper for Falcon
app = AsyncAgentApp.new

# Export for Falcon's rackup compatibility
run ->(env) {
  # Convert Rack env to our request format
  request = OpenStruct.new(
    path: env["PATH_INFO"],
    body: env["rack.input"]
  )
  response = app.call(request)
  [response.status, response.headers.to_h, response.body]
}
