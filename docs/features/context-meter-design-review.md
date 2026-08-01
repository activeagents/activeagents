# Design Review: Per-Agent Observability Handoff (ContextMeter, Interactions, Reload)

**Date:** 2026-08-01 · **Status:** Review — no code changes
**Reviewing:** `ActiveAgents_design_system.zip` → `design_handoff_agent_observability/`

The handoff adds five observability tabs to the agent detail page, a new
`ContextMeter` component for context-window pressure, a scrubable interaction
transcript whose context state recomputes live, and a "Reload into Instance"
modal for A/B replay.

This review checks the design against what the repo can actually supply today.

---

## Summary

The context-pressure thinking is good and the tool-call in/out split is the
single most valuable idea in the package. Three things block it:

1. The meter derives a context total that will visibly disagree with
   `AgentGeneration#input_tokens` — the provider-reported ground truth — on the
   same screen.
2. Its red-state copy promises compaction. This platform has no compaction.
3. Nothing in the schema stores per-message tokens, and there is no tokenizer
   in the repo, so most of the numbers the design asserts cannot be computed.

None are fatal; all change what ships first. The handoff's own build order
(`ContextMeter` → Traces → Interactions → Reload) is right, but it is missing a
step 0.

---

## 1. Context memory pressure — `ContextMeter`

### What's right

- **Tool-call in/out split.** "A 300-token call returning 28k is the single most
  common way a context window fills up" is correct, and it is the number no
  other view in this app surfaces. `agent_messages` already stores both sides
  (`tool_arguments`, `tool_result` — `db/schema.rb:171,174`), so the data model
  supports it even though the token counts don't exist yet.
- **Blue-only segment ramp.** Reserving warm colors for thresholds is sound and
  enforceable, and the `color-mix` toward `--color-card` does resolve in both
  themes.
- **`compact` in list rows.** This is what turns a per-row scan into triage.
- **Derived, never stored.** Correct call — it is what makes the meter track the
  scrubber for free.

### P1 — Two different "context" numbers on the same screen

In the Traces prototype, `tr_9f2e41` renders a `ContextMeter` totalling 68,520
("Context at time of call") and, 14px below it, a meta line reading `in 41.7k`.
Both claim to be the context for the same call. The meter's number is the sum of
estimated segments; `in` is `AgentGeneration#input_tokens` — what the provider
actually charged for the window.

`input_tokens` **is** window occupancy at call time. It should be the meter's
`used`, with the segments normalized against it for attribution, and any
shortfall shown as an explicit `unattributed` segment rather than silently
absorbed. A meter that disagrees with the number printed under it loses its
authority the first time an operator notices.

### P2 — "compaction imminent" describes behavior this product does not have

> `[!] compaction imminent — next turn may drop the oldest messages`

There is no compaction, trimming, eviction, or summarization anywhere in `app/`
or `lib/`. Nothing drops the oldest messages. What actually happens at the limit
is a provider error or a truncated response — which `AgentGeneration#truncated?`
(`finish_reason == "length"`) already models, and which the design already
surfaces in the Traces meta line.

The handoff declares copy final. This line should not be. Either:

- reword to what happens — e.g. `[!] window nearly full — the next turn may
  truncate (finish_reason: length)`; or
- ship context compaction and keep the copy.

Shipping the copy without the behavior trains operators to expect a safety net
that isn't there.

### P3 — The alarm recolors the wrong segment

The rule is that at ≥75% the `messages` segment (and its legend swatch) recolors
amber/red. But the design's own thesis is that **tool results** fill windows —
its mock has a single `export_locales` call returning 28,140 tokens. When the
window fills from tool results, the alarm paints `messages` and points at the
wrong culprit.

Worse, in the prototype's own `tr_6c2a90` the message segment is zero, so it is
filtered out entirely — the container border turns red and there is no segment
for the alarm to paint.

Fix: tone the largest contributing segment, or tone the whole bar and mark the
culprit with an ASCII glyph (`app/javascript/utils/designTokens.js` already
ships that vocabulary).

### P4 — Over-limit is invisible

`pct = Math.min(1, total / limit)` means 164% and 100% render identically.
Exceeding the window is a categorically different event from approaching it, and
it is the one that correlates with `finish_reason: length`. It deserves its own
state: bar full, value reading `210k / 128k (164%)` in error tone.

Related: bar segments have no `flexShrink: 0`, so an over-limit context gets
squeezed by flexbox and silently misreports proportions.

### P5 — The cached prefix is the answer to "what do I evict", and it's a footnote

`AgentGeneration#cached_tokens` is already recorded, and `cache_hit?` already
exists. Everything inside the cached prefix is cheap to keep and **expensive to
break** — trimming into it invalidates the cache and makes the next call cost
more, not less.

