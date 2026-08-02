# Handoff: Per-Agent Observability (Context, Interactions, Instance Reload)

## Overview

Adds per-agent observability to the Active Agent dashboard: an agent's detail
page gains five observability tabs — **Traces, Metrics, Interactions, Evals,
Feedback** — plus a new `ContextMeter` component that shows context-window state
the way engineers expect from a coding agent's `/context` readout.

The centerpiece is **Interactions**: an interaction transcript that can be
scrubbed, whose context state recomputes live as you scrub, and which can be
**reloaded into a new instance** (different model / instructions / tools / MCP
servers) for human or LLM-judge comparison.

## About the design files

The files in `design/` are **design references created in HTML** — prototypes
showing intended look and behavior, not production code to copy. The task is to
**recreate them inside `activeagents/activeagents`** using its existing
environment: Rails views + the React components under
`app/javascript/components/dashboard/`. Reuse that app's existing conventions
(component file layout, fetch/serializer patterns, Tailwind or CSS-var usage)
rather than porting these files verbatim.

The prototypes use plain React 18 via Babel-in-browser and a `window.AAKit`
namespace purely so they run from `file://`. None of that should survive into
the app.

## Fidelity

**High fidelity.** Colors, typography, spacing, and interaction behavior are
final and match the design system in `design/tokens/`. Recreate pixel-accurately
using the app's existing component library. Copy is final too — use it verbatim.

## Domain model (already in the repo — do not invent new names)

| Concept | Repo model | Meaning |
| --- | --- | --- |
| **Instance** | `Agent` + `model_config` + instructions + tool/MCP set | The configured agent that runs |
| **Interaction** | `AgentContext` | One agent's conversation stream (`agent_name` + `action_name`) |
| **Messages** | `AgentMessage` | roles `user` / `assistant` / `system` / `tool` |
| **Generation** | `AgentGeneration` | One LLM call: model, provider, finish_reason, in/out/cached/reasoning tokens, tool_calls, duration, trace_id |
| **Trace** | `TelemetryTrace` | Joined to generations via `trace_id` |

The read API already exists: `Api::InteractionsController#index` / `#show`.
`#show` returns `instructions`, `messages`, and `generations` — enough for the
transcript. The context breakdown needs additional fields (see below).

---

## Screens

### 1. Agent Detail — tab bar

**File:** `design/ui_kits/dashboard/AgentDetailScreen.jsx`

Two tab groups on one row, separated by a 1px × 18px vertical rule
(`--color-border-strong`), 20px gap:

- **Config group:** Configuration, Instructions, Tools, Versions, Code
- **Observability group:** Traces, Metrics, Interactions, Evals, Feedback

Both groups drive the same `tab` state. The row has
`border-bottom: 1px solid var(--color-border)`; the individual `Tabs` components
have their own bottom border removed.

Header above it: back arrow (`<-`, mono 13px, `--color-text-secondary`), 44px
agent glyph, agent name (20px/700), status `Badge`, description (13px,
`--color-text-secondary`), then right-aligned `Duplicate` (secondary) and
`Run Agent` (primary) buttons. Page padding 24px, section gap 20px.

---

### 2. ContextMeter (new component)

**Files:** `design/components/data/ContextMeter.jsx`, `.d.ts`, `.prompt.md`

The context window as a segmented bar plus an expandable token breakdown.

**Props**

```ts
used?: number           // defaults to sum of segments
limit?: number          // model context window, default 200000
segments?: { key, label, tokens, color? }[]
cached?: number         // AgentGeneration#cached_tokens — footnote
thinking?: number       // AgentGeneration#reasoning_tokens — footnote
compact?: boolean       // one-line: 132px bar + percentage
defaultOpen?: boolean
collapsible?: boolean   // default true
label?: string          // default "Context window"
compactAt?: number      // default 0.9
```

**Segment order and colors** (largest source first; each color is
`color-mix(in oklch, var(--color-token-in) N%, var(--color-card))`). The ramp is
**blue on purpose** — `--color-warning` and `--color-error` must be the only warm
colors in this component or the threshold states stop reading as alarms. Do not
rebuild it on `--color-accent-ui`:

