Dense table for runs/traces/agents. Headers are mono uppercase; rows use bottom borders only.

\`\`\`jsx
<DataTable
  columns={["Agent", { label: "Requests", align: "right", mono: true }, { label: "Cost", align: "right", mono: true }]}
  rows={[["TranslationAgent", "4.5K", "$12.34"], ["CodeReviewAgent", "3.9K", "$18.92"]]}
  onRowClick={open}
/>
\`\`\`
