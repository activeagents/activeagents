# Observability (Traces & Metrics)

The platform's observability stack is the **hosted, multi-tenant deployment of
the `actionagent` dashboard engine** — the same pipeline a developer gets
locally. Metric definitions match the engine's (`ActionAgent`), and the hosted
code reuses its classes rather than reimplementing them.

Two gems are involved, and the split matters when reading the rest of this
document. Both live in the same repo,
[activeagents/activeagent](https://github.com/activeagents/activeagent):

- **`activeagent`** — the framework. Agents, providers, generation, and the
  telemetry *reporter* that emits traces (`ActiveAgent::Telemetry::Reporter`,
  `ActiveAgent::Telemetry::Span`). Source under `lib/`. Deliberately does not
  depend on activerecord.
- **`actionagent`** — the dashboard, a mountable Rails engine that stores and
  displays those traces. Source under `actionagent/` in the same repo. Depends
  on activeagent, activerecord, railties and solid_agent.

Below, "the framework" means the first and "the engine" means the second;
paths beginning `lib/` or `actionagent/` are relative to that repo's checkout,
not this one.

Positioning — the same engine runs in three contexts:

- **Dev console** (free): add `actionagent` alongside `activeagent` and mount
  it for local traces while you build.
- **Self-hosted enterprise**: a customer mounts the engine in their own
  Rails app (e.g. `activeagents.combinaut.com`) as a production trace
  sink for their fleet — see `docs/framework/self-hosted-observability.md`
  in the gem repo. Data stays in their database, and it is the same
  dashboard, not a traces-only cut of it: agents, interactions, evaluations,
  scorecards, cost estimates, the agent builder, sandboxes, session
  recordings and the agents-as-MCP-server endpoint all ship in the engine.
- **Hosted platform** (this app): the paid, multi-tenant product at
  activeagents.ai. Free workspaces get a deliberately low-volume trial
  (see Quotas). The platform **mounts** `ActionAgent::Engine` at `/dashboard`
  and configures it (`config/initializers/action_agent.rb`); what lives here
  is the hosted business around it — accounts and sessions, plans and
  billing, cloud sandbox backends — not a second copy of the dashboard.

## Architecture

```
 customer Rails app        activeagents platform (this repo)
 ┌────────────────┐        ┌──────────────────────────────────────┐
 │ activeagent    │        │ POST /v1/traces                      │
 │   Telemetry::  │───────▶│   Api::V1::TracesController          │
 │   Reporter     │        │   (subclasses the engine's ingest    │
 └────────────────┘        │    controller, adds plan quotas)     │
   the framework gem       │        │                             │
                           │        ▼                             │
                           │   ActionAgent::                      │
                           │     ProcessTelemetryTracesJob        │
                           │        │                             │
                           │        ▼                             │
                           │   TelemetryTrace                     │
                           │   (active_agent_telemetry_traces)    │
                           │        │                             │
                           │        ▼                             │
                           │   mount ActionAgent::Engine          │
                           │     => "/dashboard"                  │
                           │   the dashboard, its JSON API and    │
                           │   its React app, multi-tenant        │
                           └──────────────────────────────────────┘
                             the ActionAgent:: classes are the
                             actionagent gem, mounted by this app
```

The platform mounts the engine at `/dashboard` and configures it in
`config/initializers/action_agent.rb`. Agent execution, conversations,
evaluations, scorecards, traces and metrics are all the engine's; this app
supplies tenancy (accounts and sessions), plan quotas and usage counters,
per-account provider credentials, and the cloud sandbox backends.

### What comes from the gems

- **Trace model & schema** — `TelemetryTrace < ActionAgent::TelemetryTrace`
  (`app/models/telemetry_trace.rb`). Table name, scopes (`recent`,
  `with_errors`, `for_agent`, `for_service`, `for_date_range`,
  `for_account`), the `create_from_payload` normalizer and instance helpers
  (`display_name`, `provider`, `model`, `llm_spans`, …) are all inherited.
  The table (`active_agent_telemetry_traces`) matches the migration written by
  `rails generate action_agent:install --multi_tenant`.
- **Ingestion** — `POST /v1/traces` routes to
  `Api::V1::TracesController`, a subclass of the engine's
  `ActionAgent::Api::TracesController`. Bearer-token auth against
  `Account#telemetry_api_key`, idempotency by `trace_id`, and async
  processing via the engine's `ActionAgent::ProcessTelemetryTracesJob` are all
  engine behavior; the subclass widens the auth to also accept dashboard API
  keys (Settings → API Keys) and adds plan-based trace quotas (HTTP 429).
- **Span format** — platform-executed agent runs build traces with the
  framework's `ActiveAgent::Telemetry::Span` and persist through the same
  `create_from_payload` normalizer, so platform runs and SDK-reported runs
  are indistinguishable downstream.
- **Metric definitions** — the engine's
  `ActionAgent::Api::MetricsController` (served at
  `/dashboard/api/metrics`) exposes the same aggregates as the engine's own
  server-rendered console page (`<mount>/console/traces/metrics`): trace
  count, token totals, average duration, error rate, active agents and
  per-agent stats, account-scoped and with previous-period deltas.

### Multi-tenant configuration

`config/initializers/action_agent.rb` configures the engine in
multi-tenant mode:

```ruby
ActionAgent.configure do |config|
  config.multi_tenant = true
  config.account_class = "Account"
  config.trace_model_class = "TelemetryTrace"
end
```

Every trace belongs to an `Account`. Accounts get a `telemetry_api_key`
(generated via `has_secure_token`) shown on the dashboard's Organization
page.

It also sets `config.table_name_prefix = ""`. The dashboard's other tables
(agents, runs, evaluations, …) predate the engine here and are unprefixed,
where a fresh install gets `active_agent_*`; the traces table is
`active_agent_telemetry_traces` either way. The remaining seams — quotas,
usage counters, provider credentials, agent scoping, sandbox backends — are
documented inline in the initializer.

## Customer setup (dev console → hosted)

A customer app using the activeagent gem sends traces here with:

```yaml
# config/active_agent.yml
telemetry:
  enabled: true
  endpoint: https://api.activeagents.ai/v1/traces
  api_key: <%= ENV["ACTIVEAGENTS_API_KEY"] %>
```

During development the same dashboard runs locally, against local data — same
pipeline and same code, so what a developer sees locally is what the platform
shows in production. It needs the dashboard gem alongside the framework:

```ruby
# Gemfile
gem "activeagent"
gem "actionagent"
```

then `rails generate action_agent:install` and `local_storage: true` under
`telemetry:` in `config/active_agent.yml`. `local_storage` writes through the
engine's trace model, so it reports that it has nowhere to write if
`actionagent` is not installed. The generator writes two migrations, the
traces table and the rest of the dashboard's tables; `--traces_only` skips the
second for an app that only wants to be a trace sink.

## Platform-executed agents

`ActionAgent::AgentExecutionService` (used by `AgentExecutionJob` and
`Agent#test_execute`) executes dashboard-built agents through the framework:

- The agent's configured provider is used when its credentials are present:
  the account's own provider key first (Settings → Provider API Keys,
  resolved through `config.provider_credentials_resolver`), else the platform
  keys in `config/active_agent.yml` (e.g. `OPENAI_API_KEY`,
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
Retention is plan-based too: `Account::TRACE_RETENTION` (3 days free, 14 days
pro, 400 days enterprise) is handed to the engine as a per-account callable
via `config.trace_retention`, which the engine's
`ActionAgent::TraceRetentionJob` reads — the job is not yet scheduled. Trace
quotas are enforced at this app's ingest endpoint (429 when
exhausted); execution quotas run inside the engine through
`config.quota_checker`, which returns 402 with `Account#usage_stats`.

