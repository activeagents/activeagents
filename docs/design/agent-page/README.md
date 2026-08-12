# Agent page — design update screenshots

Reference shots for the agent detail page rebuild against
`.claude/skills/activeagent-design/design_handoff_agent_observability`.

`01`/`02` are the previous editor; the rest are the current page.

| File | Shows |
| --- | --- |
| `01-before-configuration.png` | Previous 3-column editor: config card + sidebar of action/status/stats cards |
| `02-before-tools.png` | Previous Tools tab |
| `03-after-configuration.png` | Header + two-group tab row, Configuration tab |
| `04-after-configuration-dark.png` | Same, dark theme |
| `05-after-tools.png` | Tools tab |
| `06-after-tools-dark.png` | Tools tab, dark theme |
| `07-after-instructions.png` | Instructions tab |
| `08-after-feedback.png` | Feedback tab empty state |
| `09-after-versions.png` | Versions tab empty state |

Captured from the real components in a Playwright harness at 1320px with the
app's Tailwind build loaded — not from a booted Rails app. The mock agent has
no version history, and the API calls 404, so the Traces / Metrics /
Interactions / Evals tabs are not shown populated here.
