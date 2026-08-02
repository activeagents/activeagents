A configured agent (instance) as an expandable object. Collapsed: name, description, `req`/`err` indicators, compact context posture, status badge. Expanded: instance chips (model/temp/instructions/tools/mcp/ctx), health stats with sparklines, avg-context meter, nested recent TraceRows.

```jsx
<AgentRow name="TranslationAgent" description="Locale-aware translation with glossary + TM" status="healthy"
  instance={{ provider: 'openai', model: 'gpt-4o-mini', temperature: 0.7, instructions: 'v7', tools: ['translate', 'glossary_lookup'], mcps: ['github'], limit: 128000 }}
  health={{ requests: '4.5K', latency: 847, errRate: '0.8%', spark: [5,7,6,10,9,12,11], latSpark: [12,10,11,9,8,6,5], errSpark: [2,1,3,1,2,1,1] }}
  posture={{ limit: 128000, segments: segs }}
  traces={[traceProps]} />
```
