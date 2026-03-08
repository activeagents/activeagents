# frozen_string_literal: true

# =============================================================================
# Falcon Async Sandbox - Rack Configuration
# =============================================================================
#
# Run with:
#   bundle exec falcon serve --bind http://localhost:9292
#
# Test:
#   curl http://localhost:9292/health
#   curl -X POST http://localhost:9292/api/benchmark \
#     -H "Content-Type: application/json" \
#     -d '{"n": 10, "context_kb": 256}'
#
# =============================================================================

require "bundler/setup"
require "async"
require "async/barrier"
require "json"

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "ragents"

class AsyncAgentSandbox
  PROVIDER_CLASS = Ragents::Providers::AsyncSimulatedProvider
  PROVIDER_OPTS = { io_ms: 100, cpu_iterations: 50_000 }.freeze
  SYSTEM_PROMPT = "You are a helpful assistant."

  def call(env)
    path = env["PATH_INFO"]
    method = env["REQUEST_METHOD"]

    case [method, path]
    when ["GET", "/health"]
      json_response(200, { status: "ok", server: "falcon-async" })
    when ["POST", "/api/agent"]
      handle_agent(env)
    when ["POST", "/api/benchmark"]
      handle_benchmark(env)
    else
      json_response(404, { error: "Not found" })
    end
  rescue => e
    json_response(500, { error: e.message })
  end

  private

  def handle_agent(env)
    params = parse_body(env)
    input = params["input"] || "Hello"
    context_kb = params["context_kb"] || 0

    # Allocate context memory (simulates LLM context window)
    context = context_kb > 0 ? "x" * (context_kb * 1024) : nil

    provider = PROVIDER_CLASS.new(**PROVIDER_OPTS)
    messages = [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: input }
    ]

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    result = provider.chat(messages: messages)
    duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - start

    json_response(200, {
      content: result.content,
      duration_ms: duration_ms,
      input_tokens: result.input_tokens,
      output_tokens: result.output_tokens,
      context_bytes: context&.bytesize || 0
    })
  end

  def handle_benchmark(env)
    params = parse_body(env)
    n_requests = params["n"] || 10
    context_kb = params["context_kb"] || 0
    io_ms = params["io_ms"] || 100
    input = params["input"] || "Explain Ruby fibers"

    # Memory tracking
    GC.start
    mem_before = memory_mb
    gc_before = GC.count

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Run N concurrent fiber tasks using Async::Barrier
    # In Falcon, we're already inside an Async reactor, so use Barrier to wait
    barrier = Async::Barrier.new
    results = []

    Sync do |task|
      n_requests.times do |i|
        barrier.async do
          results << run_single_request(i, input, context_kb, io_ms)
        end
      end
      barrier.wait
    end

    wall_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)

    # Memory after
    gc_after = GC.count
    mem_after = memory_mb

    durations = results.map { |r| r[:duration_ms] }
    errors = results.count { |r| r[:error] }
    total_input = results.sum { |r| r[:input_tokens] || 0 }
    total_output = results.sum { |r| r[:output_tokens] || 0 }
    context_total = results.sum { |r| r[:context_bytes] || 0 }

    json_response(200, {
      name: "Falcon Async (N=#{n_requests})",
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
    })
  end

  def run_single_request(index, input, context_kb, io_ms)
    # Allocate context memory per request (simulates LLM context window)
    context = context_kb > 0 ? "x" * (context_kb * 1024) : nil

    req_start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

    # Simulate LLM I/O latency - Falcon's fiber scheduler intercepts Kernel.sleep
    # This yields to the fiber scheduler, allowing other fibers to run
    Kernel.sleep(io_ms / 1000.0)

    # Simulate CPU-bound response parsing (holds the GVL)
    _sum = 0
    50_000.times { |i| _sum += i * i }

    duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - req_start

    {
      content: "Async response for: #{input[0, 40]}",
      duration_ms: duration_ms,
      input_tokens: 80 + rand(40),
      output_tokens: 15 + rand(20),
      context_bytes: context&.bytesize || 0
    }
  rescue => e
    { error: e.message, duration_ms: 0, context_bytes: 0 }
  end

  def parse_body(env)
    body = env["rack.input"]&.read || "{}"
    JSON.parse(body)
  rescue
    {}
  end

  def memory_mb
    (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(1)
  rescue
    0.0
  end

  def percentile(arr, pct)
    return 0 if arr.empty?
    sorted = arr.sort
    idx = ((pct / 100.0) * (sorted.size - 1)).round
    sorted[idx] || 0
  end

  def json_response(status, body)
    [status, { "Content-Type" => "application/json" }, [JSON.generate(body)]]
  end
end

run AsyncAgentSandbox.new
