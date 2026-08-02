Context-window state — segmented blue-ramp bar + expandable breakdown. Warning at 75%, compaction alarm at 90% (the only warm colors allowed in it). Optional: deferred rows ("—" percent), expandable source groups with counts, sub-limit meters with reset countdowns, freshness footer.

```jsx
<ContextMeter limit={128000} cached={38400} thinking={2400} defaultOpen
  segments={[
    { key: 'messages', label: 'Messages', tokens: 41720 },
    { key: 'tool_results', label: 'Tool results', tokens: 12400 },
    { key: 'instructions', label: 'Instructions', tokens: 1800 },
    { key: 'tool_schemas', label: 'Tool schemas', tokens: 4100 },
    { key: 'mcp_schemas', label: 'MCP tool schemas', tokens: 8500 },
  ]}
  deferred={[{ label: 'MCP tools (deferred)', tokens: 24300 }]}
  groups={[{ label: 'MCP tools', tokens: 8500, count: 74, items: [{ label: 'github.search_code', tokens: 1240 }] }]}
  limits={[{ label: '5-hour limit', pct: 0.05, resetIn: 'resets in 3h 15m' }]}
  limitsLabel="Usage limits · Pro"
  updatedAt="updated 8m ago · refreshes on next generation"
/>
<ContextMeter compact limit={128000} segments={segs} />  // 132px inline variant for rows
```
