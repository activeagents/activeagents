import React from 'react';
import { useTheme } from '../../contexts/ThemeContext';
import { TYPOGRAPHY } from '../../utils/designTokens';
import ContextMeter from './ContextMeter';
import {
  formatTokens,
  formatPercent,
  contextColors,
  segmentRamp,
  pressureState,
  STATE_COLOR,
  STATE_GLYPH,
  LARGE_TURN_TOKENS,
  hatch,
  WARN_AT,
  CRITICAL_AT,
} from '../../utils/contextUtilization';

const microLabel = (colors) => ({
  fontFamily: TYPOGRAPHY.mono,
  fontSize: 10,
  fontWeight: 600,
  letterSpacing: '0.06em',
  textTransform: 'uppercase',
  color: colors.textMuted,
});

const card = (colors) => ({
  background: colors.card,
  border: `1px solid ${colors.border}`,
  borderRadius: 12,
  padding: '12px 14px',
});

/**
 * Cumulative window occupancy across an interaction's turns, against the
 * model's limit with the 75% and 90% thresholds drawn in.
 *
 * Every point is measured — occupancy after turn n is that generation's
 * `input_tokens + output_tokens`, which is exactly what the next call
 * inherits. The shape is the thing to read: a straight ramp is a
 * conversation growing normally, a step is a tool result that landed hard.
 */
export function ContextGrowthChart({ turns = [], limit, peak, height = 96, darkMode: darkModeOverride }) {
  const theme = useTheme();
  const darkMode = darkModeOverride != null ? darkModeOverride : theme.darkMode;
  const colors = contextColors(darkMode);
  if (!turns.length || !limit) return null;

  const H = 40;
  const top = 2;
  const bottom = 38;
  const span = bottom - top;
  const y = (tokens) => bottom - Math.min(1, tokens / limit) * span;
  const x = (index) => (turns.length === 1 ? 100 : (index / (turns.length - 1)) * 100);

  const points = turns.map((turn, i) => `${x(i)},${y(turn.occupancy)}`).join(' ');
  const area = `0,${bottom} ${points} 100,${bottom}`;
  const last = turns[turns.length - 1];
  const state = pressureState(last.occupancy / limit);
  const lineColor = STATE_COLOR[state] || colors.tokenIn;

  return (
    <div style={card(colors)}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 8, flexWrap: 'wrap' }}>
        <span style={microLabel(colors)}>Context growth</span>
        <span style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 11, color: colors.textMuted }}>
          {turns.length} turns · {formatTokens(last.occupancy)} now
          {peak && peak.tokens > last.occupancy && ` · peak ${formatTokens(peak.tokens)} (${formatPercent(peak.pct)})`}
        </span>
      </div>

      <div style={{ position: 'relative' }}>
        <svg
          viewBox={`0 0 100 ${H}`}
          preserveAspectRatio="none"
          role="img"
          aria-label={`Context growth across ${turns.length} turns, ending at ${formatTokens(last.occupancy)} of ${formatTokens(limit)}`}
          style={{ width: '100%', height, display: 'block' }}
        >
          {/* Threshold bands — the same 75/90 semantics as the meter, so
              the curve entering the amber band means what the amber meter
              means. */}
          <rect x="0" y={y(limit)} width="100" height={y(limit * CRITICAL_AT) - y(limit)} fill={colors.error} opacity="0.12" />
          <rect
            x="0"
            y={y(limit * CRITICAL_AT)}
            width="100"
            height={y(limit * WARN_AT) - y(limit * CRITICAL_AT)}
            fill={colors.warning}
            opacity="0.12"
          />
          <polygon points={area} fill={lineColor} opacity="0.12" />
          <polyline
            points={points}
            fill="none"
            stroke={lineColor}
            strokeWidth="1.5"
            vectorEffect="non-scaling-stroke"
          />
          {/* A truncated turn is where the window actually cost something. */}
          {turns.map((turn, i) =>
            turn.truncated ? (
              <line
                key={turn.generation_id || i}
                x1={x(i)}
                y1={top}
                x2={x(i)}
                y2={bottom}
                stroke={colors.error}
                strokeWidth="1"
                strokeDasharray="2 2"
                vectorEffect="non-scaling-stroke"
              />
            ) : null
          )}
        </svg>

        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'space-between',
            pointerEvents: 'none',
            fontFamily: TYPOGRAPHY.mono,
            fontSize: 9,
            color: colors.textMuted,
          }}
        >
          <span>{formatTokens(limit)}</span>
          <span>0</span>
        </div>
      </div>
    </div>
  );
}

