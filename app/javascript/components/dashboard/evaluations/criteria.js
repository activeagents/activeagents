// Shared vocabulary for the Evaluations page.
//
// A run's `scores` payload is { criterion_key => stats }, where stats is
// either flat ({ score, min, max, passed, total } or { skipped, reason }) or,
// for a comparison run, a cohort map { model => stats }. Beside those sit the
// runner's "_"-prefixed metadata keys: _cohorts (per-model sample summaries),
// _verdict (the judge's pick) and _missing_models. Everything here reads that
// shape; nothing here invents data the runner did not record.

export const PASS_THRESHOLD = 0.7;

const TELEMETRY_TYPES = ['trace_error_rate', 'trace_latency'];

export const CRITERION_GROUPS = [
  { id: 'rules', label: 'Rule-based' },
  { id: 'telemetry', label: 'Telemetry' },
  { id: 'judge', label: 'LLM judge' },
];

export const criterionGroup = (criterion) => {
  if (criterion?.type === 'llm_judge') return 'judge';
  if (TELEMETRY_TYPES.includes(criterion?.type)) return 'telemetry';
  return 'rules';
};

const humanize = (key) => String(key || '').replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());

export const truncate = (text, max) => {
  const value = String(text || '');
  return value.length > max ? `${value.slice(0, max - 1)}…` : value;
};

export const formatMs = (ms) => {
  const value = Number(ms) || 0;
  if (value >= 1000) return `${(value / 1000).toFixed(value % 1000 === 0 ? 0 : 1)}s`;
  return `${Math.round(value)}ms`;
};

export const formatTokens = (value) => {
  if (value == null) return '—';
  if (value >= 1e6) return `${(value / 1e6).toFixed(1).replace(/\.0$/, '')}M`;
  if (value >= 1e3) return `${(value / 1e3).toFixed(1).replace(/\.0$/, '')}k`;
  return String(Math.round(value));
};

export const timeAgo = (iso) => {
  if (!iso) return '';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  if (mins < 1440) return `${Math.floor(mins / 60)}h ago`;
  return `${Math.floor(mins / 1440)}d ago`;
};

export const criterionLabel = (criterion) => {
  const config = criterion?.config || {};
  switch (criterion?.type) {
    case 'response_present': return 'Response present';
    case 'min_length': return 'Response length';
    case 'max_latency_ms': return 'Latency';
    case 'token_budget': return 'Output tokens';
    case 'contains': return 'Must contain';
    case 'not_contains': return 'Must not contain';
    case 'trace_error_rate': return 'Trace error rate';
    case 'trace_latency': return 'Trace latency';
    case 'llm_judge': return config.description || humanize(criterion.key);
    default: return humanize(criterion?.key);
  }
};

// What each sample (or, for telemetry, the trace aggregate) is held to.
export const criterionExpectation = (criterion) => {
  const config = criterion?.config || {};
  switch (criterion?.type) {
    case 'response_present': return 'non-empty output';
    case 'min_length': return `≥ ${config.chars ?? 40} chars`;
    case 'max_latency_ms': return `≤ ${formatMs(config.ms ?? 5000)}`;
    case 'token_budget': return `≤ ${config.output_tokens ?? 1000} output tokens`;
    case 'contains': return `matches /${config.pattern || ''}/i`;
    case 'not_contains': return `no /${config.pattern || ''}/i`;
    case 'trace_error_rate': return `error rate ≤ ${config.max_error_rate ?? 5}% · ${config.window_hours ?? 168}h`;
    case 'trace_latency': return `avg ≤ ${formatMs(config.max_avg_ms ?? 5000)} · ${config.window_hours ?? 168}h`;
    case 'llm_judge': return config.prompt ? `judge: ${truncate(config.prompt, 72)}` : 'judge scores 0.0–1.0';
    default: return '';
  }
};

export const judgeLabel = (evaluation) => {
  if (evaluation?.judge_kind === 'judge_defined') {
    return `judge-defined KPIs${evaluation.judge_model ? ` · ${evaluation.judge_model}` : ''}`;
  }
  if (evaluation?.judge_kind === 'llm') return evaluation.judge_model || 'LLM judge';
  return 'rule-based';
};

