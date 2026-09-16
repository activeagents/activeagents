import React, { useState } from 'react';
import { Button, MicroLabel, MONO } from './ui';

// Creating an evaluation: which agent, which criteria, and whether a judge
// model defines or scores them. Submitting creates the evaluation and runs it
// once, so the list always has a first run to show.

const RULE_CRITERIA = [
  { type: 'response_present', key: 'response_present', label: 'Response present', config: {} },
  { type: 'min_length', key: 'response_length', label: 'Response length ≥ 40 chars', config: { chars: 40 } },
  { type: 'max_latency_ms', key: 'latency', label: 'Latency ≤ 5s', config: { ms: 5000 } },
  { type: 'token_budget', key: 'token_budget', label: 'Output ≤ 1000 tokens', config: { output_tokens: 1000 } },
];

// Scored from the agent's telemetry traces (aggregates over the last 7
// days), not from sampled generations.
const TELEMETRY_CRITERIA = [
  { type: 'trace_error_rate', key: 'trace_error_rate', label: 'Trace error rate ≤ 5% (telemetry, 7d)', config: { max_error_rate: 5, window_hours: 168 } },
  { type: 'trace_latency', key: 'trace_latency', label: 'Avg trace latency ≤ 5s (telemetry, 7d)', config: { max_avg_ms: 5000, window_hours: 168 } },
];

const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content;

