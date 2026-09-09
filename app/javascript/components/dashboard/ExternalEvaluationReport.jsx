import React, { useEffect, useState } from 'react';

// Reports originate outside the dashboard. Render content as text and build
// trace links locally; never follow a URL or render HTML from the payload.
const text = (value) => value == null ? '' : (typeof value === 'object' ? JSON.stringify(value) : String(value));
const score = (value) => typeof value === 'number' ? value.toFixed(2) : 'Unscored';
const traceLink = (id, label) => (
  <a key={id} className="underline" href={`/dashboard/traces?trace=${encodeURIComponent(id)}`}>{label}</a>
);

export default function ExternalEvaluationReport({ evaluation, colors }) {
  const [runs, setRuns] = useState([]);
  const [runId, setRunId] = useState(null);
  const [run, setRun] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    fetch(`/api/evaluations/${evaluation.id}`)
      .then(async (response) => {
        if (!response.ok) throw new Error(`Unable to load runs (${response.status})`);
        return response.json();
      })
      .then((data) => {
        if (cancelled) return;
        const available = data.evaluation.runs || [];
        const params = new URLSearchParams(window.location.search);
        const requested = params.get('evaluation') === String(evaluation.id) ? params.get('run') : null;
        setRuns(available);
        // A direct link can refer to a run older than the recent history page.
        setRunId(requested || available[0]?.id || null);
      })
      .catch((failure) => { if (!cancelled) setError(failure.message); });
    return () => { cancelled = true; };
  }, [evaluation.id, evaluation.latest_run?.id]);

  useEffect(() => {
    if (!runId) return;
    let cancelled = false;
    setRun(null);
    setError(null);
    fetch(`/api/evaluations/${evaluation.id}/runs/${encodeURIComponent(runId)}`)
      .then(async (response) => {
        if (!response.ok) throw new Error(`Unable to load report (${response.status})`);
        return response.json();
      })
      .then((data) => { if (!cancelled) setRun(data.run); })
      .catch((failure) => { if (!cancelled) setError(failure.message); });
    return () => { cancelled = true; };
  }, [evaluation.id, runId]);

  if (error) return <p role="alert" className="p-4 text-red-500">{error}</p>;
  if (!run?.report) return <p className="p-4">Loading report…</p>;
  return <ExternalEvaluationReportContent evaluation={evaluation} colors={colors} run={run} runs={runs} runId={runId} setRunId={setRunId} />;
}

export function ExternalEvaluationReportContent({ evaluation, colors, run, runs, runId, setRunId }) {
  const report = run.report;
  const results = report.results || [];
  const labels = [...new Set(results.map((result) => result.label))];
  const verdict = report.verdict;
  const history = runs.some((entry) => String(entry.id) === String(runId)) ? runs : [run, ...runs];

  return (
    <div className="p-4 space-y-4" style={{ color: colors.textPrimary }} data-testid="external-evaluation-report">
      <div className="flex flex-wrap items-center gap-3">
        <span>Reported by {evaluation.config?.source}</span>
        <label>Run{' '}
          <select aria-label="Evaluation run" value={runId} onChange={(event) => setRunId(event.target.value)} style={{ background: colors.innerBg }}>
            {history.map((entry) => <option key={entry.id} value={entry.id}>{entry.run_id} · {entry.created_at}</option>)}
          </select>
        </label>
        <a className="underline" href={`/dashboard/evaluations?evaluation=${evaluation.id}&run=${run.id}`}>Link to this run</a>
      </div>
      <p>{run.samples_passed} / {run.samples_evaluated} passed · Judge: {text(report.judge) || 'Rules and expectations'}</p>
      {verdict && <p><strong>Winner: {text(verdict.winner)}</strong> {text(verdict.rationale)}</p>}
      <div className="overflow-x-auto">
        <table className="w-full text-sm text-left">
          <thead><tr><th>Model</th><th>Passed</th><th>Mean score</th><th>Tokens in / out</th><th>Mean latency</th></tr></thead>
          <tbody>{labels.map((label) => {
            const cohort = results.filter((result) => result.label === label);
            const scored = cohort.filter((result) => typeof result.score === 'number');
            const timed = cohort.filter((result) => typeof result.duration_ms === 'number');
            return <tr key={label}>
              <td>{label}</td>
              <td>{cohort.filter((result) => result.status === 'passed').length} / {cohort.length}</td>
              <td>{score(scored.length ? scored.reduce((sum, result) => sum + result.score, 0) / scored.length : null)}</td>
              <td>{cohort.reduce((sum, result) => sum + (result.input_tokens || 0), 0)} / {cohort.reduce((sum, result) => sum + (result.output_tokens || 0), 0)}</td>
              <td>{timed.length ? `${Math.round(timed.reduce((sum, result) => sum + result.duration_ms, 0) / timed.length)} ms` : '—'}</td>
            </tr>;
          })}</tbody>
        </table>
      </div>
      <div className="space-y-2">
        {results.map((result) => <details key={`${result.scenario_key}:${result.label}`} className="border rounded p-3" style={{ borderColor: colors.cardBorder }}>
          <summary className="cursor-pointer"><strong>{result.scenario_key}</strong> · {result.label} · {result.status} · {score(result.score)}{result.fault ? ` · ${result.fault}` : ''}</summary>
          <div className="space-y-2 pt-3">
            {result.group && <p>Group: {result.group}</p>}
            <p className="whitespace-pre-wrap"><strong>Prompt:</strong> {result.prompt}</p>
            <p className="whitespace-pre-wrap"><strong>Answer:</strong> {result.answer || '(no answer)'}</p>
            {result.error && <p className="text-red-500 whitespace-pre-wrap">{result.error}</p>}
            {result.recommendation && <p className="whitespace-pre-wrap"><strong>Recommendation:</strong> {result.recommendation}</p>}
            <p>Scores: {text(result.scores)} · Cost: {result.cost == null ? 'not recorded' : `$${result.cost}`}</p>
            <div className="flex flex-wrap gap-3">
              {result.metadata?.trace_id && traceLink(result.metadata.trace_id, 'Response trace')}
              {(result.metadata?.judge_trace_ids || []).map((id, index) => traceLink(id, `Judge trace ${index + 1}`))}
            </div>
            <details><summary>Tool calls and diagnosis</summary><pre className="whitespace-pre-wrap break-words">{JSON.stringify({ tool_calls: result.tool_calls, diagnosis: result.diagnosis, metadata: result.metadata }, null, 2)}</pre></details>
          </div>
        </details>)}
      </div>
      {(report.metadata?.judge_trace_ids || []).map((id, index) => traceLink(id, `Run judge trace ${index + 1}`))}
      <details><summary>Run context and recommendations</summary><pre className="whitespace-pre-wrap break-words">{JSON.stringify({ metadata: report.metadata, recommendations: report.recommendations }, null, 2)}</pre></details>
    </div>
  );
}
