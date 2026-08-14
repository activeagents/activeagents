Context-window state — segmented bar + expandable breakdown. Segments carry the telemetry palette (span types + conversation roles), so the meter reads like the trace above it: instructions violet, user messages blue, assistant messages red, tool traffic amber/green, generated output red. Colors never move with the threshold — warning at 75% and the compaction alarm at 90% recolor the value, the border and the alarm line instead. Optional: deferred rows ("—" percent), expandable source groups with counts, sub-limit meters with reset countdowns, freshness footer.

```jsx
<ContextMeter limit={128000} cached={38400} thinking={2400} defaultOpen
  segments={[
    { key: 'instructions', label: 'Instructions', tokens: 1800 },
    { key: 'messages_user', label: 'User messages', tokens: 41720 },
    { key: 'messages_assistant', label: 'Assistant messages', tokens: 9000 },
    { key: 'tool_results', label: 'Tool results', tokens: 12400 },
    { key: 'tool_schemas', label: 'Tool schemas', tokens: 4100 },
    { key: 'mcp_schemas', label: 'MCP tool schemas', tokens: 8500 },
    { key: 'output', label: 'Generated output', tokens: 1840 },
  ]}
  deferred={[{ label: 'MCP tools (deferred)', tokens: 24300 }]}
  groups={[{ label: 'MCP tools', tokens: 8500, count: 74, items: [{ label: 'github.search_code', tokens: 1240 }] }]}
  limits={[{ label: '5-hour limit', pct: 0.05, resetIn: 'resets in 3h 15m' }]}
  limitsLabel="Usage limits · Pro"
  updatedAt="updated 8m ago · refreshes on next generation"
/>
<ContextMeter compact limit={128000} segments={segs} />  // 132px inline variant for rows

// Split a conversation's share of the window by role — user blue, assistant
// red, system violet — scaled to the tokens the provider actually counted.
messageSegments(conversationTokens, messages)  // [] when no history was recorded
```