export default function EvaluationForm({ agents, agentId, colors, onCreated, onCancel }) {
  const [form, setForm] = useState({
    agent_id: agentId ? String(agentId) : '',
    name: '',
    sample_size: 20,
    criteria: RULE_CRITERIA.map((criterion) => criterion.key),
    containsPattern: '',
    llmJudgePrompt: '',
    judgeKind: 'manual',
    judgeModel: '',
    compareModels: '',
  });
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const update = (patch) => setForm((prev) => ({ ...prev, ...patch }));
  const toggleCriterion = (key, checked) =>
    update({ criteria: checked ? [...form.criteria, key] : form.criteria.filter((k) => k !== key) });

  const buildCriteria = () => {
    const criteria = [...RULE_CRITERIA, ...TELEMETRY_CRITERIA]
      .filter((criterion) => form.criteria.includes(criterion.key))
      .map(({ key, type, config }) => ({ key, type, config }));
    if (form.containsPattern.trim()) {
      criteria.push({ key: 'contains', type: 'contains', config: { pattern: form.containsPattern.trim() } });
    }
    if (form.llmJudgePrompt.trim()) {
      criteria.push({ key: 'quality', type: 'llm_judge', config: { prompt: form.llmJudgePrompt.trim() } });
    }
    return criteria;
  };

  const submit = async (event) => {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      const response = await fetch('/api/evaluations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrfToken() },
        body: JSON.stringify({
          evaluation: {
            agent_id: form.agent_id,
            name: form.name,
            sample_size: form.sample_size,
            judge_kind: form.judgeKind === 'judge_defined'
              ? 'judge_defined'
              : (form.llmJudgePrompt.trim() ? 'llm' : 'rules'),
            judge_model: form.judgeModel.trim() || undefined,
            compare_models: form.compareModels.split(',').map((m) => m.trim()).filter(Boolean),
            criteria: form.judgeKind === 'judge_defined' ? [] : buildCriteria(),
          },
        }),
      });
      // A non-JSON body (an HTML error page, a sign-in redirect) used to
      // surface as "Unexpected token <" in the form.
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error((data.errors || [data.error]).filter(Boolean).join(', ') || `Failed to create evaluation (HTTP ${response.status})`);
      }
      onCreated(data.evaluation);
    } catch (submitError) {
      setError(submitError.message);
    } finally {
      setSubmitting(false);
    }
  };

  const field = {
    padding: '7px 10px',
    borderRadius: '8px',
    fontSize: '13px',
    width: '100%',
    boxSizing: 'border-box',
    background: colors.inputBg,
    border: `1px solid ${colors.inputBorder}`,
    color: colors.textPrimary,
  };
  const label = (text) => (
    <MicroLabel colors={colors} style={{ display: 'block', marginBottom: '6px', color: colors.textMuted, fontSize: '10px' }}>{text}</MicroLabel>
  );
  const checkbox = (criterion) => (
    <label key={criterion.key} style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', color: colors.textPrimary }}>
      <input
        type="checkbox"
        checked={form.criteria.includes(criterion.key)}
        onChange={(event) => toggleCriterion(criterion.key, event.target.checked)}
        style={{ accentColor: '#ef4444' }}
      />
      {criterion.label}
    </label>
  );

  return (
    <form
      onSubmit={submit}
      style={{
        background: colors.cardBg,
        border: `1px solid ${colors.cardBorder}`,
        borderRadius: '12px',
        padding: '16px 20px',
        display: 'flex',
        flexDirection: 'column',
        gap: '14px',
      }}
    >
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '12px' }}>
        <div>
          {label('Agent')}
          <select
            required
            disabled={!!agentId}
            value={form.agent_id}
            onChange={(event) => update({ agent_id: event.target.value })}
            style={{ ...field, opacity: agentId ? 0.7 : 1 }}
          >
            {!agentId && <option value="">Select agent…</option>}
            {agents.map((agent) => (
              <option key={agent.id} value={agent.id}>{agent.name}</option>
            ))}
          </select>
        </div>
        <div>
          {label('Name')}
          <input required type="text" value={form.name} onChange={(event) => update({ name: event.target.value })} placeholder="Response quality" style={field} />
        </div>
        <div>
          {label('Sample size')}
          <input type="number" min="1" max="100" value={form.sample_size} onChange={(event) => update({ sample_size: event.target.value })} style={{ ...field, fontFamily: MONO }} />
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '12px' }}>
        <div>
          {label('KPI definition')}
          <select value={form.judgeKind} onChange={(event) => update({ judgeKind: event.target.value })} style={field}>
            <option value="manual">Manual criteria</option>
            <option value="judge_defined">Judge defines KPIs from agent goals</option>
          </select>
        </div>
        <div>
          {label('Judge model (optional)')}
          <input type="text" value={form.judgeModel} onChange={(event) => update({ judgeModel: event.target.value })} placeholder="e.g. claude-opus-5" style={{ ...field, fontFamily: MONO }} />
        </div>
        <div>
          {label('Compare models (optional, comma-separated)')}
          <input type="text" value={form.compareModels} onChange={(event) => update({ compareModels: event.target.value })} placeholder="e.g. claude-haiku-4-5, qwen3:8b" style={{ ...field, fontFamily: MONO }} />
        </div>
      </div>

      {form.judgeKind === 'judge_defined' ? (
        <p style={{ fontSize: '12px', color: colors.textSecondary, margin: 0 }}>
          On the first run the judge reads the agent's instructions and recent interactions,
          defines 3–6 KPIs, then scores samples against them. KPIs persist so later runs
          (and model cohorts) stay comparable.
        </p>
      ) : (
        <>
          <div>
            {label('Rule-based criteria (sampled generations)')}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px' }}>{RULE_CRITERIA.map(checkbox)}</div>
          </div>
          <div>
            {label('Telemetry criteria (trace aggregates)')}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px' }}>{TELEMETRY_CRITERIA.map(checkbox)}</div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '12px' }}>
            <div>
              {label('Must contain (optional pattern)')}
              <input type="text" value={form.containsPattern} onChange={(event) => update({ containsPattern: event.target.value })} placeholder="e.g. password reset" style={{ ...field, fontFamily: MONO }} />
            </div>
            <div>
              {label('LLM judge criterion (optional, needs provider credentials)')}
              <input type="text" value={form.llmJudgePrompt} onChange={(event) => update({ llmJudgePrompt: event.target.value })} placeholder="e.g. Is the answer helpful and accurate?" style={field} />
            </div>
          </div>
        </>
      )}

      {error && <div style={{ fontSize: '13px', color: '#dc2626' }}>{error}</div>}

      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
        <Button type="submit" variant="primary" colors={colors} disabled={submitting}>
          {submitting ? 'Creating & running…' : 'Create & Run'}
        </Button>
        {onCancel && <Button variant="secondary" colors={colors} onClick={onCancel}>Cancel</Button>}
      </div>
    </form>
  );
}