Rendering the cached prefix as a hatched region on the left of the bar with a
boundary tick would let the meter say something a coding agent's `/context`
readout cannot: *trim to the right of this line*. That is the highest-leverage
addition available from data the repo already has, and it turns the component
from a gauge into a decision tool.

### P6 — `limit` sourcing will silently under-report

The handoff says to reuse the `CONTEXT_WINDOWS` map in
`app/javascript/components/dashboard/BenchmarkView.jsx:1596`, keyed by
`AgentGeneration#model`. That map is keyed by display names — `'GPT-4'`,
`'Claude-3.5'`, `'Gemini-Pro'` — while `AgentGeneration#model` holds provider ids
like `gpt-4o-mini`, `claude-sonnet-4-5`, `qwen3:8b`. Every lookup misses and
falls through to the 200,000 default, so a 128k model reads 35% low and never
trips a threshold.

Put the window table next to `ModelPricing::PRICES` (`app/models/model_pricing.rb`),
which already does regex matching over real model ids, is maintained for exactly
this reason, and has a documented fallback story.

### The blocking gap: there are no per-message token counts

This is where the design outruns the schema:

- `agent_messages` (`db/schema.rb:162`) has no token columns.
- `agent_generations` has aggregates only, with no linkage to a message row.
- There is no tokenizer in the repo — no `tiktoken`, no estimator, nothing.

So today none of these can be computed: per-tool `in`/`out`, the per-row `+9.3k`
delta, the scrub-derived recompute, or the growth curve.

Three approaches, ranked:

1. **Generation deltas — free, exact, ship first.** Between consecutive
   generations, `input_tokens[n] − (input_tokens[n−1] + output_tokens[n−1])` is
   exactly the tokens added by the user turn plus tool results in between. It is
   provider-reported, needs no tokenizer and no migration, and it yields a true
   growth curve and a true "this turn ate 31k" number — at generation
   granularity rather than per message.
2. **Per-message counts at write time.** Add `input_tokens`/`output_tokens` to
   `agent_messages`, populated in `AgentContext#add_tool_message` /
   `add_assistant_message`. This is what unlocks the per-tool split, so it is
   worth doing — but it needs a tokenizer (tiktoken covers OpenAI; Anthropic and
   Ollama need approximation), it is only correct for the model that ran, and it
   must be labeled as estimated.
3. **`chars / 4` in the client.** Cheapest, and the worst option for a component
   whose entire job is a threshold alarm. Do not anchor a red state to a guess.

Recommended: (1) for the totals the meter asserts, (2) for the breakdown,
reconciled so segments sum to the measured `input_tokens`.

The static overhead segments are cheaper than the handoff implies — all four
sources are already reachable server-side: `AgentContext#instructions` is
persisted and kept current by `AgentExecutionService#sync_context_instructions`,
`AgentToolbox.definitions_for(agent.tools)` yields the tool schemas,
`agent.mcp_servers` the MCP set, and `AgentMemory#to_prompt` the memory block.
Only the token counting is missing.

---

## 2. Interactions tab

- **Scrub-derived context is the best idea in the handoff.** Note the repo
  already has a working transport — `SessionReplayView.jsx` (play/pause, speed,
  timeline scrub) for browser session recordings. Lift it rather than writing a
  second scrubber.
- **Overlap with shipped views.** This lands on top of `AgentInteractions.jsx`
  and `InteractionsView.jsx`, both reworked in HEAD (`90da514`). Decide whether
  this is a new tab or a rework of those, before building a third interaction
  list.
- **Normalized `at` positions are mock-shaped.** Events carry `at ∈ [0,1]`. Real
  interactions have `created_at` timestamps with long idle gaps, so a wall-clock
  scrubber spends most of its track in dead air. Scrub on event index (a step
  slider, one detent per message) and *display* wall time.
- **Sentiment badges have no backing data.** There is no sentiment, feedback,
  CSAT, or vote table anywhere in the schema. The same is true of the entire
  Feedback tab, which the handoff waves through as "unchanged from the previous
  handoff". Those need a table before they need pixels — and the handoff's
  "backend work needed" callouts should say so.

---

## 3. Reload into Instance

**This is more valuable than the handoff realizes.** It is the missing Phase 3
from `docs/features/model-comparison-evaluations-design.md`, which states
outright that "the one-click replay orchestration remains future work", and
`AgentExecutionService` already honors per-run `model_override` /
`provider_override` via `input_params` (`app/services/agent_execution_service.rb:118-130`).

But do not build a parallel replay-and-score system. `EvaluationRunnerService`
already scores per-model cohorts through `Evaluation#compare_models`, and today
it fails with *"No generations recorded under X — run the agent under those
models first"*. The Reload modal is precisely the missing producer for those
cohorts. The cheap shape is:

