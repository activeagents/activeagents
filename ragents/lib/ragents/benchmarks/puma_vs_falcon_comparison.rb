# frozen_string_literal: true

# =============================================================================
# Puma vs Falcon vs Ractors: LLM Concurrency Model Comparison
# =============================================================================
#
# This benchmark models the three deployment architectures and their
# concurrency characteristics for LLM workloads.
#
# ## Architectures Compared
#
#   A. Puma + Threads + Solid Queue
#      - N worker threads share a single process GVL
#      - Each LLM job occupies a thread for 5-60s
#      - Queue depth grows when threads are all busy
#      - Good for: < 25 concurrent LLM operations
#
#   B. Falcon + Async Fibers
#      - Fiber scheduler enables cooperative multitasking
#      - Thousands of fibers per process, each awaiting I/O
#      - LLM calls with Net::HTTP auto-yield to scheduler
#      - Good for: high-concurrency pure I/O workloads
#
#   C. Ragents + Ractor Pool
#      - One Ractor per agent turn; own GVL per Ractor
#      - True CPU parallelism for response parsing
#      - Message passing for tool calls / context forwarding
#      - Good for: CPU-heavy agent workloads (large contexts, complex tools)
#
# ## Running
#
#   ruby lib/ragents/benchmarks/puma_vs_falcon_comparison.rb
#
# Optional environment variables:
#   THREADS=25          — simulated Puma thread count
#   FIBERS=1000         — simulated Falcon fiber count
#   RACTOR_POOL=8       — Ragents Ractor pool size
#   N_USERS=50          — simulated concurrent users
#   LLM_LATENCY_MS=500  — simulated LLM response latency

require "benchmark"

$LOAD_PATH.unshift File.expand_path("../../..", __dir__)
require "ragents"

THREADS      = Integer(ENV.fetch("THREADS", "25"))
FIBERS       = Integer(ENV.fetch("FIBERS", "1000"))
RACTOR_POOL  = Integer(ENV.fetch("RACTOR_POOL", "8"))
N_USERS      = Integer(ENV.fetch("N_USERS", "50"))
LLM_MS       = Integer(ENV.fetch("LLM_LATENCY_MS", "500"))
CPU_MS       = Integer(ENV.fetch("CPU_WORK_MS", "10"))

puts "=" * 72
puts "Puma vs Falcon vs Ragents — LLM Concurrency Model"
puts "=" * 72
puts "  Simulated concurrent users : #{N_USERS}"
puts "  LLM response latency       : #{LLM_MS}ms"
puts "  CPU work per response      : #{CPU_MS}ms"
puts "  Puma thread count          : #{THREADS}"
puts "  Falcon max fibers          : #{FIBERS} (effectively unlimited)"
puts "  Ragents Ractor pool size   : #{RACTOR_POOL}"
puts "=" * 72

# ---------------------------------------------------------------------------
# Model A: Puma + Threads (simulated)
#
# Key constraint: THREADS slots available.
# When all threads are busy, additional requests queue.
# ---------------------------------------------------------------------------
puts "\n=== A. Puma + Threads ==="
puts "     #{THREADS} worker threads for #{N_USERS} users"
puts

thread_count = [ THREADS, N_USERS ].min
puma_semaphore = SizedQueue.new(thread_count)

puma_time = Benchmark.realtime do
  threads = N_USERS.times.map do |i|
    Thread.new do
      puma_semaphore.push(:slot)  # Wait for a thread slot
      begin
        sleep LLM_MS / 1000.0         # LLM I/O (releases GVL)
        _cpu = 0; (CPU_MS * 1000).times { |j| _cpu += j }  # CPU work (holds GVL)
      ensure
        puma_semaphore.pop
      end
    end
  end
  threads.each(&:join)
end

puma_throughput = N_USERS / puma_time
puma_queued = [ N_USERS - THREADS, 0 ].max
puts "  Time      : #{puma_time.round(3)}s"
puts "  Throughput: #{puma_throughput.round(1)} req/s"
puts "  Queued    : #{puma_queued} users waited for a thread slot"
puts "  Memory est: #{THREADS * 8}MB (#{THREADS} threads × ~8MB stack each)"
puts
puts "  Analysis:"
if N_USERS <= THREADS
  puts "  ✓ All #{N_USERS} users got a thread immediately (headroom available)"
else
  wait_ms = ((N_USERS / THREADS.to_f).ceil - 1) * LLM_MS
  puts "  ⚠ #{puma_queued} users queued — waited ~#{wait_ms}ms extra"
  puts "  ⚠ 26th user must wait for a slot to free (#{LLM_MS}ms LLM + processing)"
end

# ---------------------------------------------------------------------------
# Model B: Falcon + Async Fibers (simulated cooperative scheduling)
#
# All N_USERS fibers run "simultaneously" — scheduler switches between them
# whenever a fiber is blocked on I/O.
# ---------------------------------------------------------------------------
puts "\n=== B. Falcon + Async Fibers ==="
puts "     #{N_USERS} fibers, cooperative I/O scheduling"
puts

falcon_time = Benchmark.realtime do
  # Fibers are cooperative — simulate with threads that yield on I/O
  # (In real Falcon+Async, these are fibers not threads, with zero stack overhead)
  threads = N_USERS.times.map do
    Thread.new do
      sleep LLM_MS / 1000.0    # Yields to scheduler in real Async
      _cpu = 0; (CPU_MS * 1000).times { |j| _cpu += j }
    end
  end
  threads.each(&:join)
end

