One agent call as an expandable object: span waterfall, context-at-call meter, tool token table, generation meta (`finish_reason` ≠ stop warns). Nests inside InteractionRow/AgentRow via `depth`.

```jsx
<TraceRow id="tr_9f2e41" agent="TranslationAgent" action="#translate" when="2m ago"
  duration="2.4s" cost="$0.0182" status={200}
  ctx={{ limit: 128000, cached: 38400, segments: segs }}
  spans={[['root', 'TranslationAgent#translate', 0, 0, 100, '2.4s'], ['llm', 'openai.chat.completions', 2, 8, 64, '1.5s']]}
  tools={[{ name: 'translate_memory', in: 420, out: 8880, dur: '340ms' }]}
  gen={{ model: 'gpt-4o-mini', in: 41720, out: 1840, finish: 'stop' }} />
```
