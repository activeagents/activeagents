Ranked comparison table (models, agent leaderboards, eval run comparisons). Sortable two-line headers, hairline rows, every numeric cell a rank-tinted `ValuePill`. Per DESIGN_SPEC "Ranked Data & Comparison Tables". Use `DataTable` for operational lists instead. Shipped as `actionagent/frontend/components/dashboard/ComparisonTable.jsx` (banding in `utils/comparison.mjs`).

\`\`\`jsx
<ComparisonTable
  identity={{ key: 'label', label: 'Model', unit: 'Cohort', render: (row) => <ModelIdentity label={row.label} /> }}
  columns={[
    { key: 'passRate', label: 'Passed', unit: 'Pass rate', better: 'higher', band: 'threshold', thresholds: [0.85, 0.5], format: (_, row) => `${row.passed}/${row.total}` },
    { key: 'avgDurationMs', label: 'Latency', unit: 'Mean', better: 'lower', format: fmtMs },          // band: 'tercile' by default
    { key: 'cost', label: 'Cost', unit: 'Cohort', better: 'lower', format: fmtSpend, sub: (row) => `${fmtSpend(row.perRun)}/run` },
    { key: 'p95', label: 'P50 / P95', better: 'lower', band: 'none', format: (_, row) => `${fmtMs(row.p50)} / ${fmtMs(row.p95)}` },
    { key: 'fault', label: 'Typical fault', kind: 'text', sortable: false, align: 'left', cell: (row) => row.faultText },
  ]}
  rows={rows}
  rowKey={(row) => row.label}
  rowProps={(row) => ({ 'data-testid': 'model-comparison-row' })}
  defaultSort="passRate"           // or { key, direction }; `sort` + onSortChange makes it controlled
  density="product"                // 'compact' 8px rows · 'product' 12px · 'marketing' 20px
/>
\`\`\`

Behaviour: first click sorts by the column's `better` direction, second flips; only the active header shows a caret (`▲`/`▼`, accent red); `<th aria-sort>`. Banding is per column: `band: 'tercile'` (default) splits the rows into thirds by `better`; `'threshold'` uses fixed cutoffs; `'none'` keeps the pill neutral. Missing values are unranked and sort last. Identity cell never tints. Under 600px the header hides and each row stacks to identity + labelled pills (`data-label`).
