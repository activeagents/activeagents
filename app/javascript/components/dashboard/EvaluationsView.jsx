import React, { useState, useEffect, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';
import { paletteFor } from '../../utils/dashboardTheme';
import EvaluationForm from './evaluations/EvaluationForm';
import EvaluationRunDetail from './evaluations/EvaluationRunDetail';
import CriteriaFooter from './evaluations/CriteriaFooter';
import { Badge, Button, MicroLabel, Mono, StatTile, Glyph, Bar, Spinner, toneFor, toneColor, semanticFor } from './evaluations/ui';
import { criterionGroup, timeAgo, passRate, fixItems, runCohorts, runLabel, judgeLabel } from './evaluations/criteria';

// Evaluations: each evaluation is a named set of criteria scored against one
// agent's recorded generations, and every run of it is kept. The page lists
// evaluations with their run history; opening a run shows the criteria ×
// model matrix and what the run asks to fix. Everything on screen comes
// from the evaluation and run records — there is no sample data here.

const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content;

// /dashboard/evaluations/:id[/runs/:runId] deep-links one evaluation's runs.
const parseLocation = () => {
  const match = window.location.pathname.match(/\/evaluations\/(\d+)(?:\/runs\/(\d+))?/);
  if (!match) return { evaluationId: null, runId: null };
  return { evaluationId: Number(match[1]), runId: match[2] ? Number(match[2]) : null };
};

function PassedBadge({ run, darkMode }) {
  if (!run) return <Badge tone="neutral" darkMode={darkMode}>no runs</Badge>;
  if (run.status === 'failed') return <Badge tone="error" darkMode={darkMode}>failed</Badge>;
  if (run.status !== 'complete') return <Badge tone="warning" darkMode={darkMode}>{run.status}</Badge>;
  if (!run.samples_evaluated) {
    return (
      <Badge tone={run.average_score == null ? 'neutral' : toneFor(run.average_score)} darkMode={darkMode}>
        {run.average_score == null ? 'no samples' : `score ${run.average_score.toFixed(2)}`}
      </Badge>
    );
  }
  return (
    <Badge tone={toneFor(passRate(run))} darkMode={darkMode}>
      {run.samples_passed}/{run.samples_evaluated} passed
    </Badge>
  );
}

// Movement against the run before this one, in samples passed. A
// predecessor that did not complete has nothing to compare against, so the
// row says what happened to it instead of claiming this is the first run.
const deltaLabel = (run, older, sem, colors) => {
  if (run.status !== 'complete') return null;
  if (!older) return { text: 'first run', color: colors.textMuted };
  if (older.status !== 'complete') return { text: `#${older.number} ${older.status}`, color: colors.textMuted };
  const diff = (run.samples_passed || 0) - (older.samples_passed || 0);
  if (diff === 0) return { text: `same as #${older.number}`, color: colors.textMuted };
  return { text: `${diff > 0 ? '+' : ''}${diff} passed vs #${older.number}`, color: diff > 0 ? sem.success : sem.error };
};

function RunRow({ run, older, latest, evaluation, onOpen, colors, sem, darkMode }) {
  const cohorts = runCohorts(run);
  const delta = deltaLabel(run, older, sem, colors);
  const meta = `@${evaluation.agent?.name} · ${runLabel(evaluation)} · ${judgeLabel(evaluation)}`;

  return (
    <div
      role="button"
      tabIndex={0}
      data-testid="evaluation-run"
      onClick={onOpen}
      onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onOpen(); } }}
      style={{
        display: 'grid',
        gridTemplateColumns: 'minmax(220px, 1.4fr) minmax(200px, 1fr) auto',
        gap: '16px',
        alignItems: 'center',
        padding: '10px 14px',
        borderTop: `1px solid ${colors.cardBorder}`,
        cursor: 'pointer',
      }}
    >
      <div style={{ minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
          <Mono colors={colors} color={colors.textPrimary} size={12} weight={700}>Run #{run.number ?? '?'}</Mono>
          <Mono colors={colors}>{timeAgo(run.completed_at || run.created_at)}</Mono>
          {latest && <Badge tone="info" darkMode={darkMode}>latest</Badge>}
          {run.status === 'failed' && <Badge tone="error" darkMode={darkMode}>failed</Badge>}
          {run.status === 'running' && <Badge tone="warning" darkMode={darkMode}>running</Badge>}
        </div>
        <Mono colors={colors} style={{ display: 'block', marginTop: '3px', whiteSpace: 'normal' }}>{meta}</Mono>
        {run.status === 'failed' && run.error_message && (
          <Mono colors={colors} color={sem.error} style={{ display: 'block', marginTop: '3px', whiteSpace: 'normal' }}>
            [!] {run.error_message}
          </Mono>
        )}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '4px', minWidth: 0 }}>
        {run.status === 'complete' && cohorts.map((cohort) => {
          const fraction = cohort.passed != null && cohort.samples ? cohort.passed / cohort.samples : null;
          const color = toneColor(toneFor(fraction), sem, colors);
          return (
            <div key={cohort.model || 'all'} style={{ display: 'grid', gridTemplateColumns: 'minmax(70px, 130px) 1fr 44px', gap: '8px', alignItems: 'center' }}>
              <Mono colors={colors} title={cohort.model || 'all sampled generations'} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {cohort.model || 'all samples'}
              </Mono>
              <Bar fraction={fraction} color={color} colors={colors} />
              <Mono colors={colors} color={fraction == null ? colors.textMuted : color} weight={600} style={{ textAlign: 'right' }}>
                {fraction == null ? '—' : `${cohort.passed}/${cohort.samples}`}
              </Mono>
            </div>
          );
        })}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: '10px', justifyContent: 'flex-end' }}>
        {delta && <Mono colors={colors} color={delta.color} weight={600}>{delta.text}</Mono>}
        <PassedBadge run={run} darkMode={darkMode} />
        <Mono colors={colors} color={sem.info}>{'->'}</Mono>
      </div>
    </div>
  );
}

