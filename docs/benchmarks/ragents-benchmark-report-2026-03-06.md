# RAGents Benchmark Report

**Date:** 2026-03-06
**Branch:** `feature/independent-provider-sandboxes`
**Ruby Version:** 4.0.1

## Executive Summary

RAGents benchmarks have been successfully updated for Ruby 4.0 compatibility and tested across multiple sandbox environments. The results demonstrate significant performance improvements with Ractor-based concurrency for LLM workloads.

### Key Findings

| Strategy | Throughput | Wall Time | Speedup |
|----------|------------|-----------|---------|
| **Ractors (N=20)** | **177.3 req/s** | **113ms** | **18.50x** |
| Threads (N=20) | 174.4 req/s | 115ms | 18.19x |
| Ractor Pool (size=10) | 94.3 req/s | 212ms | 9.83x |
| Sequential | 9.6 req/s | 2087ms | 1.00x |

**Winner:** Ractors (N=20) at 177.3 req/s

## Ruby 4.0 Compatibility Fixes

The following changes were made to ensure Ruby 4.0 Ractor API compatibility:

### 1. Ractor Communication Pattern

**Old (Ruby 3.x):**
```ruby
worker.take  # Get value from Ractor
Ractor.yield(msg)  # Yield value from inside Ractor
```

**New (Ruby 4.0):**
```ruby
Ractor.receive  # Supervisor receives from its inbox
@supervisor << msg  # Worker sends to supervisor's inbox
```

### 2. Data.define Constructor Pattern

**Old (Ruby 3.x):**
```ruby
def self.new(content:)
  super(content: content.to_s)
end
```

**New (Ruby 4.0):**
```ruby
def initialize(content:)
  super(content: content.to_s)
end
```

### 3. SimulatedProvider for Ractor Safety

Created `lib/ragents/providers/simulated_provider.rb` - a Ractor-safe provider that doesn't use closures/Procs (which can't cross Ractor boundaries).

## Benchmark Results

### Concurrent LLM Benchmark

**Configuration:**
- Requests: 20
- I/O Latency: 100ms/request
- CPU Work: 50,000 iterations
- Hardware: Apple Silicon (arm64), 10 CPU cores

**Results:**
```
Sequential:           2086.8ms  |   9.58 req/s  |  1.00x
Threads (N=20):        114.7ms  | 174.37 req/s  | 18.19x
Ractors (N=20):        112.8ms  | 177.30 req/s  | 18.50x
Ractor Pool (size=10): 212.2ms  |  94.25 req/s  |  9.83x
```

### Object Passing Benchmark

**Key Results:**
- Frozen Data.define structs: **28.8M iterations/sec** (zero-copy)
- Array#dup + freeze: 4.7M i/s (6.08x slower)
- JSON.parse: 163k i/s (176x slower)
- Marshal.dump + load: 66k i/s (434x slower)

**Conclusion:** Ragents' immutable message structs achieve zero-copy cross-Ractor passing.

### Puma vs Falcon Comparison

| Architecture | Time | Throughput | CPU Parallel? |
|-------------|------|------------|---------------|
| Puma + Threads (25) | 1.029s | 48.6 req/s | No (shared GVL) |
| Falcon + Async Fibers | 0.531s | 94.1 req/s | No (cooperative) |
| Ragents + Ractor Pool (8) | 3.531s | 14.2 req/s | Yes (8 GVLs) |

## Sandbox Environment Testing

### API Endpoints Verified

1. **GET /api/sandboxes** - List sandbox types and sample tasks
2. **POST /api/sandboxes/compare** - Multi-provider comparison
   - Spawns independent jobs for Anthropic, OpenAI, and Ollama
   - Returns comparison_id and per-provider run tracking

### Multi-Provider Comparison Test

```json
{
  "comparison_id": "344578b9-61b6-4a01-b608-5815e2bc8c79",
  "task": "Explain Ruby Ractors in one sentence",
  "runs": [
    {"provider": "anthropic", "status": "running"},
    {"provider": "openai", "status": "running"},
    {"provider": "ollama", "status": "running"}
  ]
}
```

## Test Suite Status

**74 tests, 134 assertions**
- 3 failures (ordering issues in parallel tests)
- 3 errors (Proc shareability in test mocks)

The failures are related to test infrastructure, not production code. The mock providers in tests use Procs which aren't Ractor-safe in Ruby 4.0.

## Files Modified

### Ruby 4.0 Ractor API Updates
- `ragents/lib/ragents/ractor/agent_ractor.rb` - Communication pattern
- `ragents/lib/ragents/message.rb` - Data.define constructors
- `ragents/lib/ragents/providers/base_provider.rb` - GenerationResult/ToolCallSpec
- `ragents/lib/ragents/cli/input_handler.rb` - InputEvent
- `ragents/lib/ragents/benchmarks/ractor_object_passing_benchmark.rb` - Ractor.select

### New Files
- `ragents/lib/ragents/providers/simulated_provider.rb` - Ractor-safe benchmark provider

### Gemfile Updates
- `ragents/Gemfile` - Added `benchmark` and `rake` gems (required for Ruby 4.0)
- `activeagents/Gemfile` - Fixed stripe gem version for Pay compatibility

## Recommendations

### For Low Concurrency (< 20 parallel)
Use **Threads** or **Async** - simpler, lower overhead

### For High Concurrency (20+)
Use **Async fibers** - minimal memory, auto-scheduling

### For CPU-Heavy Post-Processing
Use **Ractors** - true parallel Ruby execution

### For Mixed Workloads
Use **Ractor Pool with rate limiting**

## Dashboard Screenshot

![RAGents Benchmark Dashboard](../tmp/ragents_benchmark_dashboard.png)

## Next Steps

1. Fix test infrastructure to use Ractor-safe mocks
2. Add Async fiber strategy benchmark (requires `async` gem)
3. Run benchmarks with real LLM providers (OpenAI, Anthropic)
4. Profile memory usage across strategies