> enqueue N runs with per-variant overrides → they land as ordinary
> `AgentGeneration` rows → the existing evaluation machinery scores them.

That reuses the scorecards, the judge, and the verdict rendering, and avoids a
bespoke replay-results table entirely.

Two smaller notes:

- **"Instance" collides.** There is no `Instance` record, and the word is already
  taken in this codebase by `SandboxInstanceTier` / `InstanceTierSelector` /
  `instance_tiers_controller`. `AgentVersion` + model override is the existing
  vocabulary; "configuration" would also read cleanly.
- **The variant grid varies too much at once.** A column can change model *and*
  instructions *and* temperature *and* tools *and* MCP servers simultaneously.
  For eyeballing side by side that is fine; for the LLM-judge path the verdict
  becomes uninterpretable — you learn that B won, not why. Constrain judge mode
  to one varying factor, or surface the confound in the verdict.

The default — "replays run against recorded tool results, so results are
comparable" — is the right one, and the note explaining it is well placed.

---

## 4. Design-system fit

**The handoff's central premise about tokens is incorrect.** It says "Do not
hardcode hex values — these already exist in the app's token layer." They do not.
`--color-accent-ui`, `--color-token-in`, `--color-token-out`, `--span-tool`, and
`--color-text-cell` appear nowhere in `app/`. The dashboard is Tailwind v4
utilities plus `app/javascript/utils/designTokens.js` (JS objects: `COLORS`,
`TYPOGRAPHY`, `getThemeColors(darkMode)`), and dark mode runs through
`ThemeContext`, not a `.theme-dark` CSS scope.

So step 0 of "recreate pixel-accurately using the app's existing component
library" is: there is no such library and no token layer to bind to. Either port
`design/tokens/*.css` into `application.tailwind.css` as `@theme` variables
first, or restate the spec in the app's existing idiom. What must not happen is
~1,600 lines of inline-style prototype getting pasted in — that is how the app
ends up with a third styling system.

**There are already three conflicting in/out token color conventions:**

| Where | `in` | `out` |
| --- | --- | --- |
| `landing/base.css:1396` (used by `TracesView.jsx:1028`) | `#569cd6` | `#4ec9b0` |
| `InteractionsView.jsx:254-255` | `text-blue-500` | `text-green-600` |
| This handoff | `#2563eb` | `#7c3aed` |

Adopting the handoff's pair is fine — it is the only one that distinguishes
output from tool-green — but it needs to be a deliberate migration of all three,
not a fourth convention added by one new component.

**Other notes:**

- `--color-accent-ui: #ef4444` vs `DESIGN_SPEC.md`'s `--color-accent: #FA343B`.
  The product/marketing split is reasonable and is already implicitly true
  (`DESIGN_SPEC.md` maps the dashboard accent to `red-500`, which *is* `#ef4444`).
  Ratify it in `DESIGN_SPEC.md` so the two-red system is documented rather than
  discovered.
- **"No emoji" is a good rule that conflicts with shipped code.**
  `InteractionsView.jsx:249` renders 🧠 for thinking tokens. The handoff's `[~]`
  is better and matches the stated ASCII/TUI philosophy in `designTokens.js`.
  Worth adopting repo-wide, not just in new components.
- **Accessibility gaps, all cheap to fix.** The `ContextMeter` header is a
  click-handled `div` — no `role`, no `tabIndex`, no `aria-expanded`, no keyboard
  handler. The scrubber track is click-only with no `role="slider"` and no
  arrow-key seek. Threshold state is encoded in color alone, with a native
  `title` as the only text alternative. The ASCII glyph vocabulary makes a
  non-color encoding on-brand rather than a compromise.
- `compact` hardcodes `width: 132` and relies on callers overriding through
  `style` (the rail passes `width: '100%'`); the `.d.ts` doesn't mention this.
- `ContextMeter` is duplicated across `components/data/ContextMeter.jsx` and
  `ui_kits/dashboard/AgentInstance.jsx`. The handoff acknowledges this and is
  right that the app should have exactly one.

---

## Recommended sequencing

Broadly the handoff's order, with the step it omits:

0. **Token-layer decision** (port CSS vars vs. restate in Tailwind) and
   **generation-delta token math** — no migration, no tokenizer, real numbers.
1. **`ContextMeter`** anchored to `input_tokens`, with honest threshold copy and
   the context-window map on `ModelPricing`.
2. **Traces additions** — smallest change, immediate value, and the compact meter
   in collapsed rows is the highest ratio of insight to work in the package.
3. **Per-message token columns** → the tool in/out split and the scrubber.
4. **Reload modal** as a cohort producer for `EvaluationRunnerService`, not a new
   replay subsystem.

Deferred until they have backing tables: interaction sentiment, the Feedback tab.
