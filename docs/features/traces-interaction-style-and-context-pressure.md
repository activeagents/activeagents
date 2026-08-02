# Traces read like Interactions + context pressure

**Branch:** `feat/traces-interaction-style` · **Date:** 2026-08-02

One conversation renderer everywhere, tool calls that read as in/out pairs,
a context-pressure meter on every trace, and trace refs that deep-link.
Design direction comes from the Active Agent design system package installed
at `.claude/skills/activeagent-design/` (markdown committed; prototype
HTML/JS/CSS payloads gitignored).

## What changed

### Shared message stream (`InteractionStream.jsx`)
- Long tool results and system/developer instructions collapse to a
  tweet-length (280-char) preview; expanding shows the full text. Previously
  non-JSON tool results and instructions rendered fully inline (walls of
  text).
- Tool rows always read as a compact `in:` / `out:` summary; the expanded
  panel orders **Arguments → Result → Tool definition**.
- A tool call's two message rows split the space: the assistant row (the
  call) shows `⚙ name in: {args}`, the paired tool row (matched by
  `tool_call_id`) shows only the output. Handles both provider-style
  `tool_calls` arrays and the trace serializer's bare arguments object.
- Messages without timestamps (span-derived) no longer render "Invalid
  Date".

### Traces view (`TracesView.jsx`)
- Span detail panels lift content attributes (instructions, prompt
  messages, tool args/results, completions — both ActiveAgent and RubyLLM
  attribute shapes) into `InteractionStream` messages instead of raw
  `key: value` dumps; non-content attributes keep the mono rows.
- Every span row carries one-line `input:` / `output:` previews
  (`agent.prompt` → last user message, `llm.generate` → completion,
  `tool.*` → args/result), normalizing all span types.
- `prompt.input.tools` renders as a **ToolRoster** (`ToolRoster.jsx`):
  clickable chips per tool opening description, params, and provenance
  (explicit `mcp_server`/`gem` fields, `mcp__server__tool` naming, else
  agent-defined). Tool schemas travel with the trace so any expanded tool
  message shows its definition.
- **Context pressure** (`ContextMeter.jsx`, from the design-system spec):
  compact segmented bar + % on every trace row, full breakdown panel in the
  expanded trace (messages / tool results / instructions / tool schemas /
  MCP schemas / generated output / free space) against the model's context
  window. Real provider token totals; per-segment split estimated at
  ~4 chars/token until telemetry records per-segment counts. Thresholds:
  ≥75% warning, ≥90% error + "compaction imminent" line.
- Deep links: `/dashboard/traces?trace=<id>` (record id, trace_id, or
  8-char short form) auto-selects, expands, and scrolls to the trace,
  fetching it directly when outside the loaded time window (pinned to the
  top of the list).

### Elsewhere
- `trace:xxxxxxxx` refs in Interactions, Conversation History, and Agent
  Runner are links to the trace deep link.
- Sidebar: Interactions moved back under Observability (top-level).
- `Api::TracesController#show` accepts trace_id / short-id prefix, not
  just the record id.

## Domain model (from Justin, guiding future work)
- **Interaction** = a set of traces (each trace one turn/step).
- **Instance** = the configuration that actually ran: model version ×
  instructions/system prompt × params. Agents accumulate instances as
  those evolve; telemetry grouping/comparison should key on instances
  (cf. Agent Report's instructions × model cohorts).
- Next in this direction (design handoff): interaction scrubber with
  live-recomputed context, and "reload into instance" replay with
  human/LLM-judge comparison.

## Notes
- Fleet cards with donut/activity rings from the design kit are **not** the
  direction — agent cards should become eval-based scorecards (system-level
  + functional) later.
- The `localhost:3000` dev app runs from the separate
  `~/GitHub/activeagents-telemetry` clone (OrbStack `activeagents-telemetry-web-1`
  mounts it); it now tracks this branch instead of receiving hand-copied
  files.
