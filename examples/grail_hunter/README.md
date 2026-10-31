# Grail Hunter

Agents that hunt the rare stuff. A Rails 8 app built on
[Active Agent](https://github.com/activeagents/activeagent): collectors describe the
niche thing they are after (a 90s Patagonia Snap-T in M under $150, a Seiko Pogue,
a Leica M6 that is not a TTL) and agents search the marketplaces on a schedule, score
what they find against the brief, and surface only the listings worth a look.

The product takes a fee each time the agent hunts. A subscription lowers that fee
and lets the agent check daily or hourly instead of weekly.

| Plan | Monthly | Fee per hunt | Schedules | Active hunts |
|---|---|---|---|---|
| Pay as you go | $0 | $1.99 | on demand, weekly | 3 |
| Collector | $9 | $0.49 | + daily | 10 |
| Hunter | $29 | $0 | + every 6 hours, hourly | 50 |

Plans live in `config/plans.yml`; nothing about them is hard-coded.

## How a hunt runs

```
Hunt (the brief + a schedule)
  └─ DiscoveryRun (one agentic pass, a trace on the dashboard)
       ├─ 1. ProductSearch fetches candidates for the hunt's queries
       ├─ 2. HunterAgent reads the brief and the candidates, then works its tools:
       │      search_products   -> ProductSearch (catalog | SerpApi | Brave)
       │      inspect_listing   -> one listing's full details
       │      evaluate_listing  -> ListingEvaluatorAgent (a delegation, returns a schema)
       │      plan_queries      -> QueryPlannerAgent    (a delegation, returns a schema)
       │      record_finding    -> Finding rows, one per listing URL per hunt
       ├─ 3. candidates the agent did not record get a heuristic score (the mock
       │      provider cannot call tools, so the loop still produces findings offline)
       └─ 4. summary, tokens, trace id, the plan's fee (a Charge), the hunt's next run,
              and a digest email when there are new finds
```

The pieces, in Active Agent terms:

- **Agents are controllers.** `HunterAgent#hunt` is the action; its system prompt is
  `app/views/agents/hunter/instructions.md.erb` and its message is `hunt.md.erb`, an
  ERB template over the hunt and the candidates. Its tools are public methods
  matched by name.
- **Delegation.** `ListingEvaluatorAgent` and `QueryPlannerAgent` declare contracts
  with `delegation ... returns do ... end`; `HunterAgent` offers them with
  `delegate_to` under a `delegation_budget`, so the scoring prompt never leaks into
  the orchestrator and no hunt can spend more than its budget on sub-agents.
- **Structured output.** The delegations' `returns` schemas become each sub-agent's
  response format; the caller gets data, or a structured `invalid_result` it can act on.
- **Persistence.** `has_context` (solid_agent) stores every run's conversation, tool
  exchange included, on the `DiscoveryRun`, carrying the telemetry `trace_id`.
- **Observability.** Every generation is a trace in the Active Agent dashboard
  (the `actionagent` engine) at `/activeagents`, with a span waterfall, tool calls
  and token counts. Runs link to their traces.
- **Scheduling.** `ScheduleHuntsJob` runs on Solid Queue's recurring schedule
  (`config/recurring.yml`) and queues a `DiscoveryRunJob` for every hunt that is due.
  How often a hunt may be due is what the plan sells.

## Run it

Ruby 3.3, SQLite. No API keys are needed to try it.

```bash
bundle install
bin/rails db:prepare db:seed
bin/dev
```

Open <http://localhost:3000>. The seed makes two accounts, password `password`:

- `collector@example.com`: a collector on the Collector plan with three hunts. Open one
  and press **Run hunt now**.
- `admin@example.com`: the install's admin, who can open the dashboard at
  <http://localhost:3000/activeagents> and watch each run land as a trace.

The first account registered on a fresh install becomes its admin.

`bin/dev` runs Puma with Solid Queue inside it, so discovery runs and the hunt
scheduler execute in the same process. Mail is logged in development.

### Without keys: the mock provider

Out of the box the agents run on Active Agent's mock provider. It exercises the full
prompt, provider, telemetry and persistence pipeline but answers in pig latin and
never calls tools, so a run falls back to heuristic scoring of the search backend's
candidates and marks each finding `heuristic`. The "Plan queries" button reports the
planner's `invalid_result` for the same reason. Everything else, fees and schedules
and traces included, is real.

### With a model

```bash
OPENAI_API_KEY=sk-...        bin/dev      # gpt-4o-mini by default
ANTHROPIC_API_KEY=sk-ant-... bin/dev      # claude-haiku-4-5 by default
```

`AI_PROVIDER` (`mock`, `openai`, `anthropic`, `openrouter`) overrides the choice when
more than one key is set; `OPENAI_MODEL`, `ANTHROPIC_MODEL` and `OPENROUTER_MODEL`
pick the model. See `config/active_agent.yml`.

### With real marketplaces

The search tool has three backends behind one interface (`app/services/product_search/`):

| Backend | Env | What it is |
|---|---|---|
| `catalog` | none | `config/catalog.yml`, 37 sample listings matched by keyword overlap. The default. |
| `serpapi` | `SERPAPI_KEY` | Google Shopping via SerpApi: structured price, merchant, thumbnail. |
| `brave` | `BRAVE_SEARCH_API_KEY` | Brave web search: reaches Grailed, Vinted, Reverb, Discogs; prices parsed from snippets. |

`PRODUCT_SEARCH_BACKEND` forces one. Adding a backend is one class with `search` and
`fetch` returning `ProductSearch::Listing` structs.

### Other settings

| Variable | Purpose |
|---|---|
| `ACTIVEAGENTS_API_KEY` | In production, post traces to the ActiveAgents platform instead of storing them locally (`ACTIVEAGENTS_TELEMETRY_ENDPOINT` to change the ingest URL). |
| `MAIL_FROM` | The digest's sender. |
| `SOLID_QUEUE_IN_PUMA` | Set by `bin/dev`. In production run `bin/jobs` instead, or keep the Puma plugin. |

## Billing

`Billing` (`app/services/billing.rb`) is a ledger: every fee is a `Charge` row the
account page itemises. A run's fee is fixed when the run is queued, at the rate of the
plan the collector is on, and booked when it completes; subscribing books a month and
moves the account; cancelling moves it back and slows hunts the default plan does not
allow to its fastest schedule.

Payment collection sits behind `Billing.gateway`. The shipped `Gateways::Ledger`
settles charges on the books and moves no money, which is what a demo wants. A card
gateway implements the same `charge!` method against Stripe or similar and settles or
voids the row from its webhook.

## Tests

```bash
bin/rails test
```

The suite runs offline: the mock provider stands in for a model, the sample catalog for
the marketplaces, and WebMock stubs the SerpApi and Brave backends. It covers the plan
rules, the hunt schedule, every search backend, the heuristic ranker, the agent's tools
and delegations, the full pipeline (findings, fee, schedule, digest, trace correlation,
persisted conversation), the scheduler job, and the sign-up, hunt, billing and
dashboard-access flows.

## Layout

```
app/agents/              HunterAgent, ListingEvaluatorAgent, QueryPlannerAgent
app/views/agents/        their prompt templates (instructions + one per action)
app/services/discovery/  Pipeline, HeuristicRanker, FindingRecorder
app/services/product_search/   Listing, PriceParser, Backend, backends/{catalog,serp_api,brave}
app/services/billing.rb  plans, fees, subscriptions; gateways/ledger.rb
app/models/              User, Plan (from config/plans.yml), Hunt, DiscoveryRun, Finding, Charge
app/jobs/                DiscoveryRunJob, ScheduleHuntsJob
config/plans.yml         the three plans
config/catalog.yml       the offline sample listings
config/active_agent.yml  providers and telemetry
config/recurring.yml     the scheduler
```

## Notes

- `config/application.rb` requires `zeitwerk` before `Bundler.require`: actionagent 1.9.6
  reads Zeitwerk's inflector while its engine class loads, and Rails 8.1 only requires
  Zeitwerk once the autoloaders are set up.
- The sample catalog's listing URLs point at an example host. They are invented for the
  demo, not real listings.
