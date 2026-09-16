import React, { useState } from 'react';
import { Badge, Button, Chip, MicroLabel, Mono, Bar, Spinner, toneFor, toneColor, semanticFor, MONO } from './ui';
import CriteriaFooter from './CriteriaFooter';
import {
  CRITERION_GROUPS, PASS_THRESHOLD, criterionGroup, criterionLabel, criterionExpectation, criterionEntries,
  cellStats, findCriterion, runModels, runCohorts, modelScorecard, fixItems, timeAgo, formatMs, formatTokens,
  runLabel, navigateTo, truncate,
} from './criteria';

// One evaluation run, opened from the runs list: a scorecard per model
// cohort, the judge's verdict when there was one, the criteria matrix
// (criteria × models) and the follow-ups the run's own data asks for.

const linkStyle = (colors, sem) => ({
  background: 'none',
  border: 'none',
  padding: 0,
  cursor: 'pointer',
  fontFamily: MONO,
  fontSize: '12px',
  color: sem.info,
});

function ModelScorecard({ run, model, cohort, winner, colors, sem, darkMode }) {
  const card = modelScorecard(run, model);
  const samples = cohort?.samples ?? (model == null ? run.samples_evaluated : null);
  const passed = cohort?.passed ?? (model == null ? run.samples_passed : null);
  const bySamples = passed != null && samples > 0;
  const fraction = bySamples ? passed / samples : card.avg;
  const color = toneColor(toneFor(fraction), sem, colors);

  return (
    <div
      data-testid="model-scorecard"
      style={{
        background: colors.cardBg,
        border: `1px solid ${colors.cardBorder}`,
        borderRadius: '12px',
        padding: '14px 16px',
        display: 'flex',
        flexDirection: 'column',
        gap: '10px',
        minWidth: 0,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
        <span style={{ fontSize: '14px', fontWeight: 700, color: colors.textPrimary, fontFamily: MONO }}>
          {model || 'all samples'}
        </span>
        {cohort?.provider && <Mono colors={colors}>{cohort.provider}</Mono>}
        {winner && winner === model && <Badge tone="info" darkMode={darkMode}>judge's pick</Badge>}
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: '8px' }}>
        <span style={{ fontSize: '26px', fontWeight: 700, fontFamily: MONO, color, lineHeight: 1 }}>
          {bySamples ? `${passed}/${samples}` : card.avg != null ? card.avg.toFixed(2) : '—'}
        </span>
        <span style={{ fontSize: '13px', color: colors.textSecondary }}>
          {bySamples ? 'samples passed' : card.avg != null ? 'mean score' : 'nothing scored'}
        </span>
      </div>
      <Bar fraction={fraction} color={color} colors={colors} />
      <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
        <Mono colors={colors}>
          score <Mono colors={colors} color={colors.textPrimary} weight={600}>{card.avg != null ? card.avg.toFixed(3) : '—'}</Mono>
        </Mono>
        <Mono colors={colors}>
          criteria <Mono colors={colors} color={colors.textPrimary} weight={600}>{card.cleared}/{card.scored}</Mono>
        </Mono>
        {cohort?.avg_duration_ms != null && (
          <Mono colors={colors}>
            latency <Mono colors={colors} color={colors.textPrimary} weight={600}>{formatMs(cohort.avg_duration_ms)}</Mono>
          </Mono>
        )}
        {cohort?.input_tokens != null && (
          <Mono colors={colors}>
            <span style={{ color: sem.tokenIn }}>in</span>{' '}
            <Mono colors={colors} color={colors.textPrimary} weight={600}>{formatTokens(cohort.input_tokens)}</Mono>
            {' · '}
            <span style={{ color: sem.tokenOut }}>out</span>{' '}
            <Mono colors={colors} color={colors.textPrimary} weight={600}>{formatTokens(cohort.output_tokens)}</Mono>
          </Mono>
        )}
      </div>
      {(card.below > 0 || card.skipped > 0) && (
        <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
          {card.below > 0 && <Badge tone="error" darkMode={darkMode}>below pass mark ×{card.below}</Badge>}
          {card.skipped > 0 && <Badge tone="warning" darkMode={darkMode}>skipped ×{card.skipped}</Badge>}
        </div>
      )}
    </div>
  );
}

function ScoreCell({ stats, colors, sem }) {
  if (!stats) return <Mono colors={colors}>—</Mono>;
  if (stats.skipped) {
    return (
      <div>
        <Mono colors={colors} color={colors.textCell} size={12} weight={700}>[-] skipped</Mono>
        <Mono colors={colors} style={{ display: 'block', marginTop: '2px', whiteSpace: 'normal' }} title={stats.reason}>
          {truncate(stats.reason, 90)}
        </Mono>
      </div>
    );
  }
  const score = Number(stats.score);
  const color = toneColor(toneFor(score), sem, colors);
  const parts = [];
  if (stats.total != null) parts.push(`${stats.passed}/${stats.total} passed`);
  if (stats.total > 1 && stats.min != null) parts.push(`min ${Number(stats.min).toFixed(2)} · max ${Number(stats.max).toFixed(2)}`);
  if (stats.source === 'telemetry') {
    parts.push(`${stats.traces} traces · ${stats.window_hours}h`);
    const observed = stats.observed || {};
    if (observed.error_rate != null) parts.push(`observed ${observed.error_rate}% errors (${observed.errors})`);
    if (observed.avg_duration_ms != null) parts.push(`observed avg ${formatMs(observed.avg_duration_ms)}`);
  }
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
        <Mono colors={colors} color={color} size={12} weight={700}>
          {score >= PASS_THRESHOLD ? '[+]' : '[!]'} {score.toFixed(2)}
        </Mono>
        {stats.source === 'telemetry' && (
          <Mono
            colors={colors}
            testId="score-source-telemetry"
            size={10}
            title="Aggregate over the agent's telemetry traces"
            style={{ textTransform: 'uppercase', letterSpacing: '0.04em' }}
          >
            telemetry
          </Mono>
        )}
      </div>
      <Mono colors={colors} style={{ display: 'block', marginTop: '2px', whiteSpace: 'normal' }}>{parts.join(' · ')}</Mono>
    </div>
  );
}

