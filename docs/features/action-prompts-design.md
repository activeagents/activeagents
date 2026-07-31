# Named Action Prompts (Stacked Instructions)

**Date:** 2026-07-30 · **Status:** ✅ Implemented 2026-07-30

Implementation notes (differences from the original proposal):
- `agent_runs.action_name` records the invoked action; `AgentRun#summary`
  serializes it (falls back to metadata, then `ask`).
- Migration `20260730000001` adds `agents.action_prompts` (jsonb) and
  `agent_runs.action_name`.
- Execute/test APIs take `action_name`; the Runner UI shows a `#action`
  picker when the agent defines actions; MCP exposes `expose_as_tool`
  actions as `run_<slug>__<action>`.
- `Agent#instructions_digest_versions` also digests composed (base +
  action prompt) instructions so version labels stay correct per action.
- Verified live: `#summarize` on Docs Navigator ran under composed
  instructions (digest → v5) and produced its own
  `DocsNavigatorAgent#summarize` session.

## Motivation

The activeagent gem lets developers define multiple actions per agent — each
action is a prompt (or tool-exposed capability) with its own template. The
SaaS runner currently hardcodes a single universal `ask` action
(`AgentExecutionService`, `define_method :ask`), so dashboard agents can only
ever have one prompt and one interaction stream.

Dashboard agents should likewise support **named actions, each with its own
system prompt layered on top of the agent's base System Instructions**:

```
system = [base instructions] + "\n\n" + [action prompt]   # per action
```

This mirrors the gem's mental model (Agents = Controllers, actions =
methods), and the telemetry stack already handles it: sessions are keyed by
`(agent, agent_class, action_name)`, and the Interactions views now render
the action as a first-class chip (`Docs Navigator #ask`).

## Data Model

Add `agents.action_prompts` (jsonb, default `[]`):

```json
[
  { "name": "summarize", "prompt": "Summarize the given page...", "expose_as_tool": false },
  { "name": "triage",    "prompt": "Classify the request...",     "expose_as_tool": true  }
]
```

- `name` — snake_case, becomes the action method name and session
  `action_name`. Reserved: `ask` (the default action, uses base
  instructions only).
- `prompt` — the action's system prompt, appended after base instructions.
- `expose_as_tool` — when true, other agents/`call_agent` and MCP list this
  action as a callable tool (matching the gem's "actions as tools" pattern).

Versioning: include `action_prompts` in `Agent#configuration_for_version`'s
tracked keys so editing an action prompt creates an AgentVersion, and
`instructions_digest_versions` gains per-action composed digests (digest of
`base + action prompt`), keeping the `v4 · zesty-vale` cohort labels correct
per action.

## Execution

`AgentExecutionService` builds the dynamic class with one method per action:

```ruby
(agent_record.action_prompts + [{ "name" => "ask" }]).each do |action|
  define_method(action["name"]) do
    prompt_options[:trace_id] = run_trace_id
    load_context(contextable: agent_record)  # keys the stream per action
    composed = [instructions, action["prompt"]].compact_blank.join("\n\n")
    prompt(message: input, instructions: composed, tools: tool_definitions)
  end
end
agent_class.public_send(selected_action).generate_now
```

- `POST /api/agents/:id/execute` accepts `action` (default `"ask"`);
  `AgentRun` gains an `action_name` column so run cohorts can also group by
  action, not just instructions × model.
- MCP tool listing exposes `expose_as_tool` actions as
  `{agent_slug}_{action_name}`.

## UI

- **Agent editor → Instructions tab**: below System Instructions, an
  "Action Prompts" list — add/rename/remove named actions, each with its own
  prompt textarea and an "expose as tool" toggle (mirrors the existing
  Instruction Sets chips row in the screenshot flow).
- **Runner**: action selector (defaults to `ask`) when the agent defines
  extra actions.
- **Interactions**: no changes needed — a new session stream per action
  appears automatically, already labeled with the action chip; the Agent
  Report gains an "by action" grouping alongside instructions × model.

## Out of Scope (for the first cut)

- Per-action model/tool overrides (use the agent's config).
- Templated ERB prompts with params (gem feature; SaaS prompts stay static
  text until the sandbox story needs more).
