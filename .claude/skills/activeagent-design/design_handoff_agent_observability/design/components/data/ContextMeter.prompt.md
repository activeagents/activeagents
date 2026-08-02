# ContextMeter

Shows how full an agent interaction's context window is, and what is taking up
the space. Use it anywhere an engineer would ask "how much room is left, and
what do I evict?" — interaction transcripts, trace detail, benchmark rows.

## When to use

- **Expanded** (default) on an interaction or trace detail view — full breakdown.
- **`compact`** in list rows (traces, interactions, sessions) — a 132px bar and
  a percentage, no breakdown.

## Data mapping (activeagents/activeagents)

| Segment | Source |
| --- | --- |
| `messages` | `AgentMessage` rows where role is user/assistant |
| `tool_results` | `AgentMessage` rows where role is `tool` — both `tool_arguments` (the call the model emitted) and `tool_result` (what came back). Both land in context. |
| `instructions` | `AgentContext#instructions` + system prompt |
| `tool_schemas` | JSON schemas for the agent's Rails actions and tool classes |
| `mcp_schemas` | schemas advertised by connected MCP servers |
| `memory` | memory files / retrieved documents pinned into the prompt |

`cached` maps to `AgentGeneration#cached_tokens`, `thinking` to
`reasoning_tokens`. `limit` is the model's context window.

Always surface a tool call's **in** (arguments) and **out** (result) counts
next to the call, not just a combined total — a 300-token call returning 28k is
the single most common way a context window fills up, and the split is what
tells an operator whether to trim the schema or truncate the result.

## Rules

- Always order segments largest-source-first; free space renders last, muted.
- Never show a raw token integer — the component abbreviates (`412.4k`, `1M`).
- The 75%/90% thresholds are semantic, not decorative: amber means the operator
  should consider trimming, red means the next turn compacts. The segment ramp
  is therefore **blue** (`color-mix` steps off `--color-token-in`) — amber and
  red must be the only warm colors in the component, or the alarm state stops
  reading as an alarm. Never rebuild the ramp on `--color-accent-ui`.
- **The legend always keys the bar.** In a threshold state the `messages`
  segment recolors to amber or red — its legend swatch must recolor with it, or
  the breakdown stops explaining the bar.
- No emoji. Footnote glyphs are `[=]` cached and `[~]` thinking.

Pass only `{ key, label, tokens }` — the default color ramp is resolved from
`CONTEXT_SEGMENTS` by `key`. Override `color` only for a segment outside the
standard six.

```jsx
<ContextMeter
  limit={200000}
  cached={128000}
  segments={[
    { key: 'messages', label: 'Messages', tokens: 41720 },
    { key: 'tool_schemas', label: 'Tool schemas', tokens: 6100 },
  ]}
/>
```