| key | label | N% | resolved (light) |
| --- | --- | --- | --- |
| `messages` | Messages | 100 | `#2563eb` |
| `tool_results` | Tool results | 74 | mix |
| `instructions` | Instructions | 54 | mix |
| `tool_schemas` | Tool schemas | 38 | mix |
| `mcp_schemas` | MCP tool schemas | 24 | mix |
| `memory` | Memory files | 14 | mix |
| `__free` | Free space | — | `var(--color-muted)` |

Zero-token segments are filtered out. Callers pass only `{ key, label, tokens }`
— the component resolves each color from `CONTEXT_SEGMENTS` by `key`, so a
missing `color` must never fall through to `undefined`. Free space is appended
only in the expanded breakdown, and its swatch gets a
`1px solid var(--color-border-strong)` outline (it is otherwise invisible on
white).

**Expanded layout**

- Container: `--color-card`, `1px solid --color-border`, radius 12, padding
  12px 14px.
- Header row: mono 11px/600, `letter-spacing: 0.06em`, uppercase,
  `--color-text-secondary` on the left; right side mono 12px/600
  `412.4k / 128k (41%)`; chevron `>` (mono 11px, `--color-text-muted`) rotates
  90° on open, `transform 0.15s ease`.
- Bar: 9px tall (6px when `compact`), `border-radius: 999px`, background
  `--color-muted`, segments butted flush with width `tokens / limit * 100%`.
  Each segment has `title="{label} · {tokens}"`.
- Breakdown rows, 5px gap: 9px swatch (radius 2) · label (13px,
  `--color-text-cell`) · tokens (mono 12px, `--color-text-secondary`, 56px right)
  · percent to one decimal (mono 12px, `--color-text-muted`, 46px right).
- Footnotes, separated by a `--color-border-light` top border, mono 11px:
  `[=] cached prefix 38.4k` where `[=]` is `--color-token-in`; `[~] thinking 2.4k`
  where `[~]` is `--color-token-out`.

**Thresholds** (semantic, not decorative)

- `>= 0.75` — the header value, percentage, and the `messages` segment turn
  `--color-warning`; container border follows. **The `messages` legend swatch
  recolors with it** — the legend must always key the bar.
- `>= compactAt` (0.9) — the same turn `--color-error`, and a mono 11px line
  appears below the bar:
  `[!] compaction imminent — next turn may drop the oldest messages`

**Number formatting** — never show raw integers: `≥1e6 → "1.2M"` (trailing
`.0` stripped), `≥1e3 → "412.4k"`, else the integer.

**Compact variant** — 132px wide flex row: bar (flex 1) + percentage
(mono 11px, threshold-colored, `white-space: nowrap`). No breakdown, no
container.

**Backend work needed.** `Api::InteractionsController` currently serializes only
`input`/`output`/`total`/`cached`/`thinking`. Add a per-context breakdown:
`system_prompt_tokens`, `instruction_tokens`, `tool_schema_tokens`,
`mcp_schema_tokens`, `memory_tokens`, and message vs tool-result token sums.
`BenchmarkView.jsx` already computes `system_prompt_tokens` /
`tool_schema_tokens` and holds a `CONTEXT_WINDOWS` map — reuse both; the
`limit` prop comes from that map keyed by `AgentGeneration#model`.

---

### 3. Interactions tab

**File:** `design/ui_kits/dashboard/AgentObservability.jsx` →
`AgentObs.Interactions`

Two columns: `grid-template-columns: 280px 1fr`, 16px gap, `align-items: start`.

**Left rail** — card, radius 12, `overflow: hidden`. Header row (12px 14px,
bottom border `--color-border-light`): mono uppercase micro-label
"INTERACTIONS" + right-aligned count. Each row (padding 10px 14px, top border
between rows, `cursor: pointer`):

- Line 1: interaction id (mono 12px/600) + sentiment `Badge`
  (positive→success, neutral→neutral, negative→error).
- Line 2: `#action · user` (mono 11px, `--color-text-muted`).
- Line 3: `7 messages · 4 generations · 14m ago` (11px, `--color-text-muted`).
- Line 4: full-width `<ContextMeter compact>`.
- Selected: `background: var(--color-muted)` and
  `border-left: 2px solid var(--color-accent-ui)`. Unselected rows carry
  `border-left: 2px solid transparent` so text does not shift.

