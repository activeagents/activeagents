# frozen_string_literal: true

# =============================================================================
# Ragents Benchmark Suite — Concurrent LLM Call Strategies
# =============================================================================
#
# Compares four concurrency strategies for I/O-bound LLM workloads:
#
#   1. Sequential        — baseline: one request at a time
#   2. Threads           — Thread.new per request (shares GVL for Ruby code)
#   3. Ractors           — Ractor per request (own GVL, true parallelism)
#   4. Async (Fibers)    — cooperative multitasking via fiber scheduler
#
# Based on the analysis from:
#   https://paolino.me/async-ruby-is-the-future/
#
# ## Key Insight
#
# LLM operations spend ~99% of their time waiting for network I/O.
# The GVL is released during blocking I/O, so Threads and Ractors perform
# similarly for pure I/O workloads.  The Ractor advantage emerges when
# response *processing* (JSON parsing, context building, token counting)
# is CPU-intensive enough to compete for the GVL.
#
# ## Running
#
#   ruby lib/ragents/benchmarks/concurrent_llm_benchmark.rb
#
# Configure N_REQUESTS and SIMULATED_IO_SECONDS at the top of the file.
# Set USE_REAL_API=true and OPENAI_API_KEY to benchmark against a real LLM.

require "benchmark"
require "benchmark/ips"

$LOAD_PATH.unshift File.expand_path("../../..", __dir__)
require "ragents"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
N_REQUESTS          = Integer(ENV.fetch("N_REQUESTS", "10"))
SIMULATED_IO_MS     = Integer(ENV.fetch("SIMULATED_IO_MS", "100"))   # ms per fake LLM call
CPU_WORK_ITERATIONS = Integer(ENV.fetch("CPU_WORK_ITERATIONS", "50_000"))
USE_REAL_API        = ENV["USE_REAL_API"] == "true"
USE_ASYNC           = begin; require "async"; true; rescue LoadError; false; end

puts "=" * 72
puts "Ragents Benchmark — Concurrent LLM Strategies"
puts "=" * 72
puts "  Requests            : #{N_REQUESTS}"
puts "  Simulated I/O delay : #{SIMULATED_IO_MS}ms per request"
puts "  CPU work iterations : #{CPU_WORK_ITERATIONS.to_s.gsub(/(\d)(?=(\d{3})+$)/, '\1,')}"
puts "  Real API            : #{USE_REAL_API}"
puts "  Async available     : #{USE_ASYNC}"
puts "=" * 72
puts

# ---------------------------------------------------------------------------
# Simulated provider that mimics LLM I/O latency + CPU parsing work
# ---------------------------------------------------------------------------
class SimulatedProvider < Ragents::Providers::BaseProvider
  def initialize(io_ms: SIMULATED_IO_MS, cpu_iters: CPU_WORK_ITERATIONS)
    @io_seconds = io_ms / 1000.0
    @cpu_iters  = cpu_iters
    freeze
  end

  def chat(messages:, tools: [], model: nil, **_opts)
    # Simulate network I/O (releases GVL in both Threads and Ractors)
    sleep @io_seconds

    # Simulate CPU-bound response parsing (competes for GVL in Threads,
    # runs in parallel in Ractors)
    _sum = 0
    @cpu_iters.times { |i| _sum += i * i }

    content = "Simulated response for: #{(messages.last[:content] || "")[0, 50]}"

    Ragents::Providers::GenerationResult.new(
      content: content,
      tool_calls: [],
      input_tokens: 100,
      output_tokens: 20,
      model: "simulated-model",
      stop_reason: "end_turn"
    )
  end
end

# ---------------------------------------------------------------------------
# Real provider (only used when USE_REAL_API=true)
# ---------------------------------------------------------------------------
if USE_REAL_API
  REAL_PROVIDER_CLASS = Ragents::Providers::OpenAIProvider
  REAL_PROVIDER_OPTS  = { api_key: ENV.fetch("OPENAI_API_KEY") }.freeze
