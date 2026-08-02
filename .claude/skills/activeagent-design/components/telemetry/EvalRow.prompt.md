An evaluation run as an expandable object. Avg badge threshold-colored (≥0.85 success, ≥0.7 warning, else error); expanded shows per-criterion ScoreBars with trend sparklines and lowest-scoring samples linking back to traces.

```jsx
<EvalRow name="Translation quality — weekly" when="2h ago" judge="claude-sonnet-4-5"
  samples="182/200 passed" avg={0.89}
  scores={[['Accuracy', 0.92, [0.85, 0.88, 0.9, 0.92]], ['Terminology', 0.81, [0.86, 0.84, 0.83, 0.81]]]}
  failures={[{ score: 0.31, note: 'Brand name translated in DE output', trace: 'tr_6c2a90' }]} />
```
