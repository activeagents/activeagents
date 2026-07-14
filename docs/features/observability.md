# Observability (Traces & Metrics)

The platform's observability stack is the **hosted, multi-tenant deployment of
the activeagent gem's own dashboard/telemetry implementation** — the same
pipeline a developer gets for free by self-hosting with the gem. Feature set
and metric definitions are kept in parity with the gem's dashboard
(`ActiveAgent::Dashboard`), and the hosted code reuses the gem's classes
rather than reimplementing them.

## Architecture

```
                     ┌────────────────────────────────────────────┐
 customer Rails app  │            activeagents platform           │
 ┌────────────────┐  │                                            │
 │ activeagent gem│  │  POST /v1/traces                           │
 │   Telemetry::  │──┼─▶ Api::V1::TracesController                │
 │   Reporter     │  │    (subclass of the gem's                  │
 └────────────────┘  │     ActiveAgent::Dashboard::Api::Traces-   │
                     │     Controller; adds plan quotas)          │
                     │        │                                   │
 platform-run agents │        ▼                                   │
 ┌────────────────┐  │  ActiveAgent::ProcessTelemetryTracesJob    │
 │ AgentExecution-│  │        │                                   │
 │ Service        │──┼──▶ TelemetryTrace (< ActiveAgent::         │
 └────────────────┘  │       TelemetryTrace, table                │
                     │       active_agent_telemetry_traces)       │
                     │        │                                   │
                     │        ▼                                   │
                     │  GET /api/traces, /api/metrics             │
                     │  → dashboard Traces & Metrics views        │
                     └────────────────────────────────────────────┘
```

### What comes from the gem

- **Trace model & schema** — `TelemetryTrace < ActiveAgent::TelemetryTrace`
  (`app/models/telemetry_trace.rb`). Table name, scopes (`recent`,
  `with_errors`, `for_agent`, `for_service`, `for_date_range`,
  `for_account`), the `create_from_payload` normalizer and instance helpers
  (`display_name`, `provider`, `model`, `llm_spans`, …) are all inherited.
  The table (`active_agent_telemetry_traces`) matches the gem's
  `--multi_tenant` install-generator migration.
- **Ingestion** — `POST /v1/traces` routes to
  `Api::V1::TracesController`, a subclass of the gem's
  `ActiveAgent::Dashboard::Api::TracesController`. Bearer-token auth against
  `Account#telemetry_api_key`, idempotency by `trace_id`, and async
  processing via the gem's `ActiveAgent::ProcessTelemetryTracesJob` are all
  gem behavior; the subclass only adds plan-based trace quotas (HTTP 429).
- **Span format** — platform-executed agent runs build traces with the gem's
  `ActiveAgent::Telemetry::Span` and persist through the same
  `create_from_payload` normalizer, so platform runs and SDK-reported runs
  are indistinguishable downstream.
- **Metric definitions** — `Api::MetricsController` mirrors the gem
  dashboard's `calculate_metrics` / `agent_statistics` queries (trace count,
  token totals, average duration, error rate, active agents, per-agent
  stats).

### Multi-tenant configuration

`config/initializers/active_agent_dashboard.rb` configures the gem in
multi-tenant mode:

```ruby
ActiveAgent::Dashboard.configure do |config|
  config.multi_tenant = true
  config.account_class = "Account"
  config.trace_model_class = "TelemetryTrace"
end
```

Every trace belongs to an `Account`. Accounts get a `telemetry_api_key`
(generated via `has_secure_token`) shown on the dashboard's Organization
page.

## Customer setup (self-hosted → hosted)

A customer app using the activeagent gem sends traces here with:

```yaml
# config/active_agent.yml
telemetry:
  enabled: true
  endpoint: https://api.activeagents.ai/v1/traces
  api_key: <%= ENV["ACTIVEAGENTS_API_KEY"] %>
```

Self-hosters can instead run the gem's own dashboard
(`rails g active_agent:dashboard:install` + `local_storage: true`) and get
the same Traces/Metrics feature set locally — that's the parity contract.

## Platform-executed agents

`AgentExecutionService` (used by `AgentExecutionJob` and
`Agent#test_execute`) executes dashboard-built agents through the gem:

- The agent's configured provider is used when its credentials are present
  in `config/active_agent.yml` (e.g. `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`). Otherwise execution falls back to the gem's **mock
  provider**, which still runs the full prompt → provider → response
  pipeline with real usage accounting — no hand-rolled fake data.
- Each run records a telemetry trace (root + llm spans with real timings and
  token usage) whose `trace_id` matches `AgentRun#trace_id`, so runs and
  traces correlate.

## Quotas

Trace ingestion is limited per plan (`Account::TRACE_LIMITS`): free 1,000
traces/month, pro 25,000/month, enterprise unlimited. The quota is enforced
at the ingest endpoint (429 when exhausted) and surfaced in
`Account#usage_stats` (`traces_used` / `traces_limit`).

## Conversation persistence (solid_agent)

Alongside span-level traces, every platform execution persists the
conversation itself through the solid_agent gem's `HasContext` concern:

- `AgentContext` — one row per (agent, action): the agent's interaction
  stream (contextable = the dashboard Agent record)
- `AgentMessage` — user/assistant/system/tool messages, with content
  checksums and provenance
- `AgentGeneration` — one row per LLM call: model, tokens, finish reason,
  tool calls, provenance, and a `trace_id` that joins to
  `active_agent_telemetry_traces` (and `AgentRun#trace_id`)

`AgentExecutionService` threads the run's trace_id through
`prompt_options[:trace_id]`; `AgentContext#record_generation_with_provenance!`
(solid_agent's documented extension point) stores it per generation. The
dashboard's Interactions view reads these via `GET /api/interactions`.

Upstream PR making trace correlation first-class in solid_agent's
generators (plus fixes for silently-dropped generations):
activeagents/solid_agent#3.

## Non-ActiveAgent clients (RubyLLM, others)

The ingest endpoint is framework-agnostic — anything that POSTs the
documented wire format with a workspace API key feeds the same dashboard.
For apps built directly on RubyLLM, see
[docs/integrations/ruby_llm.md](../integrations/ruby_llm.md) for a
vendorable adapter that bridges RubyLLM's `chat.ruby_llm` instrumentation
events to `/v1/traces`.

## Known gem-side gaps (worked around here)

- The gem dashboard engine overrides `Engine.root` after Rails computes load
  paths, so its `app/` classes aren't autoloadable in a host app; the
  initializer requires the model/job/controller files explicitly.
- The gem's telemetry instrumentation mirrors LLM token usage on both the
  root and llm spans while `create_from_payload` sums across all spans;
  `TelemetryTrace.dedupe_token_totals!` recomputes totals from child spans
  to avoid double counting.
- The gem's `Reporter` local-storage path serializes trace payloads with
  symbol keys that the normalizer reads back as strings; the platform
  serializes with `as_json` (string keys) before persisting.

These are candidates for upstream fixes in the activeagent gem.