function FixCard({ item, colors, sem, darkMode }) {
  return (
    <div
      data-testid="fix-item"
      style={{
        background: colors.cardBg,
        border: `1px solid ${colors.cardBorder}`,
        borderRadius: '12px',
        padding: '14px',
        display: 'flex',
        flexDirection: 'column',
        gap: '10px',
        minWidth: 0,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
        <Mono colors={colors} color={sem.error} weight={700} size={12}>[!]</Mono>
        <Badge tone="error" darkMode={darkMode}>{item.label}</Badge>
        <Mono colors={colors}>{item.scope}</Mono>
      </div>
      <div style={{ fontSize: '13px', lineHeight: '19px', color: colors.textCell }}>{item.text}</div>
      {item.chips?.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          <MicroLabel colors={colors} style={{ fontSize: '10px', color: colors.textMuted }}>{item.chipsLabel}</MicroLabel>
          <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
            {item.chips.map((chip) => <Chip key={chip} colors={colors}>{chip}</Chip>)}
          </div>
        </div>
      )}
      {item.details?.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
          {item.details.map((detail) => (
            <Mono key={detail} colors={colors} color={colors.textCell} style={{ whiteSpace: 'normal' }}>{detail}</Mono>
          ))}
        </div>
      )}
      {item.action && (
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <Button variant="secondary" size="sm" colors={colors} onClick={() => navigateTo(item.action.href)}>
            {item.action.label}
          </Button>
          <Mono colors={colors}>{item.action.hint}</Mono>
        </div>
      )}
    </div>
  );
}