Selecting a row resets the scrubber to the end (`pos = 1`).

**Right column** — 12px gap, three stacked blocks:

**(a) Instance bar** (`design/ui_kits/dashboard/AgentInstance.jsx` →
`InstanceBar`). Card, padding 10px 14px, wrapping flex, 8px gap. Mono uppercase
"INSTANCE" label, then chips: `model openai/gpt-4o-mini`, `temp 0.7`,
`instructions v7` (value in `--color-accent-ui`), `tools 3`, `mcp 2`,
`ctx 128k`. Chip = `--color-muted` background, radius 6, padding 3px 8px,
mono 11px, key in `--color-text-muted`, value in `--color-text-primary` at 600.
Right-aligned: `Open Trace` (secondary sm), `Reload into Instance` (primary sm).

**(b) ContextMeter**, `defaultOpen`, label `Context · ctx_a41f`.
**Its values are derived from the scrubber position** — this is the important
behavior. Static instance overhead (instructions, tool schemas, MCP schemas,
memory) is always counted; `messages` sums the tokens of replayed events whose
role is not `tool`, `tool_results` sums those whose role is `tool` (arguments
**and** results — both occupy the window). Scrubbing
back shrinks the context; scrubbing to the end shows the final state.

**(c) Transcript card.** Header (padding 10px 16px): mono uppercase
"TRANSCRIPT", then `user · duration` (mono 11px), right-aligned
`3 / 7 messages`. Body padding 12px 16px, 12px gap, `min-height: 200px`. Each
message row:

- Role glyph, mono 12px/600, 20px wide, centered, `margin-top: 2px`:
  `@` user (`--color-info`), `>` assistant (`--color-accent-ui`),
  `[]` tool (`--span-tool`). **No emoji anywhere.**
- Meta line: role uppercase (mono 10px/600, `letter-spacing: 0.04em`,
  `--color-text-muted`), then, in order and only when present: tool name
  (mono 11px/600, `--span-tool`), model name, `cache hit` info `Badge`,
  **token split**, duration. The meta line wraps (`flex-wrap: wrap`).
- **Token split** (mono 10px) — tool rows show
  `in 180 · out 3.1k` where `in` is `--color-token-in` and `out` is
  `--color-token-out`; `in` is the arguments the model emitted, `out` is the
  result that came back. Assistant rows show `out 4.8k` only — their input is
  the whole context, so repeating it would be noise.
- Body: 13px / 19px line-height. Tool rows use `--font-mono` and
  `--color-text-muted`; user and assistant rows use `--font-text` and
  `--color-text-cell`.
- Right gutter: token delta `+9.3k` (mono 11px) — for tool rows this is
  `in + out`, the true context cost of the call. Deltas over 15k render in
  `--color-warning-text` — this is how an operator spots the turn that ate the
  window.

When scrubbed short of the end, append a mono 11px muted line:
`… scrub forward to replay the rest`.

**Scrubber footer** (top border, padding 10px 16px 12px):

- Micro-label "CONTEXT GROWTH" + `41.7k now · 118.9k at end` (mono 10px).
- Cumulative context curve: `<svg viewBox="0 0 100 28" preserveAspectRatio="none">`,
  full width, 28px tall. `polyline` in `--color-token-in`, `stroke-width: 1.5`,
  `vector-effect: non-scaling-stroke`, `fill: none`. Y is
  `26 - min(1, tokens/limit) * 24`. A dashed (`2 2`) vertical playhead in
  `--color-text-muted` sits at the scrub position.
- Transport row: play/restart button (32×28, radius 8, `--color-accent-ui`,
  white mono 12px label `|>` / `<<`) then the track: 6px `--color-muted` rail,
  `--color-accent-ui` fill to position, one 3×14px marker per event colored by
  role, and a 12px white knob with a 2px accent ring and
  `0 1px 3px rgba(0,0,0,0.25)`. Clicking anywhere on the track seeks
  (`(clientX - rect.left) / rect.width`). Right: `73s / 192s` (mono 11px, 72px,
  right-aligned).