else
  REAL_PROVIDER_CLASS = SimulatedProvider
  REAL_PROVIDER_OPTS  = { io_ms: SIMULATED_IO_MS, cpu_iters: CPU_WORK_ITERATIONS }.freeze
end

INPUTS = N_REQUESTS.times.map { |i| "Request #{i + 1}: Explain quantum entanglement briefly." }.freeze
SYSTEM = "You are a concise science communicator."

# ---------------------------------------------------------------------------
# Helper: run agent for a single input
# ---------------------------------------------------------------------------
def run_agent(input)
  agent = Ragents::Ractor::AgentRactor.new(
    provider_class: REAL_PROVIDER_CLASS,
    provider_opts: REAL_PROVIDER_OPTS,
    system_prompt: SYSTEM
  )
  agent.run(input)
end

# ---------------------------------------------------------------------------
# Strategy 1: Sequential
# ---------------------------------------------------------------------------
puts "\n--- 1. Sequential ---"
sequential_time = Benchmark.realtime do
  INPUTS.each { |input| run_agent(input) }
end
puts "  Total time: #{sequential_time.round(3)}s"
puts "  Throughput: #{(N_REQUESTS / sequential_time).round(1)} req/s"
puts "  Per request: #{(sequential_time / N_REQUESTS * 1000).round(1)}ms"

# ---------------------------------------------------------------------------
# Strategy 2: Threads (one Thread per request)
# ---------------------------------------------------------------------------
puts "\n--- 2. Threads (#{N_REQUESTS} threads) ---"
threads_time = Benchmark.realtime do
  threads = INPUTS.map { |input| Thread.new { run_agent(input) } }
  threads.each(&:join)
end
puts "  Total time: #{threads_time.round(3)}s"
puts "  Throughput: #{(N_REQUESTS / threads_time).round(1)} req/s"
puts "  Speedup vs sequential: #{(sequential_time / threads_time).round(2)}x"

# ---------------------------------------------------------------------------
# Strategy 3: Ractors (one Ractor per request via AgentPool)
# ---------------------------------------------------------------------------
puts "\n--- 3. Ractors (pool size = #{N_REQUESTS}) ---"
ractors_time = Benchmark.realtime do
  pool = Ragents::Ractor::AgentPool.new(
    size: N_REQUESTS,
    provider_class: REAL_PROVIDER_CLASS,
    provider_opts: REAL_PROVIDER_OPTS,
    system_prompt: SYSTEM
  )
  pool.process(INPUTS)
end
puts "  Total time: #{ractors_time.round(3)}s"
puts "  Throughput: #{(N_REQUESTS / ractors_time).round(1)} req/s"
puts "  Speedup vs sequential: #{(sequential_time / ractors_time).round(2)}x"
puts "  Speedup vs threads:    #{(threads_time / ractors_time).round(2)}x"

# ---------------------------------------------------------------------------
# Strategy 4: Async (Fiber-based cooperative scheduling)
# ---------------------------------------------------------------------------
if USE_ASYNC
  require "async"
  puts "\n--- 4. Async / Fibers ---"
  async_time = Benchmark.realtime do
    Async do
      tasks = INPUTS.map do |input|
        Async { run_agent(input) }
      end
      tasks.map(&:wait)
    end
  end
  puts "  Total time: #{async_time.round(3)}s"
  puts "  Throughput: #{(N_REQUESTS / async_time).round(1)} req/s"
  puts "  Speedup vs sequential: #{(sequential_time / async_time).round(2)}x"
  puts "  Note: Async uses cooperative fibers — perfect for pure I/O workloads."
  puts "        For CPU-bound parsing, Ractors may outperform Async."
else
  puts "\n--- 4. Async / Fibers --- SKIPPED (gem 'async' not available)"
  puts "  Add 'gem async' to your Gemfile and re-run to include Async results."
end

