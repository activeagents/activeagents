# Evaluations — runs redesign screenshots

Reference shots for the Evaluations page rebuilt against the Claude Design
"Evaluations Redesign v2" export (the REVIEW EVALS RUNS section), this time in
the `actionagent` engine the platform mounts (github.com/activeagents/activeagent,
`actionagent/frontend/components/dashboard/EvaluationsView.jsx` and
`evaluations/`), so the hosted dashboard and a self-hosted one read alike.

Evaluations are the top level; every run is kept and listed with its movement
against the run before it; a run opens to a scorecard per model cohort, the
judge's verdict, the criteria × models matrix (a suite's scenario matrix) and
what the run asks to fix. Every figure is a field the engine records. New
since the export: what a run cost is shown as two figures — the **agent's**
(what the replayed or sampled interactions cost to serve, with a
per-interaction rate: the operating cost of the agent) apart from the
**judge's** (the judge model's own calls, offline) — on every run row, on the
run, on a page tile and in the footer.

| File | Shows |
| --- | --- |
| `01-evaluations-runs.png` | Page with tiles (incl. cost per interaction), a sampling evaluation open on its run history |
| `02-evaluations-runs-dark.png` | Same, dark theme |
| `03-run-detail.png` | Run page: agent/judge cost strip, cohort scorecard, criteria matrix, what to fix |
| `04-run-comparison-dark.png` | Comparison run: two cohorts, judge's pick, verdict, missing model, judge cost |
| `05-run-skipped-judge.png` | Run whose judge criterion was skipped for want of credentials |
| `06-run-failed.png` | Failed run with the runner's error and the follow-up |
| `07-suite-runs.png` | Scenario suite: full-width runs list, model scorecards, verdict, fix items, scenario matrix |
| `08-suite-runs-dark.png` | Same suite with an earlier run selected, dark theme |
| `09-agent-evals-tab.png` | The same view embedded in the agent page, scoped to one agent |

Captured from the real components in a Playwright harness at 1440px with the
engine's built bundle and `fetch` answering from representative
`/api/evaluations` payloads in the shapes `ActionAgent::Api::EvaluationsController`
serializes — not from a booted Rails app. Agent names, models, scores and
costs in the shots are fixture values; the system fonts stand in for Inter
and JetBrains Mono, which the harness could not fetch.
