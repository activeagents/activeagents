# Auto-registered agents + the sandbox as an agent builder

Status: design, 2026-07-30. Companion to
[rubyllm-telemetry-local-validation.md](rubyllm-telemetry-local-validation.md).

Two halves of one idea:

1. **Discovery** — any interaction we observe (RubyLLM, RubyLLM agents,
   ActiveAgent, anything reporting traces) automatically registers a persistent
   `Agent` record, so the thing that ran has an identity instead of a string.
2. **Authoring** — the sandbox becomes a place to iterate on instructions /
   tools / MCP, where every run *before* you save is itself an auto-named agent
   showing up in Traces and Interactions.

Both converge on the same rule: **an agent record is created by observation, not
by a form.** Saving is a promotion, not a creation.

## The gap today

`active_agent_telemetry_traces.agent_class` is a bare **string** (schema.rb:44)
with no foreign key to `agents`. Assistant appears in Traces and (since the
Interactions work) in Interactions, but owns nothing — you can't click through
to its config, version its instructions, evaluate it, or compare models,
because as far as the platform is concerned it is a label on some rows.

Meanwhile `AgentRun` *does* carry `trace_id` (agent_run.rb:10, validated
present), so platform-executed agents already have the link. The asymmetry is
the whole problem: agents we ran are first-class, agents we merely observed are
not.

Locally right now: 9 traces from `cms-acme`, 0 agent records.

## Part 1 — auto-registration on ingest

### Identity

Reported traces carry exactly the dimensions needed. Observed today:

| service_name | environment | agent_class | agent_action | sdk |
|---|---|---|---|---|
| `cms-acme` | development | Assistant | respond | `active_agents-ruby_llm` |
| `cms-acme` | development | Assistant | title | `active_agents-ruby_llm` |

Natural key: **`account_id` + `service_name` + `agent_class` + `agent_action`**.

An earlier draft of this doc keyed on `agent_class` alone, treating
`agent_action` as behavior *within* one agent. That is wrong, and the customer
CMS is the counterexample. `Assistant.respond` and `Assistant.title` share a
name and nothing else:

| | `Assistant.respond` | `Assistant.title` |
|---|---|---|
| Instructions | `admin_instructions(tools)` — "You are an admin-only assistant…" | `TITLE_INSTRUCTIONS` — "Generate a short, specific chat title… 3 to 7 words" |
| Tools | every MCP diagnostic tool | none |
| Temperature | default | 0.2 |
| Chat object | the persisted `CmsAI::Chat` | a throwaway `RubyLLM.context.chat` |
| Observed cost/run | $0.0247 – $0.0530 | $0.0003 – $0.0005 |

Different system prompt, different tools, different sampling, different chat
object, ~100× different cost (`chat_response.rb:47-57` vs `chat.rb:44,117`).
They are two agents that happen to share a class name because one app method
spawns both.

Collapsing them would ruin exactly the numbers the platform exists to show:
one blended cost-per-run averaging a $0.03 tool-using agent with a $0.0004
one-shot, one latency figure mixing 13s against 2s, and evaluations that can't
target either independently. Model comparison would be meaningless — you'd be
asking "is Haiku good for Assistant?" when the honest answer differs sharply
between its two jobs.

So: **one agent per observed `Agent.action`.** `Assistant` becomes a *group* in the
UI, not a record. That grouping already exists in the traces filter
(`Assistant#respond` / `Assistant#title`), so the display convention is settled.

`environment` is deliberately **not** in the key: the same agent running in
development and production is one agent with runs in two environments.
Splitting on it would fragment the exact comparison you'd want to make.

`sdk_info.name` (`active_agents-ruby_llm`, `activeagent`, …) becomes the
`source` attribute — how we discovered it — not part of identity.

### Where it hooks

`TelemetryTrace.create_from_payload` (telemetry_trace.rb:26) is the single
ingest chokepoint for every trace, reported or platform-generated. Register
there, after the record is saved:

```ruby
def self.create_from_payload(trace, sdk_info = {}, account: nil)
  record = super
  record.send(:dedupe_token_totals!)
  AgentRegistrar.call(record)          # new
  record
end
```

`AgentRegistrar` finds-or-creates the `Agent` and backfills `agent_id` on the
trace. Must be cheap and must never break ingest — a registration failure
should log and drop, never 500 the customer's telemetry.

### What gets created

The `agents` table already has every column needed (`instructions`, `tools`,
`mcp_servers`, `provider`, `model`, `status`, `slug`, plus `agent_class_name`).
An auto-registered agent is:

- `name` — `Agent.action` (`Assistant.respond`), so the two are distinguishable
  wherever a bare name is shown
- `slug` — service + class + action (`cms-acme-assistant-respond`), unique
  per user (schema.rb:247)
- `provider` / `model` — from the llm span's `llm.provider` / `llm.model`
  attributes, i.e. what it actually ran with
- `instructions` — from `llm.instructions` **when content capture is on**;
  otherwise blank. Note this is per-action and genuinely differs:
  `Assistant.respond` carries the admin-assistant prompt, `Assistant.title` the
  title-writing one
- `tools` — from the tool spans observed on its traces, which is how
  `Assistant.respond` acquires a tool list and `Assistant.title` correctly stays empty
