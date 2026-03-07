# Ragents

**Ractor-based AI Agents for Ruby 4.x**

Ragents brings the [Ractor concurrency model](https://docs.ruby-lang.org/en/4.0/Ractor.html) to AI agent orchestration. Each agent turn runs in its own Ractor — an isolated parallel execution context with its own Global VM Lock — enabling true multi-core utilisation for LLM workloads.

```
Ruby Pattern         →    Ragents Pattern
Ractor               →    Agent execution unit (own GVL, isolated memory)
Ractor.send/yield    →    Tool call dispatch + result passing
Data.define structs  →    Immutable, zero-copy Message objects
Supervisor Ractor    →    Tool executor + agent orchestrator
```

## Why Ractors for LLM Agents?

LLM operations are uniquely suited to Ractor-based concurrency:

| Concern | Threads | Ractors |
|---------|---------|---------|
| I/O parallelism | ✓ (GVL released during I/O) | ✓ (own GVL per Ractor) |
| CPU parallelism | ✗ (shared GVL) | ✓ (independent GVLs) |
| Memory isolation | ✗ (shared heap) | ✓ (isolated heaps) |
| Shared-state bugs | Possible | Impossible by design |
| Context propagation | Manual locking | Immutable message passing |

For LLM workloads, the Ractor advantage compounds:

1. **Response parsing is CPU-bound** — JSON parsing, token counting, context building all compete for the GVL in a threaded model. With Ractors, N agents parse N responses in true parallel.
2. **Tool execution is safely isolated** — tools run in the supervisor Ractor, not the worker Ractor, giving clean separation between LLM reasoning and side effects.
3. **Context is structurally safe** — conversation history is passed as frozen `Data.define` structs (zero-copy across Ractor boundaries), not as mutable Hashes requiring Marshal serialisation.

## Installation

Add to your Gemfile:

```ruby
gem "ragents"
```

**Requires Ruby 4.0+** (for the stabilised Ractor API).

## Quick Start

### Simple Agent

```ruby
require "ragents"

agent = Ragents::Ractor::AgentRactor.new(
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  system_prompt:  "You are a helpful assistant"
)

result = agent.run("What is the capital of France?")
puts result.content  # => "Paris is the capital of France."
```

### With Tools

Tools are the primary way agents interact with the outside world. They're defined as immutable objects that the LLM can invoke by name:

```ruby
weather_tool = Ragents::Tool.new(
  name: "get_weather",
  description: "Get the current weather for a city",
  parameters: {
    type: "object",
    properties: {
      city: { type: "string", description: "The city name" }
    },
    required: ["city"]
  }
) { |city:| WeatherAPI.current(city).to_json }

agent = Ragents::Ractor::AgentRactor.new(
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  tools: [weather_tool],
  system_prompt: "You help users check the weather."
)

result = agent.run("What's the weather in Tokyo?")
```

### Parallel Processing with a Pool

```ruby
pool = Ragents::Ractor::AgentPool.new(
  size: 8,   # 8 parallel agent Ractors
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  system_prompt: "You are a concise assistant."
)

questions = [
  "Explain quantum entanglement",
  "What is a monad?",
  "Describe the Ractor model",
  # ...
]

results = pool.process(questions)
results.each { |r| puts r.content }
```

### Agent-as-a-Tool (Multi-Agent Orchestration)

One agent can call another as a tool. The orchestrator runs in its own Ractor while sub-agents run in their own Ractors in parallel:

```ruby
supervisor = Ragents::Ractor::Supervisor.new

supervisor.register("researcher",
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  system_prompt:  "You are a meticulous research assistant. Find facts and cite sources."
)

supervisor.register("writer",
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  system_prompt:  "You are a skilled technical writer. Write clear, engaging content."
)

# Build tool wrappers that the orchestrator can call
research_tool = supervisor.agent_tool("researcher", description: "Research a topic in depth")
writing_tool  = supervisor.agent_tool("writer",     description: "Write polished content about a topic")

orchestrator = Ragents::Ractor::AgentRactor.new(
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  tools:          [research_tool, writing_tool],
  system_prompt:  "You coordinate research and writing tasks."
)

result = orchestrator.run("Write a blog post about Ruby Ractors")
puts result.content
```

### Context Management and Continuity

Context (conversation history) is managed via immutable `Data.define` structs that can cross Ractor boundaries safely:

```ruby
# Start a conversation
agent = Ragents::Ractor::AgentRactor.new(...)
result1 = agent.run("My name is Alice.")

# Continue with the previous context — zero-copy Ractor transfer
result2 = agent.run("What is my name?", context_snapshot: result1.context_snapshot)
# => "Your name is Alice."

# Fork the context to two sub-agents simultaneously
snapshot = result1.context_snapshot  # frozen Array<Message>

results = agent.run_parallel(
  ["Tell me a joke about my name", "What does my name mean?"],
  context_snapshot: snapshot
)
```

## Message Types

All messages are `Data.define` structs — frozen at creation, zero-copy across Ractor boundaries:

```ruby
# User input
Ragents::UserMessage.new(content: "Hello", name: "Alice")

# Assistant response
Ragents::AssistantMessage.new(content: "Hi!", input_tokens: 5, output_tokens: 3)

# System instruction
Ragents::SystemMessage.new(content: "Be concise.")

# LLM-requested tool invocation
Ragents::ToolCallMessage.new(tool_call_id: "tc_1", name: "search", arguments: { query: "Ruby" })

# Tool execution result
Ragents::ToolResultMessage.new(tool_call_id: "tc_1", name: "search", content: "Found 42 results")

# Cross-agent invocation
Ragents::AgentCallMessage.new(call_id: "ac_1", agent_name: "researcher", input: "Explain Ractors")
```

## Providers

Ragents ships with pure-Ruby providers using only `Net::HTTP` — no SDK dependencies:

| Provider | Class | Config |
|----------|-------|--------|
| OpenAI / Azure / OpenRouter / Ollama | `Ragents::Providers::OpenAIProvider` | `api_key:`, `base_url:`, `default_model:` |
| Anthropic Claude | `Ragents::Providers::AnthropicProvider` | `api_key:`, `default_model:` |
| Testing / Benchmarks | `Ragents::Providers::MockProvider` | `responses: [...]` |

### Custom Provider

```ruby
class MyProvider < Ragents::Providers::BaseProvider
  def initialize(api_key:)
    @api_key = api_key.freeze
    freeze  # make shareable across Ractors
  end

  def chat(messages:, tools: [], model: nil, **opts)
    # Call your API...
    Ragents::Providers::GenerationResult.new(
      content: "Response from my LLM",
      tool_calls: [],
      model: "my-model"
    )
  end
end
```

## Benchmarks

Run the included benchmarks to see the concurrency strategy tradeoffs on your hardware:

```bash
# Compare Sequential / Threads / Ractors / Async
ruby lib/ragents/benchmarks/concurrent_llm_benchmark.rb

# Puma vs Falcon vs Ragents architectural comparison
ruby lib/ragents/benchmarks/puma_vs_falcon_comparison.rb

# Ractor object passing cost (context propagation overhead)
ruby lib/ragents/benchmarks/ractor_object_passing_benchmark.rb
```

### Strategy Decision Matrix

| Scenario | Recommended |
|----------|-------------|
| < 25 concurrent LLM ops | Puma + Threads |
| 25–10,000 concurrent LLM ops | Falcon + Async Fibers |
| CPU-heavy response processing | Ragents Ractor Pool |
| Agent-as-a-tool orchestration | Ragents Supervisor |
| Background LLM jobs (Rails) | `Async::Job` adapter |
| Mixed I/O + CPU | Falcon + Ragents (hybrid) |

### Puma vs Falcon for LLM Workloads

```
Architecture         Thread count   Memory / conn   CPU parallel?   Max concurrent
─────────────────────────────────────────────────────────────────────────────────
Puma + Threads       25 default     ~8MB / thread   No (GVL)        25 LLM ops
Falcon + Async       1 per core     ~4KB / fiber    No (GVL)        Unlimited I/O
Ragents Ractor Pool  N (pool size)  ~12MB / Ractor  Yes (N GVLs)    Pool size
```

**Falcon recommendation**: Use `async-job` adapter (no Redis needed):

```ruby
# config/application.rb
config.active_job.queue_adapter = :async_job
```

```ruby
# Gemfile
gem "falcon"
gem "async-job-adapter-active_job"
```

**Puma + Ragents**: Route only LLM jobs through `Async::Job`, keep everything else on Solid Queue:

```ruby
class LlmJob < ApplicationJob
  self.queue_adapter = :async_job

  def perform(input)
    agent = Ragents::Ractor::AgentRactor.new(...)
    result = agent.run(input)
    # ... save result
  end
end
```

## Architecture Deep Dive

### The Ractor Protocol

```
Caller (main Ractor / supervisor)
    │
    ├── Spawns worker Ractor with frozen config
    │       (provider_class, tools, system_prompt — all frozen/shareable)
    │
    │◄──────── Ractor.yield(ToolRequestMessage)   # worker needs a tool
    │──────── Ractor.send(ToolResultsMessage)      # supervisor executes & returns
    │
    │◄──────── Ractor.yield(FinalMessage)          # worker done
    │
    └── Returns RunResult (content + context snapshot)
```

### Object Passing and the Zero-Copy Advantage

```ruby
# Mutable Hash — MUST be Marshal-serialised to cross Ractor boundary (~µs overhead)
{ role: "user", content: "Hello" }  # NOT Ractor-shareable

# Ragents UserMessage — frozen Data struct, zero-copy Ractor transfer
Ragents::UserMessage.new(content: "Hello")  # Ractor-shareable by reference

# Benchmark result (20-message context):
#   Marshal copy  : ~150µs per boundary crossing
#   Frozen struct : ~2µs  per boundary crossing (75x faster)
```

### Why Tool Execution Lives in the Supervisor

The supervisor Ractor pattern gives clean separation of concerns:

- **Worker Ractor**: LLM reasoning only — calls provider, updates context, decides tool calls
- **Supervisor Ractor**: Tool execution — has access to databases, file system, network
- **Tool isolation**: A buggy tool cannot corrupt the worker's conversation context
- **Parallelism**: Multiple worker Ractors can share a supervisor, or each have their own

This mirrors the [actor model](https://en.wikipedia.org/wiki/Actor_model) with Ractors as typed actors that communicate exclusively through immutable messages.

## MCP (Model Context Protocol) Integration

MCP tools are first-class citizens in Ragents. Because each agent runs in its own Ractor, MCP calls from multiple agents run in true parallel:

```ruby
mcp_tool = Ragents::Tool.new(
  name: "mcp_filesystem",
  description: "Read and write files via MCP",
  parameters: {
    type: "object",
    properties: {
      operation: { type: "string", enum: ["read", "write"] },
      path: { type: "string" }
    },
    required: ["operation", "path"]
  }
) do |operation:, path:, content: nil|
  # HTTP/stdio call to your MCP server
  McpClient.call("filesystem", operation: operation, path: path, content: content)
end

agent = Ragents::Ractor::AgentRactor.new(
  provider_class: Ragents::Providers::OpenAIProvider,
  provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
  tools: [mcp_tool]
)
```

## Testing

```bash
# Run all tests
bundle exec rake test

# Run a specific test file
ruby test/test_agent_ractor.rb
```

Write tests using the `MockProvider` to avoid live API calls:

```ruby
require "ragents"

agent = Ragents::Ractor::AgentRactor.new(
  provider_class: Ragents::Providers::MockProvider,
  provider_opts: {
    responses: [
      { content: "The answer is 42." }
    ]
  }
)

result = agent.run("What is the answer?")
assert_equal "The answer is 42.", result.content
```

## CLI

```bash
# Chat with a mock agent (no API key needed)
bin/ragents

# Chat with OpenAI
OPENAI_API_KEY=sk-... bin/ragents --provider openai --model gpt-4o-mini

# Custom system prompt
bin/ragents --provider openai --system "You are a Ruby expert"
```

## Related Projects

- [ActiveAgent](https://github.com/activeagents/activeagent) — Rails-integrated AI agents (ActionMailer pattern)
- [SolidAgent](https://github.com/activeagents/solid_agent) — Database-backed context, manifest loading
- [RubyLLM](https://github.com/crmne/ruby_llm) — Unified Ruby LLM client (15+ providers)
- [Async](https://github.com/socketry/async) — Fiber-based async for Ruby

## License

MIT
