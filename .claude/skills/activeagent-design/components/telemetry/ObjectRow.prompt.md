The shared expandable shell for the five telemetry objects (Agent @, Interaction <>, Trace ->, Evaluation =, Context #). Header: chevron · glyph chip · mono id · title · mono meta · right-aligned indicators · status badge. `depth > 0` = nested variant. Build new telemetry objects on this shell; don't hand-roll accordions.

```jsx
<ObjectRow kind="trace" id="tr_9f2e41" title="TranslationAgent#translate" meta="2m ago"
  status={200} statusTone="success" defaultOpen
  indicators={<span style={{ fontFamily: 'var(--font-mono)', fontSize: 12 }}>2.4s</span>}>
  {/* expanded body */}
</ObjectRow>
```