---

### 4. Reload into Instance (modal)

**File:** `design/ui_kits/dashboard/AgentInstance.jsx` → `ReloadPanel`

The evaluation workflow: take a real recorded interaction and re-run it against
different instance configurations.

Overlay `rgba(0,0,0,0.45)` full-screen, 24px padding, click-outside closes
(inner panel stops propagation). Panel: `min(940px, 100%)`,
`max-height: 100%`, `overflow-y: auto`, `--color-background-page`,
`1px solid --color-border-strong`, radius 16,
`box-shadow: 0 24px 60px rgba(0,0,0,0.35)`.

**Header** (padding 16px 20px, bottom border): title "Reload interaction into an
instance" (16px/700), subtitle `ctx_a41f · 7 messages · 4 generations`
(mono 12px). Close control is a mono `[x]`, not an icon.

**Body** (padding 20px, 16px gap):

*Variant columns* — `grid-template-columns: repeat(n+1, minmax(0, 1fr))`, 12px
gap. Each column is a card (padding 14px, 12px gap, radius 12) with a title row
and stacked fields. Field label: mono 10px/600, `letter-spacing: 0.06em`,
uppercase, `--color-text-muted`.

- **Column A — "A · as recorded"**, `baseline` neutral badge. All values are
  read-only mono 13px text: model, instructions version, temperature, tools,
  MCP servers.
- **Columns B, C — "B · variant"** with a text-button `remove`. Editable:
  model `Select` (gpt-4o, gpt-4o-mini, claude-sonnet-4-5, claude-opus-4-1,
  llama3.1:70b), instructions `Select` (v7 (current), v6, v5, Draft: terse
  glossary rules), temperature `Input` (mono), then tool and MCP pickers.
  Controls are compact: `padding: 6px 10px; font-size: 13px`.
- **Tool / MCP picker** — a wrapping row of 6px-gap toggle chips, mono 11px,
  radius 6, padding 3px 8px, prefixed `[x] ` when on and `[ ] ` when off.
  On: `1px solid var(--color-accent-ui)`, background
  `color-mix(in oklch, var(--color-accent-ui) 12%, var(--color-card))`, text
  `--color-accent-ui`. Off: `1px solid var(--color-border-strong)`,
  transparent, `--color-text-muted`. In column A the chips are disabled and
  off-chips drop to `opacity: 0.4`.
- **`[+] add variant`** — dashed-border button, `min-height: 120px`, mono 12px,
  `--color-text-muted`. Caps at 3 variants (A + B + C).

*Two option cards* side by side (each `flex: 1; min-width: 260px`, radius 12,
padding 14px, 10px gap), radio groups with `accent-color: var(--color-accent-ui)`,
13px labels:

- **REPLAY** — "All 7 messages" / "User turns only — regenerate every response" /
  "Up to the scrubber position".
- **REVIEW BY** — "Human — open side-by-side in the playground" / "LLM judge —
  score against a scorecard". Choosing the judge reveals two selects in a
  `1fr 1fr` grid: judge model and scorecard.

*Note strip* — `--color-muted`, radius 8, padding 10px 12px, 12px text, opening
with a mono `[?]` in `--color-info`: "Replays run against recorded tool results
by default, so results are comparable. Toggle live tools per variant to
re-execute side effects."

**Footer** (padding 14px 20px, top border): `Switch` "Re-execute tools live" on
the left; right-aligned `Cancel` (secondary) and
`Run {n} instances` (primary) — the count includes the baseline.

**Backend work needed.** This needs a write endpoint: given an
`AgentContext` id and a list of instance configs, enqueue one replay run per
config, then persist results so the comparison view can join them. Recorded
tool results should be replayed from `AgentMessage#tool_result` unless
"re-execute live" is set. Judge mode should write into the existing
scorecard/evaluation tables.

---

### 5. Traces tab (updated)

**File:** `design/ui_kits/dashboard/AgentObservability.jsx` → `AgentObs.Traces`

Existing waterfall, with two additions:

- **Collapsed row** now carries `<ContextMeter compact>` in the right-hand
  metadata group, before duration / cost / status.
