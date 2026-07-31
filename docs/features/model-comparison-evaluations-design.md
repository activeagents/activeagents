# Model Comparison Evaluations (Judge-Defined KPIs)

**Date:** 2026-07-30 · **Status:** ✅ Phases 1–2 implemented 2026-07-30

Implementation notes:
- `judge_kind: "judge_defined"` — first run has the judge author 3–6 KPIs
  from the agent's instructions + recent runs; persisted to
  `evaluation.criteria` with `defined_by`/`defined_at` provenance
  (`EvaluationRunnerService#ensure_judge_defined_kpis!`).
- `evaluations.config["compare_models"]` — sample criteria scored once per
  model cohort (`scores[kpi][model]`), missing cohorts reported under
  `_missing_models`, judge verdict under `_verdict` (winner + rationale).
- Evaluations UI: judge mode selector, judge model, compare-models input;
  results render a KPI × model bar matrix with a verdict banner.
- Phase 3 groundwork: `AgentExecutionService` honors per-run
  `model_override` / `provider_override` in `input_params`, so replay
  comparison runs can be triggered via the execute API; the one-click
  replay orchestration remains future work.
- Verified live: claude-opus-5 defined 6 KPIs for Docs Navigator and judged
  qwen3:8b vs claude-opus-5 cohorts, declaring claude-opus-5 the winner.

## Goal

Evaluate one agent under different models and have a stronger judge model
compare them. Example: run Docs Navigator on `claude-haiku-4-5` and
`qwen3:8b`, then have `claude-opus-5` (1) define the KPIs from the agent's
own instructions, and (2) score each model's interactions against those
KPIs to validate the agent is accomplishing its goals.

## What Already Exists

- **Per-model run cohorts** — every AgentRun records its model +
  instructions digest; the Agent Report groups runs into
  (instructions × model) cohorts with success/latency/token stats, now
  labeled with agent versions (`v4 · zesty-vale`).
- **Evaluations** — `Evaluation` (criteria array incl. `llm_judge` type,
  `judge_model`, `sample_size`) scored by `EvaluationRunnerService` over the
  agent's recent `agent_generations`; rule, telemetry, and LLM-judge
  criterion types.
- **Interactions provenance** — each generation records model, provider,
  tokens, duration, trace_id, so samples can be partitioned by model.

## Gaps

1. Evaluations sample the agent's *latest* generations regardless of model —
   no per-cohort partitioning, no side-by-side verdict.
2. Criteria are hand-authored. No "judge defines the KPIs" step.
3. No way to kick off fresh comparison runs (same inputs replayed under
   N models) from the evaluation itself.

## Proposed Shape

### 1. Judge-defined KPIs (`goal_kpis` phase)

New evaluation kind `judge_defined`. On first run (or explicit refresh):

```
judge prompt := agent instructions + a sample of recent interactions
judge output := 3-7 KPIs as structured llm_judge criteria:
  { key, description, scoring_guidance, target } — persisted to
  evaluation.criteria with provenance { defined_by: "claude-opus-5", at: ... }
```

KPIs are stored, editable, and versioned with the evaluation — the judge
proposes, the user can prune. Subsequent runs reuse them (stable KPIs are
what make scores comparable across time and models).

### 2. Cohort-partitioned scoring

`EvaluationRunnerService` gains a `compare_models: ["claude-haiku-4-5",
"qwen3:8b"]` config: samples are drawn per model (from
`agent_generations.model`), each KPI scored per cohort, plus a final judge
pass that writes a comparative verdict:

```json
scores: {
  "accuracy":   { "claude-haiku-4-5": {...}, "qwen3:8b": {...} },
  "_verdict":   { "winner": "claude-haiku-4-5", "rationale": "...", "judge": "claude-opus-5" }
}
```

### 3. Comparison runs (optional replay)

"Compare" action on the evaluation: replays the last N run inputs through
`AgentExecutionService` once per candidate model (the runner already accepts
model overrides per run), so both cohorts have fresh, same-input samples
before scoring — a true A/B rather than opportunistic sampling. Note the
sandboxes API already has a `compare` collection route to model this after.

### 4. UI (Evaluations view)

- Evaluation builder: judge model picker (default strongest available,
  e.g. `claude-opus-5`), candidate models multi-select, "Let the judge
  define KPIs" toggle.
- Results: KPI rows × model columns, per-cell score + pass rate, verdict
  banner with the judge's rationale; deep-link each cell to the underlying
  interactions (the new session/run URLs make every sample addressable).

## Sequencing

1. Judge-defined KPIs on the existing single-cohort flow (no schema change —
   criteria already jsonb; add `judge_kind: "judge_defined"`).
2. Per-model sample partitioning + comparative verdict (scores jsonb shape
   change, UI columns).
3. Replay-based comparison runs.