export default function EvaluationRunDetail({
  evaluation, runs, runId, loading, running, onSelectRun, onRun, onClose, onOpenEvaluation, darkMode, colors,
}) {
  const sem = semanticFor(darkMode);
  const [group, setGroup] = useState('all');
  const [failedOnly, setFailedOnly] = useState(false);

  const crumb = (label, onClick) => (
    <button type="button" onClick={onClick} style={linkStyle(colors, sem)}>{label}</button>
  );

  if (!evaluation) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        <div>{crumb('Evaluations', onClose)}</div>
        <div style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', padding: '20px', fontSize: '13px', color: colors.textMuted }}>
          This evaluation is not in the list any more.
        </div>
      </div>
    );
  }

  const run = runs.find((candidate) => candidate.id === runId) || runs[0];
  const breadcrumb = (
    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
      {crumb('Evaluations', onClose)}
      <Mono colors={colors}>/</Mono>
      {crumb(evaluation.name, onOpenEvaluation)}
      <Mono colors={colors}>/</Mono>
      <Mono colors={colors} color={colors.textPrimary} weight={700} size={12}>{run ? `Run #${run.number ?? ''}` : 'Runs'}</Mono>
    </div>
  );

  if (!run) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {breadcrumb}
        {loading ? <Spinner /> : (
          <div style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', padding: '20px', fontSize: '13px', color: colors.textMuted }}>
            No runs recorded yet.
          </div>
        )}
      </div>
    );
  }

  const models = runModels(run);
  const columns = models.length ? models : [null];
  const cohorts = runCohorts(run);
  const cohortFor = (model) => cohorts.find((cohort) => cohort.model === model) || (model == null ? cohorts[0] : null);
  const verdict = run.scores?._verdict;
  const missing = Array.isArray(run.scores?._missing_models) ? run.scores._missing_models : [];
  const entries = criterionEntries(run).map(([key, value]) => ({ key, value, criterion: findCriterion(evaluation, key) }));
  const countIn = (groupId) => entries.filter((entry) => criterionGroup(entry.criterion) === groupId).length;
  const presentGroups = CRITERION_GROUPS.filter((candidate) => countIn(candidate.id) > 0);
  const failing = (entry) => columns.some((model) => {
    const stats = cellStats(entry.value, model);
    return stats && (stats.skipped || (stats.score != null && stats.score < PASS_THRESHOLD));
  });
  const visible = entries.filter((entry) =>
    (group === 'all' || criterionGroup(entry.criterion) === group) && (!failedOnly || failing(entry)));
  const sections = CRITERION_GROUPS
    .map((candidate) => ({ ...candidate, rows: visible.filter((entry) => criterionGroup(entry.criterion) === candidate.id) }))
    .filter((candidate) => candidate.rows.length);
  const items = fixItems(evaluation, run);
  const when = timeAgo(run.completed_at || run.created_at);
  const passedLabel = run.status === 'complete' && run.samples_evaluated
    ? ` · ${run.samples_passed}/${run.samples_evaluated} passed`
    : '';

  const th = {
    fontFamily: MONO,
    fontSize: '10px',
    fontWeight: 600,
    letterSpacing: '0.05em',
    textTransform: 'uppercase',
    color: colors.textMuted,
    padding: '8px 12px',
    textAlign: 'left',
    verticalAlign: 'top',
    whiteSpace: 'nowrap',
  };
  const td = { padding: '10px 12px', verticalAlign: 'top' };
  const groupTd = { padding: '7px 12px', verticalAlign: 'middle' };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
      {breadcrumb}

      {/* Title row: which run, what it covered, and the run switcher. */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '12px', flexWrap: 'wrap' }}>
        <div style={{ minWidth: 0 }}>
          <h1 style={{ fontSize: '22px', fontWeight: 700, margin: 0, color: colors.textPrimary, letterSpacing: '-0.01em' }}>
            Run #{run.number ?? ''}
          </h1>
          <p style={{ fontSize: '13px', color: colors.textSecondary, margin: '4px 0 0' }}>
            {evaluation.name} · {when} · @{evaluation.agent?.name} · {runLabel(evaluation)}{passedLabel}
          </p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
          {runs.map((candidate) => (
            <Chip
              key={candidate.id}
              colors={colors}
              active={candidate.id === run.id}
              onClick={() => onSelectRun(candidate)}
              title={`${candidate.status} · ${timeAgo(candidate.completed_at || candidate.created_at)}`}
            >
              #{candidate.number ?? '?'}
            </Chip>
          ))}
          <Button variant="primary" colors={colors} disabled={running} onClick={onRun}>
            {running ? 'Running…' : 'Run again'}
          </Button>
        </div>
      </div>

      {/* One scorecard per model cohort; a failed run has nothing to score. */}
      {run.status === 'failed' ? (
        <div data-testid="run-failed" style={{ background: colors.cardBg, border: `1px solid ${sem.error}`, borderRadius: '12px', padding: '14px 16px' }}>
          <Mono colors={colors} color={sem.error} weight={700} size={12}>[!] run failed</Mono>
          <div style={{ fontSize: '13px', color: colors.textCell, marginTop: '6px', lineHeight: '19px' }}>{run.error_message}</div>
        </div>
      ) : run.status !== 'complete' ? (
        <div data-testid="run-pending" style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', padding: '14px 16px' }}>
          <Mono colors={colors} color={sem.warning} weight={700} size={12}>[~] {run.status}</Mono>
          <div style={{ fontSize: '13px', color: colors.textCell, marginTop: '6px' }}>Scores appear once the run completes.</div>
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '12px' }}>
          {columns.map((model) => (
            <ModelScorecard
              key={model || 'all'}
              run={run}
              model={model}
              cohort={cohortFor(model)}
              winner={verdict?.winner}
              colors={colors}
              sem={sem}
              darkMode={darkMode}
            />
          ))}
        </div>
      )}

      {(verdict || missing.length > 0) && (
        <div style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', padding: '12px 16px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {verdict && (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <MicroLabel colors={colors}>Verdict</MicroLabel>
                {verdict.judge && <Mono colors={colors}>judged by {verdict.judge}</Mono>}
              </div>
              <div style={{ fontSize: '13px', lineHeight: '19px', color: colors.textCell }}>
                <strong style={{ color: colors.textPrimary, fontFamily: MONO, fontSize: '12px' }}>{verdict.winner}</strong>
                {verdict.rationale ? ` · ${verdict.rationale}` : ''}
              </div>
            </>
          )}
          {missing.length > 0 && (
            <Mono colors={colors} color={sem.warning} weight={600}>[!] no generations recorded under {missing.join(', ')}</Mono>
          )}
        </div>
      )}

      {/* Criteria × models. */}
      <div style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', padding: '10px 14px', flexWrap: 'wrap' }}>
          <MicroLabel colors={colors}>Criteria</MicroLabel>
          <Chip colors={colors} active={group === 'all'} onClick={() => setGroup('all')}>All {entries.length}</Chip>
          {presentGroups.map((candidate) => (
            <Chip key={candidate.id} colors={colors} active={group === candidate.id} onClick={() => setGroup(candidate.id)}>
              {candidate.label} {countIn(candidate.id)}
            </Chip>
          ))}
          <div style={{ marginLeft: 'auto' }}>
            <Chip colors={colors} active={failedOnly} onClick={() => setFailedOnly((value) => !value)}>
              {failedOnly ? '[x]' : '[ ]'} failed only
            </Chip>
          </div>
        </div>
        <div style={{ overflowX: 'auto' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ background: colors.innerBg }}>
                <th style={{ ...th, width: '34%' }}>Criterion</th>
                <th style={th}>Expects</th>
                {columns.map((model) => (
                  <th key={model || 'score'} style={th}>
                    {model ? (
                      <>
                        <span style={{ color: colors.textPrimary, textTransform: 'none', letterSpacing: 0, fontSize: '12px' }}>{model}</span>
                        {cohortFor(model)?.provider && (
                          <span style={{ display: 'block', fontWeight: 400, textTransform: 'none', letterSpacing: 0 }}>{cohortFor(model).provider}</span>
                        )}
                      </>
                    ) : 'Score'}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {sections.map((section) => (
                <React.Fragment key={section.id}>
                  <tr style={{ background: colors.innerBg, borderTop: `1px solid ${colors.cardBorder}` }}>
                    <td style={groupTd}>
                      <span style={{ fontWeight: 700, fontSize: '13px', color: colors.textPrimary }}>{section.label}</span>
                    </td>
                    <td style={groupTd}>
                      <Mono colors={colors}>{section.rows.length} {section.rows.length === 1 ? 'criterion' : 'criteria'}</Mono>
                    </td>
                    {columns.map((model) => {
                      const scored = section.rows.filter((entry) => { const stats = cellStats(entry.value, model); return stats && stats.score != null; });
                      const cleared = scored.filter((entry) => cellStats(entry.value, model).score >= PASS_THRESHOLD).length;
                      return (
                        <td key={model || 'score'} style={groupTd}>
                          <Mono colors={colors} color={scored.length && cleared === scored.length ? sem.success : colors.textCell} weight={600}>
                            {cleared}/{scored.length} passed
                          </Mono>
                        </td>
                      );
                    })}
                  </tr>
                  {section.rows.map((entry) => (
                    <tr key={entry.key} data-testid="criterion-row" style={{ borderTop: `1px solid ${colors.cardBorder}` }}>
                      <td style={td}>
                        <Mono colors={colors} style={{ display: 'block' }}>{entry.key}</Mono>
                        <span style={{ fontSize: '13px', color: colors.textPrimary }}>{criterionLabel(entry.criterion)}</span>
                      </td>
                      <td style={td}>
                        <Chip colors={colors} title={criterionExpectation(entry.criterion)}>
                          {truncate(criterionExpectation(entry.criterion), 40)}
                        </Chip>
                      </td>
                      {columns.map((model) => (
                        <td key={model || 'score'} style={td}>
                          <ScoreCell stats={cellStats(entry.value, model)} colors={colors} sem={sem} />
                        </td>
                      ))}
                    </tr>
                  ))}
                </React.Fragment>
              ))}
              {sections.length === 0 && (
                <tr style={{ borderTop: `1px solid ${colors.cardBorder}` }}>
                  <td colSpan={2 + columns.length} style={{ padding: '16px 14px', fontSize: '13px', color: colors.textMuted }}>
                    {entries.length ? 'Nothing failed under this filter.' : 'This run recorded no criterion scores.'}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* What the run's own data asks for next. */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <MicroLabel colors={colors}>What to fix</MicroLabel>
          <Mono colors={colors}>{items.length ? `${items.length} ${items.length === 1 ? 'item' : 'items'}` : 'nothing'}</Mono>
        </div>
        {items.length ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: '12px' }}>
            {items.map((item) => <FixCard key={item.kind} item={item} colors={colors} sem={sem} darkMode={darkMode} />)}
          </div>
        ) : (
          <div style={{ background: colors.cardBg, border: `1px solid ${colors.cardBorder}`, borderRadius: '12px', padding: '12px 14px' }}>
            <Mono colors={colors} color={sem.success} weight={700} size={12}>
              [+] Every criterion cleared the {PASS_THRESHOLD.toFixed(2)} pass mark and nothing was skipped.
            </Mono>
          </div>
        )}
      </div>

      <CriteriaFooter evaluation={evaluation} colors={colors} sem={sem} />
    </div>
  );
}