- **Expanded row** gains, below the span bars (14px above): a full
  `ContextMeter` labeled **"Context at time of call"**, `defaultOpen`, with
  `cached` and `thinking`.
- **Tool-call token table** below that (12px above; omitted when the trace made
  no tool calls). Bordered box, radius 10, `--color-border-light`, four columns
  `1fr 72px 72px 64px` with 12px gaps and 7px 12px cell padding, all mono:
  - Header row on `--color-muted`, 10px/600 uppercase,
    `letter-spacing: 0.05em`: `TOOL CALL` / `IN` (`--color-token-in`) /
    `OUT` (`--color-token-out`) / `TIME`, the three numeric columns
    right-aligned.
  - One 12px row per call: tool name in `--span-tool` at 600, `in` in
    `--color-text-secondary`, `out` in `--color-text-cell` — or
    `--color-warning-text` at 600 when it exceeds 15k — and duration in
    `--color-text-muted`.
  - Footer row above a `--color-border` rule: `added to context` and the column
    sums, 11px `--color-text-muted`.
- Below that a mono 11px meta line, 18px gaps:
  `model gpt-4o-mini`, `in 41.7k` (`in` in `--color-token-in`),
  `out 1.8k` (`out` in `--color-token-out`), `finish_reason stop`. A
  `finish_reason` other than `stop` renders in `--color-warning-text` — the
  cheapest possible truncation signal.

Row chrome unchanged: chevron `>` rotating 90°, mono trace id, bold
`Agent#action`, relative time, right-aligned metadata, status `Badge`
(success < 400, else error).

---

### 6. Metrics, Evals, Feedback tabs

Unchanged from the previous handoff; implementations are in the same file
(`AgentObs.Metrics`, `AgentObs.Evals`, `AgentObs.Feedback`). Briefly:

- **Metrics** — 4-up `StatCard` grid (Requests, Avg Latency, Cost, Error Rate)
  with sparklines; latency percentile bars where p99 is `--color-warning`;
  token usage split bar (`in` `--color-token-in` / `out` `--color-token-out` /
  thinking `--color-text-muted`).
- **Evals** — collapsible eval runs, `avg` badge colored by threshold, and per
  criterion a `ScoreBar` plus a 60×20 trend sparkline (green when the last
  point ≥ the first, else red).
- **Feedback** — CSAT percentage at 32px mono, +1/-1 split bar, filter `Tag`s
  (All / Positive / Negative / With comments), and a list of comments each
  linking to its trace via a mono `tr_9f2e41 ->` link in `--color-info`.

---

## Interactions & behavior summary

| Trigger | Behavior |
| --- | --- |
| Click a tab | Swap panel; no route change in the prototype (use nested routes in the app) |
| Click an interaction row | Select it, reset scrubber to end |
| Click the scrubber track | Seek; transcript and **ContextMeter recompute** |
| Play button | Advance 0.25; at the end the glyph becomes `<<` and it restarts |
| Click a trace row | Toggle expansion (single-open accordion) |
| Click ContextMeter header | Toggle the breakdown |
| `Reload into Instance` | Open the modal |
| Variant chip | Toggle that tool/MCP for that variant |
| `[+] add variant` | Append variant C (max 3) |
| Overlay click / `[x]` / Cancel | Close the modal |

Transitions are deliberately minimal: `transform 0.15s ease` on chevrons,
`width 0.4s ease` on `ScoreBar` fills. Nothing else animates.

## State

```
tab                      // shared across both tab groups
Traces:       openId                       // single-open accordion
Interactions: sel, pos, reload             // pos ∈ [0,1] drives transcript + context
ReloadPanel:  variants[], replay, mode     // variants: {id, model, instructions, temperature, tools[], mcps[]}
Evals:        open                         // index, -1 = none
Feedback:     filter                       // all | up | down | comment
ContextMeter: open
```

Derived, never stored: `shown`, `msgTok`, `toolTok`, `segments`, `used`,
`totalAll`, the growth curve. Keep them derived in the app too — that is what
makes the meter track the scrubber for free.

## Design tokens

All values are CSS custom properties in `design/tokens/`. Light mode is
`:root`; dark mode is the `.theme-dark` scope. Do not hardcode hex values —
these already exist in the app's token layer.