/**
 * What each turn added to the window — the "which turn ate the context"
 * view. `added` is measured, not estimated:
 *
 *   input_tokens[n] - (input_tokens[n-1] + output_tokens[n-1])
 *
 * which is exactly the user message plus tool results that landed between
 * two calls. A negative bar is real: it means history was trimmed or the
 * stream restarted, and hiding it would misrepresent the run.
 */
export function ContextTurnDeltas({ turns = [], limit, maxRows = 12, darkMode: darkModeOverride }) {
  const theme = useTheme();
  const darkMode = darkModeOverride != null ? darkModeOverride : theme.darkMode;
  const colors = contextColors(darkMode);
  if (!turns.length) return null;

  const rows = turns.slice(-maxRows);
  const hidden = turns.length - rows.length;
  const scale = Math.max(1, ...rows.map((turn) => Math.abs(turn.added)));

  return (
    <div style={card(colors)}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 8, flexWrap: 'wrap' }}>
        <span style={microLabel(colors)}>Added per turn</span>
        <span style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 11, color: colors.textMuted }}>
          measured from generation deltas
          {hidden > 0 && ` · showing last ${rows.length} of ${turns.length}`}
        </span>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {rows.map((turn) => {
          const heavy = turn.added >= LARGE_TURN_TOKENS;
          const reclaimed = turn.added < 0;
          const width = Math.min(100, (Math.abs(turn.added) / scale) * 100);
          const barColor = reclaimed ? colors.textMuted : heavy ? colors.warning : colors.tokenIn;

          return (
            <div
              key={turn.generation_id || turn.index}
              style={{ display: 'flex', alignItems: 'center', gap: 8, fontFamily: TYPOGRAPHY.mono, fontSize: 11 }}
              title={`Turn ${turn.index + 1}${turn.model ? ` · ${turn.model}` : ''} · occupancy after ${formatTokens(turn.occupancy)}`}
            >
              <span style={{ width: 26, color: colors.textMuted, flexShrink: 0 }}>#{turn.index + 1}</span>
              <div style={{ flex: 1, height: 8, background: colors.rail, borderRadius: 999, overflow: 'hidden', minWidth: 40 }}>
                <div
                  style={{
                    width: `${width}%`,
                    height: '100%',
                    borderRadius: 999,
                    background: barColor,
                    backgroundImage: reclaimed
                      ? hatch(darkMode ? 'rgba(0,0,0,0.35)' : 'rgba(255,255,255,0.55)')
                      : undefined,
                  }}
                />
              </div>
              <span
                style={{
                  width: 62,
                  textAlign: 'right',
                  flexShrink: 0,
                  color: heavy ? colors.warningText : reclaimed ? colors.textMuted : colors.textCell,
                  fontWeight: heavy ? 600 : 400,
                }}
              >
                {reclaimed ? '' : '+'}{formatTokens(turn.added)}
              </span>
              <span style={{ width: 54, textAlign: 'right', flexShrink: 0, color: colors.textMuted }}>
                {limit ? formatPercent(turn.occupancy / limit) : ''}
              </span>
              <span style={{ width: 16, flexShrink: 0, color: colors.error }}>
                {turn.truncated ? '[!]' : ''}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/**
 * Headroom expressed the way it is actually consumed: how many more turns
 * of this size the window can take. A percentage tells an operator the
 * window is 68% full; this tells them they have four turns left, which is
 * the number that changes what they do next.
 */
export function ContextHeadroom({ context, darkMode: darkModeOverride }) {
  const theme = useTheme();
  const darkMode = darkModeOverride != null ? darkModeOverride : theme.darkMode;
  const colors = contextColors(darkMode);
  const projection = context?.projection;
  if (!projection || !context.limit) return null;

  const remaining = projection.turns_remaining;
  const tone = remaining <= 1 ? colors.error : remaining <= 3 ? colors.warning : null;
  // Runway pips: one per projected remaining turn, capped so a long
  // conversation does not render a hundred boxes.
  const pips = Math.min(remaining, 12);

  return (
    <div style={{ ...card(colors), border: `1px solid ${tone || colors.border}` }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, flexWrap: 'wrap' }}>
        <span style={microLabel(colors)}>Headroom</span>
        <span style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 11, color: colors.textMuted }}>
          averaging {formatTokens(projection.avg_tokens_per_turn)} per turn over the last {projection.sampled_turns}
        </span>
        <span
          style={{
            marginLeft: 'auto',
            fontFamily: TYPOGRAPHY.mono,
            fontSize: 12,
            fontWeight: 600,
            color: tone || colors.textPrimary,
          }}
        >
          {tone && `${STATE_GLYPH[remaining <= 1 ? 'critical' : 'warning']} `}
          {remaining === 0 ? 'no room for another turn' : `~${remaining} turn${remaining === 1 ? '' : 's'} left`}
        </span>
      </div>

      <div style={{ display: 'flex', gap: 3, marginTop: 10 }} aria-hidden="true">
        {Array.from({ length: 12 }, (_, i) => (
          <div
            key={i}
            style={{
              flex: 1,
              height: 6,
              borderRadius: 2,
              background: i < pips ? (tone || colors.tokenIn) : colors.rail,
              opacity: i < pips ? 1 - (i * 0.05) : 1,
            }}
          />
        ))}
      </div>
      {remaining > 12 && (
        <div style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 10, color: colors.textMuted, marginTop: 4 }}>
          runway capped at 12 — {remaining} projected
        </div>
      )}
    </div>
  );
}