- `status` — a new `observed` state (see below)
- `agent_class_name` — the reported class (`Assistant`), the grouping key

Everything else stays empty until either capture fills it or someone edits it.

### The `observed` status

`Agent` has `enum :status, { draft: 0, active: 1, archived: 2 }` (agent.rb:16).
Add `observed: 3` for records the platform created by watching rather than
being told. This matters for three reasons:

- The agents list shouldn't imply you authored something you didn't. Observed
  agents want their own section or filter.
- Editing an observed agent is meaningless for execution — we can't push
  instructions back into someone else's app. The editor should be read-only for
  observed agents except where it's used to *fork* one into a real agent.
- Usage limits and billing likely count authored agents differently from
  discovered ones.

Fork is the interesting affordance: "you've been observing an agent for a
month — create an editable copy seeded with its real instructions, tools, and
model." That's a genuinely good onboarding path from monitoring into the
platform.

### Schema

```ruby
add_reference :active_agent_telemetry_traces, :agent, foreign_key: true, index: true  # nullable
add_column :agents, :service_name, :string
add_column :agents, :source, :string          # sdk_info.name
add_column :agents, :first_observed_at, :datetime
add_column :agents, :last_observed_at, :datetime
add_column :agents, :action_name, :string
add_index  :agents, [:user_id, :service_name, :agent_class_name, :action_name], unique: true
```

`agent_id` nullable and backfillable — existing traces keep working, and a
backfill job can attach history to newly registered agents.

`Agent belongs_to :user` (agent.rb:4), its slug is unique per `user_id`, and the
whole API scopes through `current_user.agents` (agents_controller.rb:238,
evaluations_controller.rb:38). Traces, by contrast, belong to an **account** —
and auto-registration is inherently account-scoped, since a reported trace
arrives with an API key, not a user session.

This is the one real modelling wrinkle. Today every account has exactly one
member, so user-scoping and account-scoping coincide and nothing visibly
breaks — which is precisely why it's easy to build the wrong thing now and
discover it the first time a team adds a second seat. An agent discovered from
a shared API key belongs to the *account*; attributing it to whichever user
happens to be primary means a teammate can't see agents their own app reported.

Recommendation: add `account_id` to `agents` and scope registration by it,
keeping `user_id` as the authoring attribution. Decide before implementation.

## Part 2 — the sandbox as builder

### What the sandbox is today

`/dashboard/sandbox` is a **"PlaywrightMCP Demo"** — a task box, a provider
picker (Anthropic/OpenAI/Ollama), four sample tasks, free-tier counters. It
runs browser automation. It has no instructions field, no tool selection, no
MCP config, and no save. It is a marketing demo, not a builder.

### What already exists

`AgentEditor.jsx` (508 lines) **already has** the tabs you want — Instructions,
Tools, MCP — bound to `formData` with `instructions`, `tools`, `mcp_servers`,
and a working `onSave`. `AgentExecutionService` already runs an agent and
records a trace with `AgentRun#trace_id`.

So the builder is mostly assembly, not invention: put the editor's config panel
next to a run loop, and route each run through the existing execution service.

### Auto-named draft agents

The requirement — *"each time before that it should get an auto generated named
agent in the traces and interactions"* — falls out of Part 1 if sandbox runs go
through the same path. On first run of an unsaved configuration:

1. Create an `Agent` with `status: :draft` and a generated name.
2. Run it through `AgentExecutionService`, which already emits a trace.
3. The trace carries `agent_id`, so it appears in Traces and Interactions
   immediately, attributed to that draft.
4. Editing config and re-running creates an `AgentVersion` (the `after_update`
   callback at agent.rb:21 already does this on config change) — so the
   sandbox's iteration history is versioned for free.
5. "Save as agent" flips `draft` → `active` and takes a real name. Nothing is
   created; a status changes.

Generated names should be readable, not UUIDs — you'll be scanning them in a
trace list. Something like `sandbox-swift-otter-3` (memorable, sortable by
recency). Worth stealing whatever convention the run feed already uses.

Draft cleanup matters: sandbox iteration will produce a lot of abandoned
drafts. Sweep drafts with no runs older than N days, and don't count drafts
against agent quotas.

## Why this ordering

Part 1 stands alone and is worth doing first: it makes every already-reported
trace click through to something, and it's a small, contained change at one
ingest point. Part 2 depends on it (draft agents are just auto-registered
agents with a different origin) and is a much larger UI build.

The payoff of both together is the product story: **monitor an existing agent →
see its real instructions and tools → fork it into the sandbox → iterate →
save.** That's a path from "we watch your app" to "you build here," and each
step already has most of its parts.

## Open questions

- **Agent ownership** — `user_id` vs `account_id` (above). Blocking.
- **Instructions without capture.** `capture_content` is off by default, so most
  reported agents will register with blank instructions. Is an agent with no
  instructions useful enough to show, or does registration wait for capture?
  Leaning: register anyway; the identity and run history are valuable on their
  own, and blank config is honest.
- **Cardinality.** A misconfigured reporter with a dynamic `agent_class` could
  create unbounded agents. Cap per account and stop registering past it.
- **Renames.** If a customer renames their agent class, we create a second
  agent and orphan the first. Probably acceptable; worth a merge affordance
  later.
