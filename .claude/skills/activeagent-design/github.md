repo: activeagents/activeagents
branch: main

## Last sync
date: 2026-09-21T17:40:00Z

### Recreated from this project — "Evaluations Redesign v2" (REVIEW EVALS RUNS)
- Built in the `actionagent` engine (activeagents/activeagent, branch
  `claude/awesome-gauss-ebky6n`), which this platform mounts, rather than in
  this repo's deleted dashboard copy: *(gem)* `frontend/components/dashboard/EvaluationsView.jsx`,
  `frontend/components/dashboard/evaluations/` (RunsList, EvaluationRunDetail,
  ModelScorecard, SpendStrip, CriteriaFooter, EvaluationForm) and
  `frontend/utils/evaluationRuns.mjs`.
- Evaluations as the top level, every run listed with its movement against
  the run before it, a run page with cohort scorecards, verdict, criteria ×
  models matrix and what to fix; a suite's runs list is the same component.
- Added beyond the export: each run's cost as the agent's spend (per
  interaction — the operating figure) apart from the judge's (offline).
- Rows keep their metric columns aligned with the `MetaStrip` from
  activeagents/activeagent#470.
- Reference shots: `docs/design/evaluations/`.

### Earlier sync — 2026-07-31

### Updated in this project
- Added `ContextMeter` — context-window state (messages / tool results / instructions / tool + MCP schemas / memory) modeled on `AgentContext` + `AgentGeneration` token fields.
- Renamed the per-agent "Sessions" tab to **Interactions**, matching `Api::InteractionsController` (a context is one agent's interaction stream).
- Added "Reload into instance" — replay an interaction against alternate model / instructions / tools / MCP variants for human or judge review.
- Traces now show context state per call, plus `finish_reason` and cached/thinking token counts.

## Screen map
The dashboard now ships as its own gem, `actionagent`, a mountable engine
living beside the `activeagent` framework gem in
github.com/activeagents/activeagent. Paths marked *(gem)* are relative to
`actionagent/` in that repo; unmarked paths are this repo's. This repo
keeps one-line alias files (`app/models/agent_context.rb` reads
`AgentContext = ActionAgent::AgentContext`).

| Screen | Built from |
| --- | --- |
| Agent detail → Interactions | *(gem)* `app/controllers/action_agent/api/interactions_controller.rb`, `app/models/action_agent/agent_context.rb`, `.../agent_generation.rb` |
| Agent detail → Traces | *(gem)* `app/models/action_agent/agent_generation.rb` (trace_id, finish_reason, cached/reasoning tokens) |
| Agent detail → Tools | `config/active_agent.yml` |
| ContextMeter component | *(gem)* `frontend/components/dashboard/ContextMeter.jsx` (`contextWindowFor`, `estimateTokens`) |

## Not yet recreated
Session Replay, Benchmarks, Sandbox spaces.