/**
 * Per-source share of the window as a stacked strip with its own scale —
 * the meter shows sources against the *limit*, this shows them against
 * each other, which is the comparison you want when deciding what to trim.
 */
export function ContextSourceShare({ segments = [], darkMode: darkModeOverride }) {
  const theme = useTheme();
  const darkMode = darkModeOverride != null ? darkModeOverride : theme.darkMode;
  const colors = contextColors(darkMode);
  const ramp = segmentRamp(darkMode);
  const total = segments.reduce((sum, segment) => sum + segment.tokens, 0);
  if (!total) return null;

  return (
    <div style={card(colors)}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 8 }}>
        <span style={microLabel(colors)}>Share of used</span>
        <span style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 11, color: colors.textMuted }}>
          {formatTokens(total)} attributed
        </span>
      </div>
      <div style={{ display: 'flex', height: 22, borderRadius: 6, overflow: 'hidden', background: colors.rail }}>
        {segments.map((segment) => {
          const share = segment.tokens / total;
          return (
            <div
              key={segment.key}
              title={`${segment.label} · ${formatTokens(segment.tokens)} · ${formatPercent(share, 1)} of used`}
              style={{
                width: `${share * 100}%`,
                flexShrink: 0,
                background: ramp[segment.key] || ramp.unattributed,
                backgroundImage: segment.key === 'unattributed'
                  ? hatch(darkMode ? 'rgba(0,0,0,0.35)' : 'rgba(255,255,255,0.55)')
                  : undefined,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontFamily: TYPOGRAPHY.mono,
                fontSize: 9,
                color: '#ffffff',
                overflow: 'hidden',
                whiteSpace: 'nowrap',
              }}
            >
              {share > 0.12 ? formatPercent(share) : ''}
            </div>
          );
        })}
      </div>
    </div>
  );
}

/**
 * The full context story for one interaction: how full, what filled it,
 * how it got there, and how much longer it can run.
 */
export default function ContextUtilizationPanel({ context, label = 'Context window', dense = false, darkMode }) {
  if (!context || !context.limit) return null;

  const turns = context.turns || [];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <ContextMeter context={context} label={label} defaultOpen={!dense} darkMode={darkMode} />
      {!dense && <ContextSourceShare segments={context.segments} darkMode={darkMode} />}
      {turns.length > 1 && (
        <ContextGrowthChart turns={turns} limit={context.limit} peak={context.peak} height={dense ? 72 : 96} darkMode={darkMode} />
      )}
      {turns.length > 0 && <ContextTurnDeltas turns={turns} limit={context.limit} maxRows={dense ? 6 : 12} darkMode={darkMode} />}
      <ContextHeadroom context={context} darkMode={darkMode} />
    </div>
  );
}
