import React, { useState, useEffect, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

const RULE_CRITERIA = [
  { type: 'response_present', key: 'response_present', label: 'Response present', config: {} },
  { type: 'min_length', key: 'response_length', label: 'Response length ≥ 40 chars', config: { chars: 40 } },
  { type: 'max_latency_ms', key: 'latency', label: 'Latency ≤ 5s', config: { ms: 5000 } },
  { type: 'token_budget', key: 'token_budget', label: 'Output ≤ 1000 tokens', config: { output_tokens: 1000 } },
];

const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content;

const timeAgo = (iso) => {
  if (!iso) return '';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 1440) return `${Math.floor(mins / 60)} hours ago`;
  return `${Math.floor(mins / 1440)} days ago`;
};

const scoreStatus = (value) => {
  if (value >= 0.85) return 'high';
  if (value >= 0.7) return 'medium';
  return 'low';
};

export default function EvaluationsView() {
  const { darkMode } = useTheme();
  const [evaluations, setEvaluations] = useState([]);
  const [agents, setAgents] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [expandedEval, setExpandedEval] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [runningId, setRunningId] = useState(null);
  const [form, setForm] = useState({
    agent_id: '', name: '', sample_size: 20,
    criteria: RULE_CRITERIA.map((c) => c.key),
    containsPattern: '', llmJudgePrompt: '',
  });
  const [formError, setFormError] = useState(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const fetchEvaluations = useCallback(async () => {
    try {
      const response = await fetch('/api/evaluations');
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setEvaluations(data.evaluations || []);
      setLoadError(null);
    } catch (error) {
      setLoadError(error.message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchEvaluations();
    fetch('/api/agents')
      .then((r) => (r.ok ? r.json() : { agents: [] }))
      .then((data) => setAgents(data.agents || []))
      .catch(() => setAgents([]));
  }, [fetchEvaluations]);

  const buildCriteria = () => {
    const criteria = RULE_CRITERIA
      .filter((c) => form.criteria.includes(c.key))
      .map(({ key, type, config }) => ({ key, type, config }));
    if (form.containsPattern.trim()) {
      criteria.push({ key: 'contains', type: 'contains', config: { pattern: form.containsPattern.trim() } });
    }
    if (form.llmJudgePrompt.trim()) {
      criteria.push({ key: 'quality', type: 'llm_judge', config: { prompt: form.llmJudgePrompt.trim() } });
    }
    return criteria;
  };

  const handleCreate = async (event) => {
    event.preventDefault();
    setIsSubmitting(true);
    setFormError(null);
    try {
      const response = await fetch('/api/evaluations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
        body: JSON.stringify({
          evaluation: {
            agent_id: form.agent_id,
            name: form.name,
            sample_size: form.sample_size,
            judge_kind: form.llmJudgePrompt.trim() ? 'llm' : 'rules',
            criteria: buildCriteria(),
          },
        }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error((data.errors || [data.error]).filter(Boolean).join(', ') || 'Failed to create evaluation');
      setShowForm(false);
      setForm({ ...form, name: '' });
      await fetchEvaluations();
      setExpandedEval(data.evaluation?.id ?? null);
    } catch (error) {
      setFormError(error.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleRun = async (id) => {
    setRunningId(id);
    try {
      await fetch(`/api/evaluations/${id}/run`, {
        method: 'POST',
        headers: { 'X-CSRF-Token': csrfToken() },
      });
      await fetchEvaluations();
    } finally {
      setRunningId(null);
    }
  };

  const colors = {
    cardBg: darkMode ? '#1f1f1f' : '#ffffff',
    cardBorder: darkMode ? '#2a2a2a' : '#e5e7eb',
    innerBg: darkMode ? 'rgba(255,255,255,0.04)' : '#f9fafb',
    trackBg: darkMode ? 'rgba(255,255,255,0.1)' : '#f3f4f6',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
    inputBg: darkMode ? 'rgba(255,255,255,0.06)' : '#ffffff',
    inputBorder: darkMode ? 'rgba(255,255,255,0.2)' : '#d1d5db',
  };

  const statusColor = { high: '#22c55e', medium: '#eab308', low: '#ef4444' };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  const completedRuns = evaluations.map((e) => e.latest_run).filter((r) => r && r.status === 'complete');
  const avgScore = completedRuns.length
    ? completedRuns.reduce((sum, r) => sum + (r.average_score || 0), 0) / completedRuns.length
    : null;
  const samplesEvaluated = completedRuns.reduce((sum, r) => sum + (r.samples_evaluated || 0), 0);

  const inputStyle = {
    padding: '8px 12px', borderRadius: '8px', fontSize: '14px',
    background: colors.inputBg, border: `1px solid ${colors.inputBorder}`, color: colors.textPrimary,
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold" style={{ color: colors.textPrimary }}>Evaluations</h1>
          <p className="text-sm mt-1" style={{ color: colors.textSecondary }}>
            Score outputs with LLM-as-judge, rule-based checks, or custom criteria
          </p>
        </div>
        <button
          onClick={() => setShowForm(!showForm)}
          className="px-4 py-2 bg-red-500 text-white rounded-lg text-sm font-medium hover:bg-red-600 transition-colors"
        >
          {showForm ? 'Cancel' : 'New Evaluation'}
        </button>
      </div>

      {loadError && (
        <div className="p-3 rounded-lg text-sm" style={{ background: darkMode ? 'rgba(239,68,68,0.1)' : '#fef2f2', color: '#ef4444' }}>
          Failed to load evaluations: {loadError}
        </div>
      )}

      {/* New Evaluation form */}
      {showForm && (
        <form
          onSubmit={handleCreate}
          className="rounded-xl border p-5 space-y-4"
          style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}
        >
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>Agent</label>
              <select
                required
                value={form.agent_id}
                onChange={(e) => setForm({ ...form, agent_id: e.target.value })}
                style={{ ...inputStyle, width: '100%' }}
              >
                <option value="">Select agent…</option>
                {agents.map((agent) => (
                  <option key={agent.id} value={agent.id}>{agent.name}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>Name</label>
              <input
                required
                type="text"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                placeholder="Response Quality"
                style={{ ...inputStyle, width: '100%' }}
              />
            </div>
            <div>
              <label className="block text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>Sample size</label>
              <input
                type="number" min="1" max="100"
                value={form.sample_size}
                onChange={(e) => setForm({ ...form, sample_size: e.target.value })}
                style={{ ...inputStyle, width: '100%' }}
              />
            </div>
          </div>

          <div>
            <label className="block text-xs uppercase tracking-wide mb-2" style={{ color: colors.textMuted }}>Rule-based criteria</label>
            <div className="flex flex-wrap gap-3">
              {RULE_CRITERIA.map((criterion) => (
                <label key={criterion.key} className="flex items-center gap-2 text-sm" style={{ color: colors.textPrimary }}>
                  <input
                    type="checkbox"
                    checked={form.criteria.includes(criterion.key)}
                    onChange={(e) => setForm({
                      ...form,
                      criteria: e.target.checked
                        ? [...form.criteria, criterion.key]
                        : form.criteria.filter((k) => k !== criterion.key),
                    })}
                  />
                  {criterion.label}
                </label>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>
                Must contain (optional pattern)
              </label>
              <input
                type="text"
                value={form.containsPattern}
                onChange={(e) => setForm({ ...form, containsPattern: e.target.value })}
                placeholder="e.g. password reset"
                style={{ ...inputStyle, width: '100%' }}
              />
            </div>
            <div>
              <label className="block text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>
                LLM judge criterion (optional, needs provider credentials)
              </label>
              <input
                type="text"
                value={form.llmJudgePrompt}
                onChange={(e) => setForm({ ...form, llmJudgePrompt: e.target.value })}
                placeholder="e.g. Is the answer helpful and accurate?"
                style={{ ...inputStyle, width: '100%' }}
              />
            </div>
          </div>

          {formError && <div className="text-sm text-red-500">{formError}</div>}

          <button
            type="submit"
            disabled={isSubmitting}
            className="px-4 py-2 bg-red-500 text-white rounded-lg text-sm font-medium hover:bg-red-600 transition-colors disabled:opacity-50"
          >
            {isSubmitting ? 'Creating & running…' : 'Create & Run'}
          </button>
        </form>
      )}

      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="rounded-xl p-5 border shadow-sm" style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}>
          <div className="text-sm mb-1" style={{ color: colors.textSecondary }}>Total Evaluations</div>
          <div className="text-3xl font-bold" style={{ color: colors.textPrimary }}>{evaluations.length}</div>
        </div>
        <div className="rounded-xl p-5 border shadow-sm" style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}>
          <div className="text-sm mb-1" style={{ color: colors.textSecondary }}>Average Score</div>
          <div className="text-3xl font-bold" style={{ color: avgScore == null ? colors.textMuted : statusColor[scoreStatus(avgScore)] }}>
            {avgScore == null ? '—' : `${(avgScore * 100).toFixed(0)}%`}
          </div>
        </div>
        <div className="rounded-xl p-5 border shadow-sm" style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}>
          <div className="text-sm mb-1" style={{ color: colors.textSecondary }}>Samples Evaluated</div>
          <div className="text-3xl font-bold" style={{ color: colors.textPrimary }}>{samplesEvaluated}</div>
        </div>
      </div>

      {/* Evaluations List */}
      <div className="space-y-4">
        {evaluations.map((evaluation) => {
          const run = evaluation.latest_run;
          const isExpanded = expandedEval === evaluation.id;
          return (
            <div
              key={evaluation.id}
              className="rounded-xl border shadow-sm overflow-hidden"
              style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}
            >
              <div
                className="flex items-center justify-between p-4 cursor-pointer"
                onClick={() => setExpandedEval(isExpanded ? null : evaluation.id)}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <span className="px-2 py-1 text-xs font-medium bg-purple-100 text-purple-700 rounded flex-shrink-0">EVALUATION</span>
                  <span className="font-medium truncate" style={{ color: colors.textPrimary }}>{evaluation.name}</span>
                  <span className="text-sm truncate" style={{ color: colors.textSecondary }}>{evaluation.agent?.name}</span>
                </div>
                <div className="flex items-center gap-4 flex-shrink-0 text-sm" style={{ color: colors.textSecondary }}>
                  {run?.status === 'failed' && <span className="text-red-500">failed</span>}
                  {run?.status === 'complete' && run.average_score != null && (
                    <span style={{ color: statusColor[scoreStatus(run.average_score)], fontWeight: 600 }}>
                      {(run.average_score * 100).toFixed(0)}%
                    </span>
                  )}
                  <span style={{ color: colors.textMuted }}>{timeAgo(run?.completed_at || evaluation.created_at)}</span>
                </div>
              </div>

              {isExpanded && (
                <div className="border-t" style={{ borderColor: colors.cardBorder }}>
                  {run?.status === 'failed' ? (
                    <div className="p-4 text-sm text-red-500">{run.error_message}</div>
                  ) : run?.scores ? (
                    <div className="p-4 space-y-3">
                      {Object.entries(run.scores).map(([label, score]) => (
                        <div key={label} className="flex items-center gap-4">
                          <div className="w-32 text-sm truncate" style={{ color: colors.textSecondary }}>{label.replace(/_/g, ' ')}</div>
                          {score.skipped ? (
                            <div className="flex-1 text-xs italic" style={{ color: colors.textMuted }} title={score.reason}>
                              skipped — {score.reason}
                            </div>
                          ) : (
                            <>
                              <div className="flex-1 h-2 rounded-full overflow-hidden" style={{ background: colors.trackBg }}>
                                <div
                                  className="h-full rounded-full transition-all"
                                  style={{ width: `${score.score * 100}%`, background: statusColor[scoreStatus(score.score)] }}
                                />
                              </div>
                              <div
                                className="w-12 text-sm font-medium text-right"
                                style={{ color: statusColor[scoreStatus(score.score)] }}
                                title={`min ${score.min} · max ${score.max} · ${score.passed}/${score.total} passed`}
                              >
                                {score.score.toFixed(2)}
                              </div>
                            </>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="p-4 text-sm" style={{ color: colors.textMuted }}>No runs yet</div>
                  )}

                  {/* Details */}
                  <div className="p-4 grid grid-cols-2 md:grid-cols-5 gap-4 text-sm" style={{ background: colors.innerBg }}>
                    <div>
                      <div style={{ color: colors.textMuted }}>Judge</div>
                      <div className="font-medium" style={{ color: colors.textPrimary }}>
                        {evaluation.judge_kind === 'llm' ? (evaluation.judge_model || 'LLM judge') : 'Rule-based'}
                      </div>
                    </div>
                    <div className="col-span-2">
                      <div style={{ color: colors.textMuted }}>Criteria</div>
                      <div className="font-medium truncate" style={{ color: colors.textPrimary }}>
                        {(evaluation.criteria || []).map((c) => c.key).join(', ')}
                      </div>
                    </div>
                    <div>
                      <div style={{ color: colors.textMuted }}>Samples</div>
                      <div className="font-medium" style={{ color: colors.textPrimary }}>
                        {run ? `${run.samples_passed} / ${run.samples_evaluated} passed` : '—'}
                      </div>
                    </div>
                    <div className="flex items-end justify-end">
                      <button
                        onClick={(e) => { e.stopPropagation(); handleRun(evaluation.id); }}
                        disabled={runningId === evaluation.id}
                        className="px-3 py-1.5 text-sm bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors disabled:opacity-50"
                      >
                        {runningId === evaluation.id ? 'Running…' : 'Run again'}
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {evaluations.length === 0 && !showForm && (
        <div className="text-center py-12 rounded-xl border" style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}>
          <div className="text-lg" style={{ color: colors.textMuted }}>No evaluations yet</div>
          <p className="text-sm mt-2" style={{ color: colors.textSecondary }}>Create an evaluation to start scoring agent outputs</p>
        </div>
      )}
    </div>
  );
}
