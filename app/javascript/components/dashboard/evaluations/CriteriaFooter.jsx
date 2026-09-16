import React from 'react';
import { Mono, MONO } from './ui';
import { criterionGroup, criterionLabel, criterionExpectation, judgeLabel } from './criteria';

// The evaluation's standing configuration, as one mono line: who judges,
// which criteria, and the API call that re-scores it. Telemetry and judge
// criteria carry a source tag because they are scored from different data
// than the sampled generations.
export default function CriteriaFooter({ evaluation, colors, sem, onDelete, deleting }) {
  const criteria = evaluation.criteria || [];
  const sourceTag = (text, testId, title) => (
    <Mono
      colors={colors}
      testId={testId}
      size={10}
      title={title}
      style={{ textTransform: 'uppercase', letterSpacing: '0.04em', marginLeft: '2px' }}
    >
      {text}
    </Mono>
  );

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap', rowGap: '4px' }}>
        <Mono colors={colors}>judge</Mono>
        <Mono colors={colors} color={colors.textCell} weight={600}>{judgeLabel(evaluation)}</Mono>
        <Mono colors={colors} style={{ marginLeft: '8px' }}>criteria</Mono>
        {criteria.length === 0 && <Mono colors={colors}>defined by the judge on the first run</Mono>}
        {criteria.map((criterion, index) => (
          <React.Fragment key={criterion.key || index}>
            {index > 0 && <Mono colors={colors}>·</Mono>}
            <Mono colors={colors} color={colors.textCell} title={criterionExpectation(criterion)}>
              {criterionLabel(criterion)}
            </Mono>
            {criterionGroup(criterion) === 'telemetry' &&
              sourceTag('telemetry', 'score-source-telemetry', "Scored from the agent's telemetry traces, not from sampled generations")}
            {criterionGroup(criterion) === 'judge' &&
              sourceTag('judge', undefined, 'Scored by the judge model; needs provider credentials')}
          </React.Fragment>
        ))}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px', flexWrap: 'wrap' }}>
        <Mono colors={colors} title="Re-score this evaluation from the API">POST /api/evaluations/{evaluation.id}/run</Mono>
        {onDelete && (
          <button
            type="button"
            onClick={(event) => { event.stopPropagation(); onDelete(); }}
            disabled={deleting}
            title="Delete this evaluation and its runs"
            style={{ background: 'none', border: 'none', cursor: deleting ? 'wait' : 'pointer', fontFamily: MONO, fontSize: '11px', color: sem.error, padding: 0 }}
          >
            {deleting ? 'Deleting…' : 'Delete evaluation'}
          </button>
        )}
      </div>
    </div>
  );
}
