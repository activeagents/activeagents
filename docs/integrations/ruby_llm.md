# RubyLLM → ActiveAgents observability

Apps built directly on [RubyLLM](https://github.com/crmne/ruby_llm) — without
ActiveAgent — can still ship traces to the ActiveAgents platform (or a
self-hosted ActiveAgent dashboard). The ingest endpoint (`POST /v1/traces`)
speaks a plain JSON wire format, and RubyLLM ≥ 1.4 has a built-in
instrumentation bus that exposes everything a trace needs.

Two integration paths, in order of preference:

## Option 1: adopt ActiveAgent's RubyLLM provider

If you can wrap your calls in an agent class, ActiveAgent ships a `ruby_llm`
provider that drives RubyLLM under the hood — and you get telemetry, the
free local dashboard, and solid_agent conversation persistence with zero
extra code:

```ruby
class SupportAgent < ActiveAgent::Base
  generate_with :ruby_llm, model: "claude-sonnet-4-5"
end
```

```yaml
# config/active_agent.yml
production:
  ruby_llm:
    service: "RubyLLM"
telemetry:
  enabled: true
  endpoint: https://api.activeagents.ai/v1/traces
  api_key: <%= ENV["ACTIVEAGENTS_API_KEY"] %>
```

## Option 2: instrument RubyLLM directly (no ActiveAgent dependency)

RubyLLM emits `chat.ruby_llm` and `tool_call.ruby_llm` events through a
configurable instrumenter. Point it at `ActiveSupport::Notifications` and
subscribe with the
[activeagents-telemetry-ruby_llm](https://rubygems.org/gems/activeagents-telemetry-ruby_llm)
gem — no dependencies beyond ActiveSupport and the shared telemetry core.

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.instrumenter = ActiveSupport::Notifications
end

ActiveAgents::Telemetry::RubyLLM.subscribe!(
  api_key: ENV["ACTIVEAGENTS_API_KEY"],
  service_name: "my-app"
)
```

Attribute traffic to a logical agent (otherwise it reports as
`RubyLLM::Chat`):

```ruby
ActiveAgents::Telemetry::RubyLLM.with_agent("SupportBot", action: "respond") do
  chat = RubyLLM.chat(model: "gpt-4o")
  chat.ask("How do I reset my password?")
end
```

### How events map to spans

RubyLLM emits a `chat.ruby_llm` event per provider round, and the two
generations of the gem arrange those rounds differently:

- **1.x** recurses through `Chat#complete` for each tool round, so the rounds
  **nest** inside the enclosing event and `tool_call.ruby_llm` fires within it.
- **2.x** drives a flat `step until complete?` loop, so the rounds are
  **siblings** and tool calls fire *between* them.

The adapter accumulates rounds and flushes on the round that ends the turn —
the one that errors, or answers without requesting tools (`payload[:tool_call]`)
— which produces the same trace under both arrangements:

- a `root` span named `Agent.action`,
- one `llm` span covering the whole provider loop, carrying `llm.rounds` and
  token totals summed **per round** from the assistant messages that round
  added (the event-level token fields repeat the last round's counts, so they
  are not used), and
- a `tool` span per `tool_call.ruby_llm` event, with real start/end times and
  `tool.name` / `tool.call_id`, parented under the llm span.

Tool arguments and results are deliberately never sent, and error messages are
truncated — safe defaults for apps whose tool traffic may contain sensitive
data.

### Attributing traffic

RubyLLM carries no application identity on the payload: neither the
`RubyLLM::Agent` class nor an `acts_as_chat` record reaches the instrumenter,
so unattributed traffic reports as `RubyLLM::Chat`. Three ways to name it:

```ruby
# 1. Per call site.
ActiveAgents::Telemetry::RubyLLM.with_agent("SupportBot", action: "respond") { chat.ask(...) }

# 2. From the initializer, derived from the event payload.
ActiveAgents::Telemetry::RubyLLM.subscribe!(
  api_key: ENV["ACTIVEAGENTS_API_KEY"],
  agent_resolver: ->(payload) { { name: "SupportBot", action: payload[:tools].present? ? "respond" : "summarize" } }
)

# 3. Every RubyLLM::Agent subclass, by class name.
module AgentTelemetryAttribution
  def ask(...)
    ActiveAgents::Telemetry::RubyLLM.with_agent(self.class.name) { super }
  end
end
RubyLLM::Agent.prepend(AgentTelemetryAttribution)
```

Option 3 covers `SupportAgent.new.ask(...)` and Rails-backed
`Agent.create!/find` instances. It does **not** cover `SupportAgent.chat`,
which hands back a bare `RubyLLM::Chat` — wrap those call sites, or resolve
from the payload.

### The adapter

Published to RubyGems from
[activeagents/activeagents-telemetry](https://github.com/activeagents/activeagents-telemetry)
(`adapters/ruby_llm`, on the shared `activeagents-telemetry` core):

```ruby
# Gemfile
gem "activeagents-telemetry-ruby_llm"
```

The initializer above is the whole integration. Implementation, tests, and
the full option list live in the adapter's README.

Notes:

- **Scope is chat and tool calls.** RubyLLM also emits `request.ruby_llm`,
  `embedding.ruby_llm`, `image.ruby_llm`, `moderation.ruby_llm`,
  `speech.ruby_llm`, `transcription.ruby_llm`, and
  `models.refresh.ruby_llm`. An app whose RubyLLM usage is embeddings or
  transcription reports nothing today; those events carry their own token
  counts and are a natural extension of the same subscriber.
- **Tool spans** carry real start/end times, so the dashboard's waterfall,
  generation-vs-tools breakdown, and slowest-operations views work for
  RubyLLM apps the same as for platform-executed agents. Concurrent tool
  execution runs tools off the instrumented thread and is not captured —
  sequential execution (the default) is fully covered.
- **Fallbacks** (`with_fallbacks`) retry a failed round against the next
  model in a loop, so each failed attempt closes its own `ERROR` trace and
  the successful attempt closes an `OK` one. That reads as one trace per
  provider attempt, which is what the latency and error-rate metrics want.
- **A turn that never reaches a final round** — a halted tool call, or an app
  driving 2.x's `step`/`run_tools` by hand — is flushed when the next chat
  reports, when `MAX_TURN_SECONDS` elapses, or on an explicit `flush!`.
- **Failures** surface as `status: "ERROR"` traces with the exception class
  and a truncated message attached. Delivery failures (ingest down, bad key)
  are warned and swallowed, never raised into the app.
- Requests are fire-and-forget on a background thread; pass `async: false`
  for deterministic delivery in tests, and stub `post_traces` to assert on
  the built payload. Batch buffering (like
  `ActiveAgent::Telemetry::Reporter`) is a natural upgrade if volume
  warrants it.

## Local / self-hosted dashboards

The endpoint is just a parameter — point it at any deployment of this app or
of the gem's dashboard:

```ruby
ActiveAgents::Telemetry::RubyLLM.subscribe!(
  api_key: ENV["ACTIVEAGENTS_API_KEY"],
  endpoint: ENV.fetch("ACTIVEAGENTS_TELEMETRY_ENDPOINT", ActiveAgents::Telemetry::Configuration::DEFAULT_ENDPOINT),
  service_name: "my-app",
  environment: Rails.env
)
```

For a dashboard running locally (e.g. via `docker-compose.dev.yml` under
OrbStack/Docker Desktop — see `docs/local-mac-llm.md`), set
`ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces` (or the
container's `*.orb.local` hostname) in the reporting app. The Bearer token
is either a platform API key generated from Settings → API Keys (`aa_…`
keys, once PR
[#96](https://github.com/activeagents/activeagents/pull/96) lands) or the
account's legacy `telemetry_api_key` from the Organization page.

For an **enterprise self-hosted mount** of the gem's dashboard engine
(customer's own Rails app, e.g. `activeagents.example.com` — see the
gem's `docs/framework/self-hosted-observability.md`), the endpoint shape
is `<mount>/api/traces`, e.g.
`https://activeagents.example.com/api/traces`, and the Bearer token is
that install's `ActiveAgent::Dashboard.ingest_api_key` (single-tenant) or
an account `telemetry_api_key` (multi-tenant).

## Wire format reference

The endpoint accepts what `ActiveAgent::Telemetry::Reporter` sends —
`{ "traces": [...], "sdk": {...} }` with `Authorization: Bearer
<telemetry_api_key>` (find your key on the dashboard's Organization page).
Full payload spec: activeagent's `docs/framework/telemetry.md`
("self-hosting endpoint requirements"). Anything that speaks this format —
Python sidecars, edge functions, other frameworks — can feed the same
dashboard.

## History

The adapter began as a vendored gem in this repo (`ruby_llm_telemetry/`)
and was extracted to
[activeagents/activeagents-telemetry](https://github.com/activeagents/activeagents-telemetry)
(`adapters/ruby_llm`, on the shared telemetry core) and published as
`activeagents-telemetry-ruby_llm` — the namespace moved from
`ActiveAgents::RubyLLMTelemetry` to `ActiveAgents::Telemetry::RubyLLM` in
the process. First production consumer: a customer CMS's admin chat agent.