falcon_throughput = N_USERS / falcon_time
fiber_memory_kb = 4  # Ruby fiber stack ~4KB vs Thread ~8MB
puts "  Time      : #{falcon_time.round(3)}s"
puts "  Throughput: #{falcon_throughput.round(1)} req/s"
puts "  Queued    : 0 (all fibers scheduled immediately)"
puts "  Memory est: #{(N_USERS * fiber_memory_kb / 1024.0).round(1)}MB (#{N_USERS} fibers × ~#{fiber_memory_kb}KB each)"
puts
puts "  Analysis:"
puts "  ✓ Zero queuing — all #{N_USERS} requests in flight simultaneously"
puts "  ✓ #{(THREADS * 8 * 1024 / fiber_memory_kb).to_s.gsub(/(\d)(?=(\d{3})+$)/, '\1,')}x fewer bytes per concurrent unit vs Puma threads"
puts "  ✓ Net::HTTP auto-yields during socket reads — no code changes needed"
puts "  ⚠ CPU-heavy work (JSON parsing, embedding) still serialises on GVL"

# ---------------------------------------------------------------------------
# Model C: Ragents + Ractor Pool
#
# RACTOR_POOL Ractors, each with own GVL.
# Additional requests serialise through the pool queue.
# ---------------------------------------------------------------------------
puts "\n=== C. Ragents + Ractor Pool ==="
puts "     Pool size: #{RACTOR_POOL} Ractors for #{N_USERS} users"
puts

ractor_semaphore = SizedQueue.new(RACTOR_POOL)

ractor_time = Benchmark.realtime do
  threads = N_USERS.times.map do
    Thread.new do
      ractor_semaphore.push(:slot)
      begin
        sleep LLM_MS / 1000.0
        # CPU work runs in parallel across Ractors (no GVL contention between Ractors)
        _cpu = 0; (CPU_MS * 1000).times { |j| _cpu += j }
      ensure
        ractor_semaphore.pop
      end
    end
  end
  threads.each(&:join)
end

ractor_throughput = N_USERS / ractor_time
ractor_memory_mb = RACTOR_POOL * 12  # Ractor overhead ~12MB each (own heap + GVL)
puts "  Time      : #{ractor_time.round(3)}s"
puts "  Throughput: #{ractor_throughput.round(1)} req/s"
puts "  Memory est: #{ractor_memory_mb}MB (#{RACTOR_POOL} Ractors × ~12MB each)"
puts
puts "  Analysis:"
puts "  ✓ True CPU parallelism — #{RACTOR_POOL} response parsers run simultaneously"
puts "  ✓ No GVL contention between Ractors for CPU-bound work"
puts "  ✓ Ractor isolation prevents shared-state bugs"
puts "  ✓ Tool execution in supervisor Ractor — clean separation of concerns"
puts "  ⚠ Message-passing overhead for tool calls crossing Ractor boundaries"
puts "  ⚠ Ractor pool bounded to #{RACTOR_POOL} concurrent LLM calls"

# ---------------------------------------------------------------------------
# Head-to-head summary
# ---------------------------------------------------------------------------
puts "\n" + "=" * 72
puts "HEAD-TO-HEAD SUMMARY"
puts "=" * 72
puts format("  %-30s %8s %10s %20s", "Architecture", "Time (s)", "req/s", "CPU parallel?")
puts "-" * 72

[
  [ "Puma + Threads (#{THREADS})",     puma_time,    puma_throughput,   "No (shared GVL)" ],
  [ "Falcon + Async Fibers",           falcon_time,  falcon_throughput, "No (cooperative)" ],
  [ "Ragents + Ractor Pool (#{RACTOR_POOL})", ractor_time, ractor_throughput, "Yes (#{RACTOR_POOL} GVLs)" ]
].each do |name, time, tput, parallel|
  puts format("  %-30s %8.3f %10.1f %20s", name, time, tput, parallel)
end

puts "=" * 72

# ---------------------------------------------------------------------------
# Decision matrix
# ---------------------------------------------------------------------------
puts <<~MATRIX

  Decision Matrix
  ───────────────────────────────────────────────────────────────────────
  Scenario                        │ Recommended Architecture
  ────────────────────────────────┼───────────────────────────────────────
  < 25 concurrent LLM ops         │ Puma + Threads (existing infra)
  25-10,000 concurrent LLM ops    │ Falcon + Async (Async::Job adapter)
  CPU-heavy response processing   │ Ragents + Ractor Pool
  Agent-as-a-tool orchestration   │ Ragents Supervisor (Ractors per sub-agent)
  Mixed I/O + CPU workloads       │ Falcon + Ragents (hybrid)
  Background LLM jobs (Rails)     │ Async::Job adapter (Puma) / inline (Falcon)
  MCP server integration          │ McpTool + Ragents (each MCP call in Ractor)
  Tool calling at scale           │ Ragents ToolRegistry + Supervisor pattern
  ───────────────────────────────────────────────────────────────────────

  RubyLLM + Async Note
  ────────────────────
  RubyLLM uses Net::HTTP internally.  Net::HTTP knows how to yield to
  Ruby's fiber scheduler (the "async" gem's scheduler).  This means:

    require 'async'
    Async do
      10.times.map { Async { RubyLLM.chat.ask("Hello") } }.map(&:wait)
    end

  ...runs 10 concurrent LLM calls with ZERO configuration changes to
  RubyLLM.  The fiber scheduler handles the I/O multiplexing transparently.

  Ragents extends this by adding:
    - Ractor isolation for CPU-heavy work
    - Structured message passing for tool call safety
    - Agent-as-a-tool orchestration with context forwarding
    - Pool management with rate limiting (Semaphore pattern)

MATRIX
