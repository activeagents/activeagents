One conversation stream (AgentContext) as an expandable object: context meter + transcript. Role glyphs `@` user (info) / `>` assistant (accent) / `[]` tool (green); right gutter shows each event's context cost (`+9.3k`, warning > 15k). Events with a `trace` get a `+ tr_x` chip that expands the TraceRow inline.

```jsx
<InteractionRow id="ctx_a41f" action="#translate" user="jess@acme.dev" when="14m ago"
  turns={7} gens={4} duration="3m 12s" sentiment="positive"
  ctx={{ limit: 128000, cached: 38400, segments: segs }}
  events={[
    { role: 'user', text: 'Translate the pricing page…', tokens: 1240 },
    { role: 'tool', name: 'glossary_lookup', text: '14 terms pinned', inTok: 180, outTok: 3100, dur: '210ms', trace: traceProps },
    { role: 'assistant', text: 'Done — three locales.', tokens: 4820, model: 'gpt-4o-mini', cached: true },
  ]} />
```
