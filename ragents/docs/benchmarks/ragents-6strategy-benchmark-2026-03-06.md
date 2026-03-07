# RAGents Concurrency Benchmark Report

**Date**: 2026-03-06
**Ruby Version**: 4.0.1
**Platform**: arm64-darwin25 (Apple Silicon)
**CPU Cores**: 10

## Overview

This benchmark compares 6 concurrency strategies for LLM workloads in Ruby 4.0:

1. **Sequential** - Baseline, one request at a time
2. **Threads (unbounded)** - One thread per request, N threads for N requests
3. **Thread Pool (bounded)** - Worker pool limited to CPU cores
4. **Ractors (unbounded)** - One Ractor per request, true parallelism
5. **Ractor Pool (bounded)** - Worker pool limited to CPU cores
6. **Async Fibers** - Cooperative scheduling with fiber scheduler

## Test Configuration

| Parameter | Value |
|-----------|-------|
| Requests (N) | 20 |
| Simulated I/O Latency | 100ms |
| CPU Iterations | 50,000 |
| Pool Size | 10 (CPU cores) |
| Provider | SimulatedProvider (mock) |

## Results

| Strategy | Wall Time | Throughput | Speedup vs Sequential |
|----------|-----------|------------|----------------------|
| Sequential | 2115.6ms | 9.45 req/s | 1.0x |
| **Threads (N=20)** | **112.4ms** | **177.94 req/s** | **18.82x** |
| Thread Pool (size=10) | 213.0ms | 93.9 req/s | 9.93x |
| Ractors (N=20) | 114.4ms | 174.83 req/s | 18.49x |
| Ractor Pool (size=10) | 213.6ms | 93.63 req/s | 9.9x |
| Async Fibers (N=20) | 154.8ms | 129.2 req/s | 13.67x |

**Winner**: Threads (N=20) with 177.94 req/s

## Analysis

### Unbounded Strategies (Threads & Ractors)
- Both achieve ~175-178 req/s with ~18-19x speedup
- Ractors provide true parallelism (bypass GVL for CPU-bound work)
- Threads release GVL during I/O but share GVL for CPU
- For I/O-heavy LLM workloads, both perform nearly identically

### Bounded Pools (Thread Pool & Ractor Pool)
- Both achieve ~94 req/s with ~10x speedup
- Expected: 20 requests / 10 workers = 2 batches of ~100ms each = ~200ms total
- Better resource utilization than unbounded strategies
- Recommended for production with rate limiting

### Async Fibers
- Achieves 129.2 req/s with 13.67x speedup
- Lower than Threads/Ractors due to CPU-bound work blocking fiber scheduler
- Fibers only yield during I/O operations (sleep)
- Would perform better with true async I/O (HTTP client with fiber scheduler)

## Ruby 4.0 Changes

Several Ruby 4.0 Ractor API changes were addressed:

1. **`Ractor.take` removed** - Use `Ractor.receive` for the supervisor to receive from its inbox
2. **`Ractor.yield` removed** - Use `supervisor << msg` for worker to send to supervisor
3. **`Data.define` constructor** - Override `initialize` instead of `self.new`
4. **Shareable constraints** - Dynamic Procs can't cross Ractor boundaries; use proper classes

## Recommendations

| Use Case | Recommended Strategy |
|----------|---------------------|
| Development/Testing | Sequential |
| Production (unbounded load) | Threads or Ractors |
| Production (rate-limited) | Thread Pool or Ractor Pool |
| Async I/O workloads | Async Fibers + Falcon |
| CPU-bound + I/O mixed | Ractors (bypass GVL) |

## Running the Benchmark

```bash
# Basic benchmark (5 strategies)
bin/bench --requests 20 --io-ms 100

# With Async Fibers (all 6 strategies)
bin/bench --async --requests 20 --io-ms 100

# Post results to dashboard
bin/bench --async --requests 20 --post http://localhost:3000

# With realistic LLM latency (1-30s variable)
bin/bench --provider realistic --requests 10

# With real providers
OPENAI_API_KEY=sk-... bin/bench --provider openai --requests 5
```

## Files Modified

- `lib/ragents/ractor/agent_ractor.rb` - Ruby 4.0 Ractor API fixes
- `lib/ragents/message.rb` - Data.define constructor fixes
- `lib/ragents/providers/simulated_provider.rb` - Ractor-safe mock provider
- `lib/ragents/providers/async_simulated_provider.rb` - Async-aware mock provider
- `bin/bench` - Added Thread Pool and Async Fibers strategies