# ---------------------------------------------------------------------------
# Strategy 5: Ractor Pool with rate-limiting semaphore
# ---------------------------------------------------------------------------
POOL_SIZE = [ N_REQUESTS, 4 ].min
puts "\n--- 5. Ractor Pool (size=#{POOL_SIZE}, rate-limited) ---"
semaphore_time = Benchmark.realtime do
  pool = Ragents::Ractor::AgentPool.new(
    size: POOL_SIZE,
    provider_class: REAL_PROVIDER_CLASS,
    provider_opts: REAL_PROVIDER_OPTS,
    system_prompt: SYSTEM
  )
  pool.process(INPUTS)
end
puts "  Total time: #{semaphore_time.round(3)}s"
puts "  Throughput: #{(N_REQUESTS / semaphore_time).round(1)} req/s"
puts "  Speedup vs sequential: #{(sequential_time / semaphore_time).round(2)}x"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "\n" + "=" * 72
puts "SUMMARY (N=#{N_REQUESTS}, io=#{SIMULATED_IO_MS}ms/req, cpu=#{CPU_WORK_ITERATIONS} iters)"
puts "=" * 72
puts format("  %-35s %8s %12s %12s", "Strategy", "Time (s)", "req/s", "Speedup")
puts "-" * 72

rows = [
  [ "Sequential",                         sequential_time,  1.0 ],
  [ "Threads (N=#{N_REQUESTS})",           threads_time,    sequential_time / threads_time ],
  [ "Ractors (N=#{N_REQUESTS})",           ractors_time,    sequential_time / ractors_time ],
  [ "Ractor Pool (N=#{POOL_SIZE})",        semaphore_time,  sequential_time / semaphore_time ]
]

rows.each do |name, time, speedup|
  puts format("  %-35s %8.3f %12.1f %12.2fx",
              name, time, N_REQUESTS / time, speedup)
end

puts "=" * 72

# ---------------------------------------------------------------------------
# Architecture analysis
# ---------------------------------------------------------------------------
puts <<~ANALYSIS

  Architecture Analysis
  ─────────────────────
  Sequential: Processes one LLM call at a time. Throughput is bounded by
  individual request latency. Fine for single-user, low-volume scenarios.

  Threads: Release the GVL during I/O (sleep/Net::HTTP), so multiple
  threads can wait for LLM responses concurrently. Ruby code between I/O
  calls (JSON parsing, object creation) still serialises on the GVL.
  Practical limit: ~100-200 threads before context switching overhead hurts.

  Ractors: Each Ractor has its own GVL. CPU-bound response parsing runs
  truly in parallel. Ideal when processing work per response is significant
  (large contexts, complex tool dispatching, embedding computation).
  Communication overhead: message passing for tool calls crosses Ractor
  boundaries — design for coarse-grained, not fine-grained, parallelism.

  Async (Fibers): Cooperative scheduling — zero per-fiber memory overhead,
  millions of concurrent fibers possible. Net::HTTP yields to the scheduler
  during I/O automatically. No CPU parallelism for Ruby code, but perfect
  for pure I/O workloads where threads are too heavy and Ractors introduce
  unnecessary complexity.

  Ractor Pool: Bounded parallelism via SizedQueue semaphore. Prevents
  resource exhaustion when N >> CPU cores. Good default for production.

  ─────────────────────
  Recommendation for LLM workloads (RubyLLM / Ragents):

    • Low concurrency (< 20 parallel): Threads or Async — simpler, lower overhead
    • High concurrency (20+): Async fibers — minimal memory, auto-scheduling
    • CPU-heavy post-processing: Ractors — true parallel Ruby execution
    • Mixed workloads: Ractor pool with rate limiting (Strategy 5)

  For the Puma vs Falcon comparison:
    • Puma (threaded): Good for moderate concurrency; use Async::Job for LLM queues
    • Falcon (fiber-based): Naturally async; LLM calls auto-yield; no job queue needed
    • Ragents + Falcon: Optimal — each request runs in an Async fiber that
      yields during LLM I/O, and Ractors handle CPU-bound tool execution.

ANALYSIS
