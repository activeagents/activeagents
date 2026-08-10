# Support Inbox — ActiveAgent example app

A small but real Rails app that shows the whole ActiveAgent product loop:

- **AI product features** built on the [activeagent](https://github.com/activeagents/activeagent) gem:
  - `TriageAgent` — classifies each ticket (category / priority / sentiment + one-line summary), parsed defensively from a JSON-shaped response
  - `SupportReplyAgent` — drafts replies grounded in matching knowledge-base articles (`config/knowledge_base.yml`), with the conversation persisted through [solid_agent](https://github.com/activeagents/solid_agent)
  - `SummarizeAgent` — running thread summaries
- **Monitoring**:
  - In development, traces land in the gem's **dev console** at [`/activeagents`](http://localhost:3000/activeagents)
  - In production (or whenever `ACTIVEAGENTS_API_KEY` is set), traces POST to the **ActiveAgents platform** — the same pipeline, hosted
  - Every persisted `AgentGeneration` carries the `trace_id` of the telemetry trace that produced it, so a conversation row here links to its trace on the dashboard

It works **without any API keys**: the gem's mock provider exercises the full
prompt → provider → response pipeline (including token accounting and
telemetry). Set `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` to use a real model.

This app doubles as the **runnable reference for the self-hosted
(enterprise) observability mode** — an existing Rails app that mounts
`ActiveAgent::Dashboard::Engine` and stores its own traces. The full
deployment story (production auth, ingest keys, fleet ingest, subdomain
mounts) is in the gem's `docs/framework/self-hosted-observability.md`.

## Run it locally

```bash
bundle install
bin/rails db:prepare db:seed
bin/rails server
```

Open http://localhost:3000, click into a ticket, and hit **Triage**,
**Draft reply**, or **Summarize thread**. Then open
http://localhost:3000/activeagents to see each click as a trace with a span
waterfall and token counts.

To post traces to a platform workspace instead (hosted or local):

```bash
ACTIVEAGENTS_API_KEY=<your workspace key from the Organization page> \
ACTIVEAGENTS_TELEMETRY_ENDPOINT=https://staging.activeagents.ai/v1/traces \
bin/rails server
```

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `AI_PROVIDER` | `mock`, `openai`, or `anthropic` | auto: first provider with credentials, else `mock` |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | real model credentials | — |
| `ACTIVEAGENTS_API_KEY` | workspace telemetry key (Organization page) | — (dev falls back to the local dev console) |
| `ACTIVEAGENTS_TELEMETRY_ENDPOINT` | trace ingest URL | `https://api.activeagents.ai/v1/traces` |

## Deploy to staging

The platform repo's staging terraform can run this app as a public Cloud
Run service that posts telemetry to the staging platform:

1. Sign up on staging and copy the workspace API key from the Organization page.
2. In the GitHub repo settings set the **repository variable** `DEPLOY_DEMO_APP=true`
   and the **secret** `DEMO_ACTIVEAGENTS_API_KEY=<that key>`.
3. Run the *Deploy to Staging* workflow. The job summary prints the demo
   app's `run.app` URL (also `terraform output demo_app_url`).

Details: `terraform/modules/demo-app`. The service uses ephemeral SQLite
(re-seeded on every boot, max one instance) — it is a demo, not a place to
keep data. Agents default to the mock provider; set `demo_ai_provider` in
terraform (plus provider keys as env) for real models.

## Tests

```bash
bin/rails test
```

Five integration tests cover the three agent features, solid_agent
persistence with trace correlation, and the send-draft flow — all against
the mock provider.

## Notes

- The `Gemfile` tracks both gems' `main` branches (pin released versions
  once activeagent v2 ships).
