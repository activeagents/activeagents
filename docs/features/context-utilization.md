# Context Utilization (Memory Pressure)

**Date:** 2026-08-01 · **Status:** ✅ Implemented

Context-window pressure per interaction and at time of trace: how full the
window is, what is taking up the space, how it got there turn by turn, and how
many turns of headroom are left.

Follows from `docs/features/context-meter-design-review.md` — the design review
of the observability handoff. Everything that review flagged as a blocker is
addressed here.

## The measured/estimated split

The headline number is always measured. A provider reports `input_tokens` for
every generation, and that is exactly what occupied the window at that call. So:

| Quantity | How it is obtained |
| --- | --- |
| Occupancy at a call | `AgentGeneration#input_tokens` — exact |
| Occupancy after a turn | `input_tokens + output_tokens` (what the next call inherits) |
| Tokens a turn added | `input_tokens[n] - (input_tokens[n-1] + output_tokens[n-1])` |
| Per-source breakdown | Estimated by `TokenEstimator`, then reconciled |

The delta identity is the important one: it is precisely the user message plus
tool results that landed between two calls, and it needs no tokenizer. No
tokenizer ships with the app, and the correct BPE vocabulary differs per
provider, so nothing depends on one.

The breakdown has no measured equivalent — nothing persists per-message token
counts. It is estimated and then **reconciled against the measured total**:
whatever the estimate cannot account for is surfaced as an explicit
`unattributed` segment rather than silently absorbed. Segments always sum to
`used`, so the bar adds up to the number printed above it, and every estimated
segment carries `estimated: true` (rendered with a `~` marker).

When the estimate *exceeds* the measured total it is scaled down proportionally
instead of overflowing.

## Thresholds

`ok` → `warning` (≥75%) → `critical` (≥90%) → `over` (>100%).

`over` is a distinct state, not a clamp: exceeding the window is a different
event from approaching it, and it is the one that correlates with
`finish_reason: "length"`.

**There is no compaction on this platform.** Nothing drops the oldest messages;
the window is simply exceeded and the provider truncates. The threshold copy
says that:

```
[!] window nearly full — the next turn may truncate (finish_reason: length)
```

If context compaction is ever implemented, this copy is the thing to revisit.

## Components

`ModelContextWindow` resolves the denominator: RubyLLM's registry first (same
pattern as `ModelPricing`), then a static regex table for aliases and
self-hosted models, then a 128k default. `known?` reports whether the window was
resolved or assumed, and the UI marks an assumed denominator with `[?]` rather
than presenting a guess as fact.

`TokenEstimator` approximates prose at 3.6 chars/token and JSON at 2.8, and
splits a tool message into the arguments the model emitted and the result that
came back — both occupy the window.

`ContextUtilization` assembles the payload:

- `for_context(context)` — meter, `turns[]`, `peak`, `projection`, truncation count
- `for_generation(generation)` — context at time of call, plus the turns leading
  up to it
- `summaries_for(contexts)` — one query for a whole list, so rows get pressure
  without an N+1

## API

- `GET /api/interactions` — each row carries a compact `context`
- `GET /api/interactions/:id` — full `context` with `segments`, `turns`, `projection`
- `GET /api/traces` — each row carries `context` at time of call (measured only)
- `GET /api/traces/:id` — adds the per-source breakdown and turn history

The breakdown costs a messages load, so it is built only for the drilled-in
record. `TracesView` fetches the detail on expand and falls back to the summary
payload.

## Visualizations

| Component | Answers |
| --- | --- |
| `ContextMeter` | How full is it, and what is filling it? |
| `ContextMeter compact` | Which row is about to run out? (list scanning) |
| `ContextSourceShare` | What is worth trimming, relative to the rest? |
| `ContextGrowthChart` | How did it get here — a ramp or a step? |
| `ContextTurnDeltas` | Which turn ate the window? |
| `ContextHeadroom` | How many more turns fit? |

`ContextUtilizationPanel` composes them; `dense` drops the share strip and
shortens the turn list for embedding in a trace row.

Three details that are semantics rather than decoration:

- **The alarm recolors the largest segment**, not a fixed one. Recoloring
  `messages` would blame it for a window filled by tool results, which is the
  common case.
- **The cached prefix is drawn on the bar**, not footnoted. Everything left of
  the boundary is cache-warm — cheap to keep and expensive to break, because
  trimming into it invalidates the prefix and makes the next call cost *more*.
  That boundary is the actual answer to "what do I evict".
- **Headroom is expressed in turns**, not percent. "68% full" is a fact;
  "~4 turns left" is the number that changes what an operator does.

## Conventions

- Blue (`#2563eb`) is context and input; purple (`#7c3aed`) is output. Amber and
  red are reserved for thresholds — the segment ramp is blue steps toward the
  card background so the alarm states keep reading as alarms.
- Threshold state is never color-only: `[!]` / `[!!]` markers accompany it,
  matching the ASCII vocabulary in `utils/designTokens.js`.
- Hatching marks a region as "not a source" (unattributed) or "cache-warm",
  without adding a hue.
- No emoji. `[=]` cached, `[~]` thinking, `[?]` assumed window.
- Token counts are always abbreviated (`412.4k`, `1.2M`), never raw integers.
- The meter's disclosure is a real `<button>` with `aria-expanded`; bars and
  charts carry `role="img"` with a spoken summary.

## Known limits

- The breakdown is an estimate. On streams whose recorded token counts diverge
  from the persisted message text, `unattributed` dominates — which is the
  honest outcome, and the reason the segment exists.
- Per-source attribution would become measured if `agent_messages` gained
  `input_tokens`/`output_tokens` columns populated at write time. The payload
  shape already accommodates that: drop the `estimated` flag and
  `unattributed` shrinks to zero.
- Anthropic's 1M-context beta header is not modeled; a run using it reads
  pessimistically rather than silently over-full.