## Conversation persistence (solid_agent)

Alongside span-level traces, every platform execution persists the
conversation itself through the solid_agent gem's `HasContext` concern.
`ActionAgent::AgentExecutionService` mixes `SolidAgent::HasContext` into the
class it builds for a run, so `actionagent` declares solid_agent as a hard
dependency — one `activeagent` could never declare, since solid_agent depends
on it. The three record classes are the engine's (`ActionAgent::AgentContext`
and friends), aliased here so the bare names still resolve:

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
dashboard's Interactions view reads these via
`GET /dashboard/api/interactions`.

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
per criterion with min/max/passed counts). API:
`/dashboard/api/evaluations` (index/show/create/run/destroy). Runner:
`EvaluationRunnerService`. All three are the engine's classes, so a
self-hosted install gets evaluations too.

## Cost estimation

The framework's telemetry records tokens only; the engine layers pricing on
top via `ModelPricing` (RubyLLM's model registry where the model is known,
otherwise a per-model $/1M token table with a blended fallback). Estimated
costs appear per trace (`estimated_cost` in `/dashboard/api/traces`), and in
`/dashboard/api/metrics` as `summary.total_cost` plus a per-agent `cost` —
always labeled as estimates.

## Non-ActiveAgent clients (RubyLLM, others)

The ingest endpoint is framework-agnostic — anything that POSTs the
documented wire format with a workspace API key feeds the same dashboard.
For apps built directly on RubyLLM, see
[docs/integrations/ruby_llm.md](../integrations/ruby_llm.md) for a
vendorable adapter that bridges RubyLLM's `chat.ruby_llm` instrumentation
events to `/v1/traces`.

## Gem-side gaps: current status

Earlier platform workarounds have been fixed upstream (paths below are in the
gem repo, github.com/activeagents/activeagent):

- ~~Engine `app/` classes not autoloadable in a host app~~ — fixed. The
  dashboard is now its own gem, so `actionagent/` is the engine root and
  `app/` sits directly under it, where Rails already looks. The engine's
  `actionagent/test/engine_integration_test.rb` asserts both autoloadability
  and that every class eager loads. No manual requires needed.
- ~~Reporter local-storage symbol-key payloads dropped by the
  normalizer~~ — fixed in `activeagent`; the reporter stringifies before
  persisting.
- Token double-counting on root+llm spans — fixed in `actionagent`
  (`ActionAgent::TelemetryTrace.create_from_payload` treats child spans as
  authoritative). The platform's `TelemetryTrace.dedupe_token_totals!` is
  therefore redundant and kept only as belt-and-braces for old SDKs; it can be
  removed once pre-fix SDK versions are out of the wild.