function EvaluationCard({
  evaluation, runs, expanded, onToggle, onOpenRun, onRun, onDelete, running, deleting, colors, sem, darkMode,
}) {
  const latest = evaluation.latest_run;
  const criteria = evaluation.criteria || [];
  const issues = fixItems(evaluation, latest).length;
  // Criteria are only rendered once expanded, so this exposes on the
  // collapsed card whether the evaluation scores from telemetry.
  const scoresFromTelemetry = criteria.some((criterion) => criterionGroup(criterion) === 'telemetry');
  const shownRuns = runs || (latest ? [latest] : []);
  const runsCount = evaluation.runs_count ?? shownRuns.length;
  const runsNoun = runsCount === 1 ? 'run' : 'runs';
  const summary = [
    `${runsCount} ${runsNoun}`,
    latest ? `latest #${latest.number ?? runsCount} ${timeAgo(latest.completed_at || latest.created_at)}` : null,
    latest?.status === 'complete' && latest.samples_evaluated ? `${latest.samples_passed}/${latest.samples_evaluated} passed` : null,
  ].filter(Boolean).join(' · ');

  return (
    <div
      data-testid="evaluation-card"
      data-telemetry={scoresFromTelemetry ? 'true' : 'false'}
      style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', overflow: 'hidden' }}
    >
      <div
        role="button"
        tabIndex={0}
        aria-expanded={expanded}
        onClick={onToggle}
        onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onToggle(); } }}
        style={{ display: 'flex', alignItems: 'center', gap: '10px', padding: '12px 16px', cursor: 'pointer', flexWrap: 'wrap' }}
      >
        <Mono
          colors={colors}
          style={{ width: '12px', display: 'inline-block', transform: expanded ? 'rotate(90deg)' : 'none', transition: 'transform 0.15s ease' }}
        >
          {'>'}
        </Mono>
        <Glyph colors={colors}>=</Glyph>
        <span style={{ fontSize: '15px', fontWeight: 700, color: colors.textPrimary }}>{evaluation.name}</span>
        <Mono colors={colors}>@{evaluation.agent?.name} · {runLabel(evaluation)}</Mono>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: '12px' }}>
          <Mono colors={colors}>{timeAgo(latest?.completed_at || latest?.created_at || evaluation.created_at)}</Mono>
          {issues > 0 && <Mono colors={colors} color={sem.error}>{issues} to fix</Mono>}
          <PassedBadge run={latest} darkMode={darkMode} />
        </div>
      </div>

      {expanded && (
        <div style={{ borderTop: `1px solid ${colors.cardBorder}`, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px', flexWrap: 'wrap' }}>
            <span style={{ fontSize: '13px', color: colors.textCell }}>{summary}</span>
            <Button variant="primary" size="sm" colors={colors} disabled={running} onClick={onRun}>
              {running ? 'Running…' : `Run ${runLabel(evaluation)}`}
            </Button>
          </div>

          <div style={{ border: `1px solid ${colors.cardBorder}`, borderRadius: '10px', overflow: 'hidden' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 14px', background: colors.innerBg }}>
              <MicroLabel colors={colors}>Runs</MicroLabel>
              <Mono colors={colors}>
                {runsCount} {runsNoun}{runs && runsCount > runs.length ? ` · showing ${runs.length}` : ''}
              </Mono>
            </div>
            {shownRuns.length === 0 && (
              <div style={{ padding: '14px', fontSize: '13px', color: colors.textMuted, borderTop: `1px solid ${colors.cardBorder}` }}>
                No runs yet.
              </div>
            )}
            {shownRuns.map((run, index) => {
              // Until the history loads, the list payload's previous_run
              // stands in for the run before the latest.
              const older = shownRuns[index + 1] || (!runs ? evaluation.previous_run : null);
              return (
                <RunRow
                  key={run.id}
                  run={run}
                  older={older}
                  latest={index === 0}
                  evaluation={evaluation}
                  onOpen={() => onOpenRun(run)}
                  colors={colors}
                  sem={sem}
                  darkMode={darkMode}
                />
              );
            })}
          </div>

          <CriteriaFooter evaluation={evaluation} colors={colors} sem={sem} onDelete={onDelete} deleting={deleting} />
        </div>
      )}
    </div>
  );
}

// embedded hides the page title when this renders inside the agent detail
// page's Evals tab, which already carries the heading. agentId scopes every
// number on the page to that agent — an account-wide average under one
// agent's name reads as that agent's score, which it is not.
export default function EvaluationsView({ embedded = false, agentId = null }) {
  const { darkMode } = useTheme();
  const colors = paletteFor(darkMode);
  const sem = semanticFor(darkMode);
  const [evaluations, setEvaluations] = useState([]);
  const [agents, setAgents] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [expanded, setExpanded] = useState(() => (embedded ? null : parseLocation().evaluationId));
  const [runsByEvaluation, setRunsByEvaluation] = useState({});
  const [openRun, setOpenRun] = useState(() => {
    if (embedded) return null;
    const { evaluationId, runId } = parseLocation();
    return runId ? { evaluationId, runId } : null;
  });
  const [showForm, setShowForm] = useState(false);
  const [runningId, setRunningId] = useState(null);
  const [deletingId, setDeletingId] = useState(null);

  const fetchEvaluations = useCallback(async () => {
    try {
      // Scoped server-side: the endpoint caps at the 50 most recent, so
      // narrowing here rather than after the fetch is what makes an agent's
      // older evaluations reachable at all.
      const response = await fetch(`/api/evaluations${agentId ? `?agent_id=${encodeURIComponent(agentId)}` : ''}`);
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setEvaluations(data.evaluations || []);
      setLoadError(null);
    } catch (error) {
      setLoadError(error.message);
    } finally {
      setIsLoading(false);
    }
  }, [agentId]);

  // The run history (up to 20) is one request per evaluation, made when a
  // card opens rather than for every row in the list.
  const loadRuns = useCallback(async (evaluationId) => {
    try {
      const response = await fetch(`/api/evaluations/${evaluationId}`);
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setRunsByEvaluation((prev) => ({ ...prev, [evaluationId]: data.evaluation?.runs || [] }));
    } catch (error) {
      setLoadError(error.message);
    }
  }, []);

  useEffect(() => {
    fetchEvaluations();
    fetch('/api/agents')
      .then((response) => (response.ok ? response.json() : { agents: [] }))
      .then((data) => setAgents(data.agents || []))
      .catch(() => setAgents([]));
  }, [fetchEvaluations]);

  useEffect(() => {
    const id = openRun?.evaluationId || expanded;
    if (id && !runsByEvaluation[id]) loadRuns(id);
  }, [expanded, openRun, runsByEvaluation, loadRuns]);

  // Browser back/forward between the list and a run.
  useEffect(() => {
    if (embedded) return undefined;
    const apply = () => {
      const { evaluationId, runId } = parseLocation();
      setOpenRun(runId ? { evaluationId, runId } : null);
      if (evaluationId) setExpanded(evaluationId);
    };
    window.addEventListener('popstate', apply);
    return () => window.removeEventListener('popstate', apply);
  }, [embedded]);

  const setPath = (href) => {
    if (!embedded && window.location.pathname !== href) window.history.pushState({}, '', href);
  };

  const openRunDetail = (evaluation, run) => {
    setExpanded(evaluation.id);
    setOpenRun({ evaluationId: evaluation.id, runId: run.id });
    setPath(`/dashboard/evaluations/${evaluation.id}/runs/${run.id}`);
  };

  const closeRunDetail = (evaluationId) => {
    setOpenRun(null);
    setPath(evaluationId ? `/dashboard/evaluations/${evaluationId}` : '/dashboard/evaluations');
  };

  const toggleCard = (evaluation) => {
    const next = expanded === evaluation.id ? null : evaluation.id;
    setExpanded(next);
    setPath(next ? `/dashboard/evaluations/${next}` : '/dashboard/evaluations');
  };

  const handleRun = async (evaluation) => {
    setRunningId(evaluation.id);
    setLoadError(null);
    try {
      const response = await fetch(`/api/evaluations/${evaluation.id}/run`, {
        method: 'POST',
        headers: { 'X-CSRF-Token': csrfToken() },
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        setLoadError(`Run failed (HTTP ${response.status})`);
        return;
      }
      await Promise.all([fetchEvaluations(), loadRuns(evaluation.id)]);
      if (data.run && openRun?.evaluationId === evaluation.id) openRunDetail(evaluation, data.run);
    } finally {
      setRunningId(null);
    }
  };

  const handleDelete = async (evaluation) => {
    if (!window.confirm(`Delete "${evaluation.name}"? Its runs are deleted with it.`)) return;
    setDeletingId(evaluation.id);
    setLoadError(null);
    try {
      const response = await fetch(`/api/evaluations/${evaluation.id}`, {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': csrfToken() },
      });
      if (response.ok || response.status === 404) {
        setEvaluations((prev) => prev.filter((candidate) => candidate.id !== evaluation.id));
        if (expanded === evaluation.id) setExpanded(null);
        if (openRun?.evaluationId === evaluation.id) closeRunDetail(null);
      } else {
        setLoadError(`Delete failed (HTTP ${response.status})`);
      }
    } finally {
      setDeletingId(null);
    }
  };

  if (isLoading) return <Spinner />;

  // The request is already scoped; this is a belt-and-braces guard so the
  // list, the tiles, and the empty state can never disagree.
  const shown = agentId
    ? evaluations.filter((evaluation) => String(evaluation.agent?.id) === String(agentId))
    : evaluations;

  if (openRun) {
    const evaluation = shown.find((candidate) => candidate.id === openRun.evaluationId);
    const runs = runsByEvaluation[openRun.evaluationId] || (evaluation?.latest_run ? [evaluation.latest_run] : []);
    return (
      <EvaluationRunDetail
        evaluation={evaluation}
        runs={runs}
        runId={openRun.runId}
        loading={!runsByEvaluation[openRun.evaluationId]}
        running={runningId === openRun.evaluationId}
        onSelectRun={(run) => openRunDetail(evaluation, run)}
        onRun={() => handleRun(evaluation)}
        onClose={() => closeRunDetail(null)}
        onOpenEvaluation={() => closeRunDetail(openRun.evaluationId)}
        darkMode={darkMode}
        colors={colors}
      />
    );
  }

  const latestRuns = shown.map((evaluation) => evaluation.latest_run).filter(Boolean);
  const completeRuns = latestRuns.filter((run) => run.status === 'complete');
  const samplesScored = completeRuns.reduce((sum, run) => sum + (run.samples_evaluated || 0), 0);
  const samplesPassed = completeRuns.reduce((sum, run) => sum + (run.samples_passed || 0), 0);
  const rate = samplesScored ? samplesPassed / samplesScored : null;
  const agentCount = new Set(shown.map((evaluation) => evaluation.agent?.id)).size;
  const comparedModels = new Set(shown.flatMap((evaluation) => evaluation.compare_models || []));
  const attention = shown.map((evaluation) => fixItems(evaluation, evaluation.latest_run).length);
  const attentionItems = attention.reduce((sum, count) => sum + count, 0);
  const attentionEvaluations = attention.filter(Boolean).length;
  const plural = (count, noun) => `${count} ${noun}${count === 1 ? '' : 's'}`;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
      {/* Header. Embedded in the agent page, that page owns the heading. */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '12px', flexWrap: 'wrap' }}>
        {embedded ? <div /> : (
          <div>
            <h1 style={{ fontSize: '22px', fontWeight: 700, color: colors.textPrimary, margin: 0, letterSpacing: '-0.01em' }}>Evaluations</h1>
            <p style={{ fontSize: '13px', color: colors.textSecondary, margin: '4px 0 0' }}>
              Score an agent's recorded generations against rule, telemetry and judge criteria, once per run or once per model cohort.
            </p>
          </div>
        )}
        <Button variant="primary" colors={colors} onClick={() => setShowForm((value) => !value)}>
          {showForm ? 'Cancel' : 'New Evaluation'}
        </Button>
      </div>

      {loadError && (
        <div style={{ padding: '10px 12px', borderRadius: '8px', fontSize: '13px', background: darkMode ? 'rgba(239,68,68,0.1)' : '#fef2f2', color: '#ef4444' }}>
          Failed to load evaluations: {loadError}
        </div>
      )}

      {showForm && (
        <EvaluationForm
          agents={agents}
          agentId={agentId}
          colors={colors}
          onCancel={() => setShowForm(false)}
          onCreated={async (evaluation) => {
            setShowForm(false);
            await fetchEvaluations();
            if (evaluation?.id) {
              setExpanded(evaluation.id);
              setPath(`/dashboard/evaluations/${evaluation.id}`);
            }
          }}
        />
      )}

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))', gap: '12px' }}>
        <StatTile
          label="Evaluations"
          value={shown.length}
          sub={shown.length ? `${plural(agentCount, 'agent')} · ${comparedModels.size ? `${plural(comparedModels.size, 'model')} compared` : 'no model comparisons'}` : 'none defined yet'}
          colors={colors}
        />
        <StatTile
          label="Samples scored"
          value={samplesScored}
          sub="latest run of each evaluation"
          colors={colors}
        />
        <StatTile
          label="Pass rate"
          value={rate == null ? '—' : `${Math.round(rate * 100)}%`}
          sub={rate == null ? 'no samples scored yet' : `${samplesPassed} / ${samplesScored} samples passed`}
          color={rate == null ? colors.textMuted : toneColor(toneFor(rate), sem, colors)}
          colors={colors}
        />
        <StatTile
          label="To fix"
          value={attentionItems}
          sub={attentionItems ? `across ${plural(attentionEvaluations, 'evaluation')}` : 'nothing outstanding'}
          color={attentionItems ? sem.error : colors.textPrimary}
          colors={colors}
        />
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {shown.map((evaluation) => (
          <EvaluationCard
            key={evaluation.id}
            evaluation={evaluation}
            runs={runsByEvaluation[evaluation.id]}
            expanded={expanded === evaluation.id}
            onToggle={() => toggleCard(evaluation)}
            onOpenRun={(run) => openRunDetail(evaluation, run)}
            onRun={() => handleRun(evaluation)}
            onDelete={() => handleDelete(evaluation)}
            running={runningId === evaluation.id}
            deleting={deletingId === evaluation.id}
            colors={colors}
            sem={sem}
            darkMode={darkMode}
          />
        ))}
      </div>

      {shown.length === 0 && !showForm && (
        <div style={{ textAlign: 'center', padding: '40px 20px', background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px' }}>
          <div style={{ fontSize: '15px', fontWeight: 600, color: colors.textPrimary }}>No evaluations yet</div>
          <p style={{ fontSize: '13px', color: colors.textSecondary, margin: '6px 0 0' }}>
            Create one to score an agent's recorded generations. Every run is kept, so scores stay comparable over time.
          </p>
        </div>
      )}
    </div>
  );
}