export const runLabel = (evaluation) => {
  const criteria = (evaluation?.criteria || []).length;
  const models = (evaluation?.compare_models || []).length;
  const noun = criteria === 1 ? 'criterion' : 'criteria';
  if (models) return `${criteria} ${noun} × ${models} ${models === 1 ? 'model' : 'models'}`;
  return `${criteria} ${noun} · ${evaluation?.sample_size ?? 0} samples`;
};

// --- run payload -----------------------------------------------------------

export const isCohortMap = (value) =>
  value != null && typeof value === 'object' && !Array.isArray(value) && !('score' in value) && !('skipped' in value);

export const criterionEntries = (run) =>
  Object.entries(run?.scores || {}).filter(([key, value]) => !key.startsWith('_') && value && typeof value === 'object');

export const isComparison = (run) => criterionEntries(run).some(([, value]) => isCohortMap(value));

// The models a run scored, in the runner's order.
export const runModels = (run) => {
  const cohorts = run?.scores?._cohorts;
  if (cohorts && typeof cohorts === 'object' && Object.keys(cohorts).length) return Object.keys(cohorts);
  const models = [];
  criterionEntries(run).forEach(([, value]) => {
    if (!isCohortMap(value)) return;
    Object.keys(value).forEach((model) => { if (!models.includes(model)) models.push(model); });
  });
  return models;
};

// Stats for one criterion under one model column. Telemetry criteria are
// scored once per run, so a flat value applies to every column.
export const cellStats = (value, model) => {
  if (!value || typeof value !== 'object') return null;
  if (isCohortMap(value)) return model ? value[model] || null : null;
  return value;
};

export const findCriterion = (evaluation, key) =>
  (evaluation?.criteria || []).find((criterion) => criterion.key === key) || { key, type: key, config: {} };

export const passRate = (run) =>
  run && run.samples_evaluated ? (run.samples_passed || 0) / run.samples_evaluated : null;

// Per-model sample summaries. Runs recorded before the runner stored
// _cohorts fall back to what the criteria stats can tell.
export const runCohorts = (run) => {
  if (!run) return [];
  const stored = run.scores?._cohorts;
  if (stored && typeof stored === 'object' && Object.keys(stored).length) {
    return Object.entries(stored).map(([model, cohort]) => ({ model, ...cohort }));
  }
  const models = runModels(run);
  if (models.length) {
    return models.map((model) => {
      const totals = criterionEntries(run)
        .map(([, value]) => cellStats(value, model))
        .filter((stats) => stats && stats.total != null)
        .map((stats) => stats.total);
      return { model, samples: totals.length ? Math.max(...totals) : null, passed: null };
    });
  }
  return [{ model: null, samples: run.samples_evaluated ?? null, passed: run.samples_passed ?? null }];
};

// How one model column did across the run's criteria.
export const modelScorecard = (run, model) => {
  const cells = criterionEntries(run).map(([, value]) => cellStats(value, model)).filter(Boolean);
  const scored = cells.filter((stats) => stats.score != null);
  return {
    avg: scored.length ? scored.reduce((sum, stats) => sum + stats.score, 0) / scored.length : null,
    scored: scored.length,
    cleared: scored.filter((stats) => stats.score >= PASS_THRESHOLD).length,
    below: scored.filter((stats) => stats.score < PASS_THRESHOLD).length,
    skipped: cells.filter((stats) => stats.skipped).length,
  };
};

