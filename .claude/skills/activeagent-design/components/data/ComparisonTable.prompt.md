Ranked comparison table (models, agent leaderboards, eval run comparisons). Sortable two-line headers, hairline rows, every numeric cell a rank-tinted `ValuePill`. Per DESIGN_SPEC "Ranked Data & Comparison Tables". Use `DataTable` for operational lists instead.

\`\`\`jsx
<ComparisonTable
  defaultSort="accuracy"
  identity={{ label: "Model", render: (r) => <ModelCell mark={r.logo} name={r.name} variant={r.effort} /> }}
  columns={[
    { key: "accuracy", label: "Accuracy", unit: "Task score", better: "higher", format: pct,   band: "threshold", thresholds: [0.85, 0.70] },
    { key: "duration", label: "Speed",    unit: "Task time",  better: "lower",  format: hms },
    { key: "tokens",   label: "Tokens",   unit: "Per run",    better: "lower",  format: int },
    { key: "cost",     label: "Cost",     unit: "Per run",    better: "lower",  format: usd },
  ]}
  rows={runs}
  density="product"   // "product" 12px rows | "marketing" 20px rows
  onSortChange={(key, dir) => setQuery({ sort: key, dir })}
/>
\`\`\`

Behaviour: first click sorts by the column's `better` direction, second flips; only the active header shows a caret (`▲`/`▼`, accent red); `<th aria-sort>`. Banding is per column: `band: "tercile"` (default) splits the visible rows into thirds by `better`; `band: "threshold"` uses fixed cutoffs. Identity cell never tints. Below 600px each row stacks to identity line + `repeat(4, 1fr)` pill grid under a sticky header row.