**Used by this feature (light mode):**

| Token | Value |
| --- | --- |
| `--color-accent-ui` | `#ef4444` (product accent; `--color-accent` `#FA343B` is marketing only) |
| `--color-card` / `--color-background-page` | `#ffffff` |
| `--color-muted` | `#f3f4f6` |
| `--color-border` / `-light` / `-strong` | `#e5e7eb` / `#f3f4f6` / `#d1d5db` |
| `--color-text-primary` / `-cell` / `-secondary` / `-muted` | `#111827` / `#4b5563` / `#6b7280` / `#9ca3af` |
| `--color-success` / `-text` | `#16a34a` / `#166534` |
| `--color-warning` / `-text` | `#eab308` / `#854d0e` |
| `--color-error` / `-text` | `#dc2626` / `#991b1b` |
| `--color-info` / `-text` | `#3b82f6` / `#1e40af` |
| `--color-token-in` / `-out` | `#2563eb` / `#7c3aed` |
| `--span-tool` | `#22c55e` |

Dark mode replaces surfaces with `#0f0f0f` / `#1a1a1a`, cards with
`rgba(255,255,255,0.05)`, and text with white at 100/70/60/40% opacity. The
`color-mix` segment ramp resolves correctly in both because it mixes toward
`--color-card`.

**Color discipline:** blue (`--color-token-in`) means context and input tokens;
purple (`--color-token-out`) means output; green (`--span-tool`) means tools; the
reds (`--color-accent-ui` for controls, `--color-warning` / `--color-error` for
thresholds) are reserved. Keep the ContextMeter ramp off red so its 75% and 90%
states stay legible.

**Type:** `--font-text` = "Inter Variable", `--font-mono` = "JetBrains Mono".
Product scale: 10 / 11 / 13 / 14 / 16 / 20 / 24 / 32px. Every number, id,
token count, model name, and micro-label is mono. Micro-labels are uppercase
with `letter-spacing: 0.05–0.06em` at 10–11px / 600.

**Radii:** 6 chips · 8 controls and small buttons · 12 cards · 16 modal · 999
bars. **Card padding:** 12–20px. **Gaps:** 8 chips · 12 within cards · 16 between
sections · 20–24 page.

## Assets

`design/assets/` holds the real brand assets pulled from the repo
(`public/images/`), and `design/fonts/` the two webfonts. Use whatever the app
already ships instead of these copies. The only glyphs this feature needs are
ASCII/TUI: `@ > [] [x] [ ] [=] [~] [!] [?] |> << -> <- [+]`. **No icon font, no
SVG icon set, no emoji.**

## Files

| File | Contains |
| --- | --- |
| `design/ui_kits/dashboard/index.html` | App shell — open this in a browser to see everything |
| `design/ui_kits/dashboard/AgentDetailScreen.jsx` | Tab bar, config tabs, Tools/MCP panel |
| `design/ui_kits/dashboard/AgentObservability.jsx` | Traces, Metrics, Interactions, Evals, Feedback + mock data |
| `design/ui_kits/dashboard/AgentInstance.jsx` | ContextMeter runtime copy, InstanceBar, ReloadPanel |
| `design/ui_kits/dashboard/AgentListScreen.jsx` | Fleet grid with nested activity rings |
| `design/components/data/ContextMeter.{jsx,d.ts,prompt.md}` | Canonical ContextMeter + prop docs |
| `design/components/{core,data,feedback}/` | Button, Input, Select, Switch, Tabs, Badge, Tag, DataTable, StatCard, SpanBar, ScoreBar, MonoLabel, Toast, Tooltip |
| `design/tokens/*.css`, `design/styles.css` | Token layer |

`AgentInstance.jsx` deliberately duplicates `components/data/ContextMeter.jsx`
as a `window.AAKit` global so the prototype runs without a bundler. In the app
there should be exactly one implementation.

## Suggested build order

1. `ContextMeter` + the serializer fields it needs — it is the reusable piece
   and unblocks the other two.
2. Traces additions (smallest change, immediate value).
3. Interactions tab: rail, transcript, scrubber, derived context.
4. Reload modal + the replay endpoint + the comparison view the runs land in.