// Everything in a run that asks for a follow-up, derived from what the
// runner recorded: a failed run, cohorts with no generations, criteria it
// could not score, and criteria that came in under the pass mark.
export const fixItems = (evaluation, run) => {
  if (!run) return [];
  const items = [];
  const agentRunHref = `/dashboard/agents/${evaluation?.agent?.id}/run`;

  if (run.status === 'failed') {
    items.push({
      kind: 'failed',
      label: 'run failed',
      scope: run.number ? `run #${run.number}` : 'latest run',
      text: run.error_message || 'The run ended before any criterion was scored.',
      action: { label: 'Run agent', href: agentRunHref, hint: 'Run Agent ->' },
    });
  }

  const missing = Array.isArray(run.scores?._missing_models) ? run.scores._missing_models : [];
  if (missing.length) {
    items.push({
      kind: 'missing',
      label: `no generations ×${missing.length}`,
      scope: 'comparison cohorts',
      text: 'The comparison asked for these models, but the agent has no recorded generations under them. Run the agent under each model, then run the evaluation again.',
      chipsLabel: 'missing models',
      chips: missing,
      action: { label: 'Run agent', href: agentRunHref, hint: 'Run Agent ->' },
    });
  }

  const skipped = { judge: [], telemetry: [], rules: [] };
  const below = [];
  criterionEntries(run).forEach(([key, value]) => {
    const criterion = findCriterion(evaluation, key);
    const cells = isCohortMap(value) ? Object.entries(value) : [[null, value]];
    cells.forEach(([model, stats]) => {
      if (!stats || typeof stats !== 'object') return;
      if (stats.skipped) {
        skipped[criterionGroup(criterion)].push({ key, model, reason: stats.reason });
      } else if (stats.score != null && stats.score < PASS_THRESHOLD) {
        below.push({ key, model, stats, criterion });
      }
    });
  });

  const keysOf = (list) => [...new Set(list.map((entry) => entry.key))];
  const criteriaScope = (list) => `${keysOf(list).length} ${keysOf(list).length === 1 ? 'criterion' : 'criteria'}`;

  if (skipped.judge.length) {
    items.push({
      kind: 'judge',
      label: `judge skipped ×${skipped.judge.length}`,
      scope: criteriaScope(skipped.judge),
      text: skipped.judge[0].reason || 'The LLM judge could not score these criteria.',
      chipsLabel: 'unscored criteria',
      chips: keysOf(skipped.judge),
      action: { label: 'Add provider key', href: '/dashboard/settings', hint: 'Settings ->' },
    });
  }
  if (skipped.telemetry.length) {
    items.push({
      kind: 'telemetry',
      label: `no telemetry ×${skipped.telemetry.length}`,
      scope: criteriaScope(skipped.telemetry),
      text: skipped.telemetry[0].reason || 'No traces were recorded for this agent in the criterion window.',
      chipsLabel: 'unscored criteria',
      chips: keysOf(skipped.telemetry),
      action: { label: 'Open traces', href: '/dashboard/traces', hint: 'Traces ->' },
    });
  }
  if (skipped.rules.length) {
    items.push({
      kind: 'samples',
      label: `no samples ×${skipped.rules.length}`,
      scope: criteriaScope(skipped.rules),
      text: skipped.rules[0].reason || 'No generation could be scored against these criteria.',
      chipsLabel: 'unscored criteria',
      chips: keysOf(skipped.rules),
      action: { label: 'Run agent', href: agentRunHref, hint: 'Run Agent ->' },
    });
  }
  if (below.length) {
    const models = [...new Set(below.map((entry) => entry.model).filter(Boolean))];
    items.push({
      kind: 'below',
      label: `below pass mark ×${below.length}`,
      scope: `${criteriaScope(below)}${models.length ? ` · ${models.length} ${models.length === 1 ? 'model' : 'models'}` : ''}`,
      text: `Scored under the ${PASS_THRESHOLD.toFixed(2)} pass mark. Each line is what the criterion expects against how the samples did; tighten the agent's instructions or revisit the budget before running again.`,
      details: below.map((entry) =>
        `${entry.key}${entry.model ? ` · ${entry.model}` : ''} ${entry.stats.score.toFixed(2)} · expects ${criterionExpectation(entry.criterion)} · ${entry.stats.passed}/${entry.stats.total} passed`),
    });
  }
  return items;
};

// In-app navigation the dashboard router listens for (pushState alone does
// not re-run its path parser).
export const navigateTo = (href) => {
  window.history.pushState({}, '', href);
  window.dispatchEvent(new Event('dashboard:navigate'));
};
