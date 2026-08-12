# Observability (Traces & Metrics)

The platform's observability stack is the **hosted, multi-tenant deployment of
the activeagent gem's own dashboard/telemetry implementation** — the same
pipeline behind the gem's local dev console. Metric definitions match the
gem's dashboard (`ActiveAgent::Dashboard`), and the hosted code reuses the
gem's classes rather than reimplementing them.

Positioning — the same engine runs in three contexts:

- **Dev console** (free, in the gem): local traces while you build.
- **Self-hosted enterprise**: a customer mounts the engine in their own
  Rails app (e.g. `activeagents.combinaut.com`) as a production trace
  sink for their fleet — see the gem's
  `docs/framework/self-hosted-observability.md`. Data stays in their
  database; the richer React suite below stays platform-only.
- **Hosted platform** (this app): the paid, multi-tenant product at
  activeagents.ai. Free workspaces get a deliberately low-volume trial
  (see Quotas). Note the platform does **not** mount the engine — it
  subclasses the gem's trace model and ingest controller and layers its
  own React read path on top.

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

## Customer setup (dev console → hosted)

A customer app using the activeagent gem sends traces here with:

```yaml
# config/active_agent.yml
telemetry:
  enabled: true
  endpoint: https://api.activeagents.ai/v1/traces
  api_key: <%= ENV["ACTIVEAGENTS_API_KEY"] %>
```

During development the gem's own dev console
(`rails g active_agent:dashboard:install` + `local_storage: true`) shows the
same Traces/Metrics views against local data — same pipeline, so what a
developer sees locally is what the platform shows in production.

## Platform-executed agents

`AgentExecutionService` (used by `AgentExecutionJob` and
`Agent#test_execute`) executes dashboard-built agents through the gem:

- The agent's configured provider is used when its credentials are present
  in `config/active_agent.yml` (e.g. `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`). Otherwise execution raises
  `AgentExecutionService::ProviderNotConfiguredError` and the run is marked
  failed with that message. There is no mock fallback outside the test
  environment, so every stored run, trace and generation reflects a real
  provider response.
- Each run records a telemetry trace (root + llm spans with real timings and
  token usage) whose `trace_id` matches `AgentRun#trace_id`, so runs and
  traces correlate.

## Quotas

Trace ingestion is limited per plan (`Account::TRACE_LIMITS`): free 250
traces/month (trial-sized), pro 25,000/month, enterprise unlimited. Agent
executions follow `Account::USAGE_LIMITS` (free 25/month trial, pro 10,000).
Retention is plan-based too (`TraceRetentionJob::RETENTION`: 3 days free,
14 days pro, 400 days enterprise — job not yet scheduled). Quotas are
enforced at the ingest endpoint (429 when exhausted) and the execution API
(402), and surfaced in `Account#usage_stats`.

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

## Evaluations

Evaluations score an agent's persisted generations (`agent_generations`)
against configurable criteria — matching the lander's Evaluations preview:

- **Rule-based criteria** (always available, deterministic):
  `response_present`, `min_length`, `max_latency_ms`, `token_budget`,
  `contains` / `not_contains`
- **LLM-as-judge** (`llm_judge`): a judge model scores each sample
  0.0–1.0; requires real provider credentials and is reported as
  *skipped* — never faked — without them

Models: `Evaluation` (per-agent definition) and `EvaluationRun` (scores
per criterion with min/max/passed counts). API: `/api/evaluations`
(index/show/create/run/destroy). Runner: `EvaluationRunnerService`.

## Cost estimation

The gem's telemetry records tokens only; the platform layers pricing on
top via `ModelPricing` (per-model $/1M token table with a blended
fallback). Estimated costs appear per trace (`estimated_cost` in
`/api/traces`), and in `/api/metrics` as `summary.total_cost` plus a
per-agent `cost` — always labeled as estimates.

## Non-ActiveAgent clients (RubyLLM, others)

The ingest endpoint is framework-agnostic — anything that POSTs the
documented wire format with a workspace API key feeds the same dashboard.
For apps built directly on RubyLLM, see
[docs/integrations/ruby_llm.md](../integrations/ruby_llm.md) for a
vendorable adapter that bridges RubyLLM's `chat.ruby_llm` instrumentation
events to `/v1/traces`.

## Gem-side gaps: current status

Earlier platform workarounds have been fixed upstream in the activeagent
gem:

- ~~Engine `app/` classes not autoloadable in a host app~~ — fixed:
  `Engine.find_root` points at the dashboard directory before load paths
  are computed, and the gem's `test/dashboard/engine_integration_test.rb`
  asserts autoloadability. No manual requires needed.
- ~~Reporter local-storage symbol-key payloads dropped by the
  normalizer~~ — fixed upstream; the reporter stringifies before
  persisting.
- Token double-counting on root+llm spans — fixed upstream
  (`create_from_payload` treats child spans as authoritative). The
  platform's `TelemetryTrace.dedupe_token_totals!` is therefore redundant
  and kept only as belt-and-braces for old SDKs; it can be removed once
  pre-fix SDK versions are out of the wild.
