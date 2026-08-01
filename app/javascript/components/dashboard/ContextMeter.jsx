import React, { useState } from 'react';
import { useTheme } from '../../contexts/ThemeContext';
import { TYPOGRAPHY } from '../../utils/designTokens';
import {
  formatTokens,
  formatPercent,
  pressureState,
  segmentRamp,
  contextColors,
  dominantSegmentKey,
  cachedShare,
  hatch,
  STATE_COLOR,
  STATE_GLYPH,
  STATE_NOTE,
  WARN_AT,
  CRITICAL_AT,
} from '../../utils/contextUtilization';

/**
 * How full an interaction's context window is, and what is taking up the
 * space. Rendered wherever an engineer would ask "how much room is left,
 * and what do I evict?" — interaction rows, interaction detail, and the
 * expanded trace ("context at time of call").
 *
 * The header number is measured: it comes from the provider's own
 * input_tokens, not from summing the breakdown. The breakdown is an
 * estimate reconciled against that total, with whatever it cannot explain
 * shown as an explicit `unattributed` segment — so the bar always adds up
 * to the number printed above it.
 *
 * Props mirror the `context` payload from ContextUtilization:
 *   { used, limit, pct, state, segments[], cached, thinking, measured,
 *     window_known, overflow }
 */
export default function ContextMeter({
  context,
  label = 'Context window',
  compact = false,
  defaultOpen = false,
  collapsible = true,
  // The Traces waterfall renders on a permanently dark panel regardless of
  // the app theme, so surfaces can pin the palette rather than inherit it.
  darkMode: darkModeOverride,
  style,
}) {
  const theme = useTheme();
  const darkMode = darkModeOverride != null ? darkModeOverride : theme.darkMode;
  const [open, setOpen] = useState(defaultOpen);

  if (!context || !context.limit) return null;

  const colors = contextColors(darkMode);
  const ramp = segmentRamp(darkMode);
  const segments = context.segments || [];
  const used = context.used || 0;
  const limit = context.limit;
  const pct = context.pct != null ? context.pct : used / limit;
  const state = context.state || pressureState(pct);
  const tone = STATE_COLOR[state];
  const fill = Math.min(1, pct);
  const culprit = tone ? dominantSegmentKey(segments) : null;
  const cachedPct = cachedShare(context.cached, limit);

  const colorFor = (key) => (tone && key === culprit ? tone : ramp[key] || ramp.unattributed);

  const readout = `${formatTokens(used)} / ${formatTokens(limit)} (${formatPercent(pct)})`;
  const ariaLabel = `${label}: ${readout}${state === 'ok' ? '' : ` — ${STATE_NOTE[state]}`}`;

  const bar = (
    <div
      role="img"
      aria-label={ariaLabel}
      style={{
        position: 'relative',
        display: 'flex',
        height: compact ? 6 : 9,
        borderRadius: 999,
        overflow: 'hidden',
        background: colors.rail,
      }}
    >
      {segments.map((segment) => (
        <div
          key={segment.key}
          title={`${segment.label} · ${formatTokens(segment.tokens)}${segment.estimated ? ' (estimated)' : ''}`}
          style={{
            width: `${Math.min(100, (segment.tokens / limit) * 100)}%`,
            flexShrink: 0,
            background: colorFor(segment.key),
            // Unattributed is not a source — hatch it so it never reads as
            // one more thing filling the window.
            backgroundImage: segment.key === 'unattributed'
              ? hatch(darkMode ? 'rgba(0,0,0,0.35)' : 'rgba(255,255,255,0.55)')
              : undefined,
          }}
        />
      ))}
      {/* Nothing to segment (no breakdown available) — still show occupancy. */}
      {segments.length === 0 && (
        <div style={{ width: `${fill * 100}%`, flexShrink: 0, background: tone || colors.tokenIn }} />
      )}
      {/* Cache-warm boundary: trimming to the left of this costs the discount. */}
      {cachedPct > 0 && (
        <div
          title={`cached prefix ${formatTokens(context.cached)} — trimming into it invalidates the cache`}
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            bottom: 0,
            width: `${cachedPct * 100}%`,
            borderRight: `2px solid ${darkMode ? 'rgba(255,255,255,0.85)' : 'rgba(17,24,39,0.7)'}`,
            background: hatch(darkMode ? 'rgba(0,0,0,0.30)' : 'rgba(255,255,255,0.45)'),
            pointerEvents: 'none',
          }}
        />
      )}
    </div>
  );

  if (compact) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 120, ...style }}>
        <div style={{ flex: 1 }}>{bar}</div>
        <span
          style={{
            fontFamily: TYPOGRAPHY.mono,
            fontSize: 11,
            color: tone || colors.textMuted,
            whiteSpace: 'nowrap',
          }}
          title={ariaLabel}
        >
          {STATE_GLYPH[state] && `${STATE_GLYPH[state]} `}{formatPercent(pct)}
        </span>
      </div>
    );
  }

  const breakdown = segments.concat(
    context.free > 0 ? [{ key: '__free', label: 'Free space', tokens: context.free }] : []
  );

  return (
    <div
      style={{
        background: colors.card,
        border: `1px solid ${tone || colors.border}`,
        borderRadius: 12,
        padding: '12px 14px',
        ...style,
      }}
    >
      <button
        type="button"
        onClick={collapsible ? () => setOpen(!open) : undefined}
        aria-expanded={collapsible ? open : undefined}
        disabled={!collapsible}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          width: '100%',
          background: 'none',
          border: 'none',
          padding: 0,
          textAlign: 'left',
          cursor: collapsible ? 'pointer' : 'default',
        }}
      >
        <span
          style={{
            fontFamily: TYPOGRAPHY.mono,
            fontSize: 11,
            fontWeight: 600,
            letterSpacing: '0.06em',
            textTransform: 'uppercase',
            color: colors.textSecondary,
          }}
        >
          {label}
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
          {readout}
        </span>
        {collapsible && (
          <span
            aria-hidden="true"
            style={{
              fontFamily: TYPOGRAPHY.mono,
              fontSize: 11,
              color: colors.textMuted,
              transform: open ? 'rotate(90deg)' : 'none',
              transition: 'transform 0.15s ease',
            }}
          >
            &gt;
          </span>
        )}
      </button>

      <div style={{ marginTop: 10 }}>{bar}</div>

      {open && (
        <div style={{ marginTop: 12, display: 'flex', flexDirection: 'column', gap: 5 }}>
          {breakdown.map((segment) => (
            <div key={segment.key} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 13 }}>
              <span
                style={{
                  width: 9,
                  height: 9,
                  borderRadius: 2,
                  flexShrink: 0,
                  background: segment.key === '__free' ? ramp.__free : colorFor(segment.key),
                  backgroundImage: segment.key === 'unattributed'
                    ? hatch(darkMode ? 'rgba(0,0,0,0.35)' : 'rgba(255,255,255,0.55)')
                    : undefined,
                  border: segment.key === '__free' ? `1px solid ${colors.borderStrong}` : 'none',
                }}
              />
              <span style={{ flex: 1, color: segment.key === '__free' ? colors.textMuted : colors.textCell }}>
                {segment.label}
                {segment.estimated && (
                  <span style={{ color: colors.textMuted, fontSize: 11 }} title="Estimated: no per-message token counts are recorded"> ~</span>
                )}
              </span>
              <span style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 12, color: colors.textSecondary, width: 60, textAlign: 'right' }}>
                {formatTokens(segment.tokens)}
              </span>
              <span style={{ fontFamily: TYPOGRAPHY.mono, fontSize: 12, color: colors.textMuted, width: 50, textAlign: 'right' }}>
                {((segment.tokens / limit) * 100).toFixed(1)}%
              </span>
            </div>
          ))}

          {(context.cached > 0 || context.thinking > 0 || !context.window_known) && (
            <div
              style={{
                display: 'flex',
                flexWrap: 'wrap',
                gap: 16,
                marginTop: 6,
                paddingTop: 8,
                borderTop: `1px solid ${colors.border}`,
                fontFamily: TYPOGRAPHY.mono,
                fontSize: 11,
                color: colors.textMuted,
              }}
            >
              {context.cached > 0 && (
                <span title="Reusing this prefix is nearly free; trimming into it is not">
                  <span style={{ color: colors.tokenIn }}>[=]</span> cached prefix {formatTokens(context.cached)}
                </span>
              )}
              {context.thinking > 0 && (
                <span>
                  <span style={{ color: colors.tokenOut }}>[~]</span> thinking {formatTokens(context.thinking)}
                </span>
              )}
              {!context.window_known && (
                <span title={`No published window for ${context.model || 'this model'} — assuming ${formatTokens(limit)}`}>
                  <span style={{ color: colors.warning }}>[?]</span> assumed window
                </span>
              )}
            </div>
          )}
        </div>
      )}

      {STATE_NOTE[state] && (
        <div
          style={{
            marginTop: 10,
            fontFamily: TYPOGRAPHY.mono,
            fontSize: 11,
            color: state === 'warning' ? colors.warningText : colors.error,
          }}
        >
          {STATE_GLYPH[state]} {STATE_NOTE[state]}
          {context.overflow > 0 && ` — ${formatTokens(context.overflow)} over`}
        </div>
      )}
    </div>
  );
}

export { WARN_AT, CRITICAL_AT };
