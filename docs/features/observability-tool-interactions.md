# Observability: tool interactions, span breakdowns, multi-agent tools

**Branch:** `claude/analytics-api-key-encryption-9kwpsc` (on top of PR #96)
**Date:** 2026-07-29
**Screenshots:** `tmp/playwright/08–14*.png` (gitignored)

## What changed

### Backend — real tool telemetry

- `AgentExecutionService#execute_tool` now wraps every tool call in a live
  `:tool` span (real start/end around execution) with `tool.name` and
  `tool.args` attributes, replacing the after-the-fact zero-duration
  `tool.unknown` stamps. Run metadata `tool_calls` now reports real names.
- Tool interactions persisted to conversations now carry `tool_name`,
  `tool_arguments`, and `duration_ms` (`AgentContext#add_tool_message`
  extended; provider messages without names fall back to the service's
  invocation record).
- `Api::AgentRunsController#show` returns the run's `messages` slice —
  correlated via the user message's `provenance.trace_id` — so run history
  can show the full interaction stream.
- `AgentMessageSerializer` shared by Interactions and run detail.

### Backend — new tools

- `browse_page` (enabled by the builder's **Playwright** tool): fetches a
  page restricted to trusted hosts (`docs.activeagents.ai`), strips HTML to
  readable text. SSRF-guarded via the existing `fetch_url` machinery.
- `call_agent` (new **agents** tool in `Agent::AVAILABLE_TOOLS`): delegates
  a message to another same-workspace agent (MCP-equivalent scoping) via
  synchronous `test_execute`; the sub-run is a real `AgentRun` with its own
  trace. Thread-local depth guard (max 2) prevents recursion.

### Frontend

- **`InteractionStream`** — shared component (Interactions view + agent
  Conversation History run detail): every message row is expandable — tool
  chips (`⚙ calculate · 2ms`), pretty-printed arguments/results, call ids,
  checksums, full timestamps.
- **Traces waterfall** — every span row shows `duration · % of trace` and
  expands on click to attributes/tokens/span id.
- **Time breakdown — generation vs tools** (per expanded trace): stacked
  bar + legend splitting wall clock into pure generation (llm span minus
  tool time, since tools run inside the provider loop), per-tool durations,
  and overhead.
- **Spans view mode** (Traces): "Slowest operations" — span durations
  aggregated across the filtered window, ranked by total time
  (count / avg / max / Σ per operation).

## Demo (all local: OrbStack + native Ollama qwen3:8b)

1. "Local Qwen Assistant" run: `calculate` → 2.68ms, `save_memory` → 97ms,
   `llm.generate` → 37.97s; all visible in waterfall + breakdown.
2. "Docs Navigator" agent (tools: playwright + agents), one MCP run:
   - `browse_page` read https://docs.activeagents.ai (259ms · 0.36%)
   - `call_agent` → local-qwen-assistant recalled `41679` from memory
     (38.66s · 54.2%; the sub-agent's own trace appears separately)
   - Breakdown: generation 32.35s (45.4%) vs tools 38.92s (54.6%).

## Streaming run progress (added later same day)

- `AgentRun#append_event` — progress events in the `logs` jsonb, paired by
  `eid` (`started` → `done`/`error`), written with `update_column` from the
  execution thread.
- `AgentExecutionService` emits events around the LLM call and every
  tool/`call_agent` execution (label, args detail, duration, error).
- `AgentRunner` now POSTs `/api/agents/:id/execute` (async job — dev uses
  the in-process `:async` adapter) and polls `/api/runs/:id` every 1.2s,
  rendering a live activity feed: `∿ ollama/qwen3:8b generating running…`,
  `[] browse_page ✓ 153ms`, `@ call_agent → local-qwen-assistant ✓ 9.7s`.
  The feed persists after completion as a run timeline. MCP-initiated runs
  record the same events server-side.
- True token/thinking streaming needs provider streaming + SSE — follow-up.

## Bug found via user report: editor wiped agent config

"Docs Navigator stopped following instructions": the agents-list JSON omits
detail fields (`instructions`, `tools`), and `Dashboard#navigateTo` passed
that shallow object straight into `AgentEditor`, which initialized its form
empty — the next save PATCHed `instructions`/`tools` with wrong/empty
values (confirmed in request logs; tools were wiped to `[]`). Fixed by
refetching the full agent whenever a detail view receives a shallow object
(`agent.instructions === undefined`). Docs Navigator's config was restored.

## Notes / follow-ups

- Cross-file test contamination pre-exists (`Email address has already been
  taken` when running several controller test files together); changed
  files pass individually.
- Builder design view still needs work (hardcoded Ollama model list, no
  "agents"-tool description in wizard) — next work item.
- Sub-agent traces are separate top-level traces; linking parent/child
  traces (`tool.call_agent` span → sub trace) would make the dig-in
  seamless.
