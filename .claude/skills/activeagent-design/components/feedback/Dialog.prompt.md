Modal dialog.

\`\`\`jsx
<Dialog open title="Delete agent?" onClose={close}
  footer={<><Button variant="secondary">Cancel</Button><Button variant="danger">Delete</Button></>}>
  This permanently removes TranslationAgent and its 4,521 runs.
</Dialog>
\`\`\`
