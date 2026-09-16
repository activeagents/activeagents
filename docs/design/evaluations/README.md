# Evaluations — runs section screenshots

Reference shots for the Evaluations page rebuilt against the Claude Design
"Evaluations Redesign v2" export: evaluations as the top level, every run
kept, and a run drill-in with per-model scorecards, the criteria × models
matrix, and what the run asks to fix.

Every label on these screens is a field the app records: evaluations,
runs, criteria (rule-based, telemetry, LLM judge), sample cohorts per
model, the judge's verdict, and the runner's missing-model and skipped
reasons. There is no scenario or client data; where the export used mock
suites and scenarios, the page reads `Evaluation`, `EvaluationRun#scores`
and the new `scores["_cohorts"]` summaries instead.

| File | Shows |
| --- | --- |
| `01-evaluations-runs.png` | Page with tiles, one evaluation expanded to its run history |
| `02-evaluations-runs-dark.png` | Same, dark theme |
| `03-run-detail.png` | Run drill-in: single cohort scorecard, criteria matrix, what to fix |
| `04-run-comparison-dark.png` | Comparison run: two cohorts, judge's pick, verdict, missing model |
| `05-run-skipped-judge.png` | Run whose judge criterion was skipped for want of credentials |
| `06-run-failed.png` | Failed run with the runner's error and the follow-up |
| `07-agent-evals-tab.png` | The same view embedded in the agent page, scoped to one agent |

Captured from the real components in a Playwright harness at 1440px with
`fetch` answering from representative `/api/evaluations` payloads in the
shapes `Api::EvaluationsController` serializes — not from a booted Rails
app. Agent names, models and scores in the shots are fixture values.
