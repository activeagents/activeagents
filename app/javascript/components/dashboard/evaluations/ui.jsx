import React from 'react';
import { TYPOGRAPHY } from '../../../utils/designTokens';
import { ACCENT } from '../../../utils/dashboardTheme';

// Small presentational pieces the Evaluations page is built from: mono type,
// tinted badges, outlined chips, buttons, stat tiles and bars. Styled from
// the product design system (13px base, mono for every number and id,
// uppercase micro-labels, 12px card radius) and resolved per theme.

export const MONO = TYPOGRAPHY.mono;

// Dark mode lifts the strong colours so they stay readable on #1f1f1f.
export const semanticFor = (darkMode) => ({
  success: darkMode ? '#4ade80' : '#16a34a',
  warning: darkMode ? '#facc15' : '#ca8a04',
  error: darkMode ? '#f87171' : '#dc2626',
  info: darkMode ? '#60a5fa' : '#3b82f6',
  tokenIn: darkMode ? '#60a5fa' : '#2563eb',
  tokenOut: darkMode ? '#a78bfa' : '#7c3aed',
});

const BADGE_TONES = {
  success: { light: ['#dcfce7', '#166534'], dark: ['rgba(22,163,74,0.18)', '#4ade80'] },
  warning: { light: ['#fef9c3', '#854d0e'], dark: ['rgba(234,179,8,0.18)', '#facc15'] },
  neutral: { light: ['#f3f4f6', '#4b5563'], dark: ['rgba(255,255,255,0.1)', 'rgba(255,255,255,0.7)'] },
  error: { light: ['#fee2e2', '#991b1b'], dark: ['rgba(220,38,38,0.18)', '#f87171'] },
  info: { light: ['#dbeafe', '#1e40af'], dark: ['rgba(59,130,246,0.18)', '#60a5fa'] },
};

// Shared thresholds: a fraction is coloured the same on every surface.
export const toneFor = (fraction) => {
  if (fraction == null || Number.isNaN(fraction)) return 'neutral';
  if (fraction >= 0.85) return 'success';
  if (fraction >= 0.7) return 'warning';
  return 'error';
};

export const toneColor = (tone, sem, colors) =>
  ({ success: sem.success, warning: sem.warning, error: sem.error, info: sem.info }[tone] || colors.textMuted);

export function Badge({ tone = 'neutral', darkMode, children, title, testId }) {
  const [bg, fg] = (BADGE_TONES[tone] || BADGE_TONES.neutral)[darkMode ? 'dark' : 'light'];
  return (
    <span
      data-testid={testId}
      title={title}
      style={{
        background: bg,
        color: fg,
        borderRadius: '4px',
        padding: '2px 7px',
        fontSize: '11px',
        fontWeight: 600,
        fontFamily: MONO,
        whiteSpace: 'nowrap',
        display: 'inline-block',
      }}
    >
      {children}
    </span>
  );
}

export function Chip({ colors, children, title, active = false, onClick, testId }) {
  const style = {
    fontFamily: MONO,
    fontSize: '11px',
    padding: '3px 8px',
    borderRadius: '6px',
    border: `1px solid ${active ? ACCENT : colors.inputBorder}`,
    color: active ? ACCENT : colors.textCell,
    background: active ? 'rgba(239,68,68,0.08)' : 'transparent',
    whiteSpace: 'nowrap',
    cursor: onClick ? 'pointer' : 'default',
    lineHeight: 1.4,
  };
  if (onClick) {
    return (
      <button type="button" onClick={onClick} title={title} data-testid={testId} style={style}>
        {children}
      </button>
    );
  }
  return <span title={title} data-testid={testId} style={style}>{children}</span>;
}

export function Button({ variant = 'secondary', size = 'md', onClick, disabled, colors, children, title, type = 'button' }) {
  const base = {
    padding: size === 'sm' ? '5px 10px' : '7px 14px',
    borderRadius: '8px',
    fontSize: '13px',
    fontWeight: 500,
    cursor: disabled ? 'not-allowed' : 'pointer',
    transition: 'background 0.15s ease, border-color 0.15s ease',
    whiteSpace: 'nowrap',
  };
  const variants = {
    primary: { background: disabled ? colors.mutedBg : ACCENT, color: disabled ? colors.textMuted : '#ffffff', border: '1px solid transparent' },
    secondary: { background: 'transparent', color: colors.textCell, border: `1px solid ${colors.inputBorder}` },
    danger: { background: 'transparent', color: '#dc2626', border: '1px solid rgba(220,38,38,0.4)' },
  };
  return (
    <button type={type} onClick={onClick} disabled={disabled} title={title} style={{ ...base, ...(variants[variant] || variants.secondary) }}>
      {children}
    </button>
  );
}

export function MicroLabel({ colors, children, style, testId }) {
  return (
    <span
      data-testid={testId}
      style={{
        fontFamily: MONO,
        fontSize: '11px',
        fontWeight: 600,
        letterSpacing: '0.06em',
        textTransform: 'uppercase',
        color: colors.textSecondary,
        whiteSpace: 'nowrap',
        ...style,
      }}
    >
      {children}
    </span>
  );
}

export function Mono({ colors, color, size = 11, weight = 400, children, style, title, testId }) {
  return (
    <span
      data-testid={testId}
      title={title}
      style={{ fontFamily: MONO, fontSize: `${size}px`, fontWeight: weight, color: color || colors?.textMuted, ...style }}
    >
      {children}
    </span>
  );
}

export function StatTile({ label, value, sub, color, colors, testId }) {
  return (
    <div
      data-testid={testId}
      style={{
        background: colors.cardBg,
        border: `1px solid ${colors.cardBorder}`,
        borderRadius: '12px',
        padding: '14px 16px',
        display: 'flex',
        flexDirection: 'column',
        gap: '6px',
        minWidth: 0,
      }}
    >
      <MicroLabel colors={colors}>{label}</MicroLabel>
      <div style={{ fontSize: '26px', fontWeight: 700, lineHeight: 1.1, color: color || colors.textPrimary, fontFamily: MONO }}>
        {value}
      </div>
      <div style={{ fontSize: '12px', color: colors.textSecondary }}>{sub}</div>
    </div>
  );
}

export function Glyph({ colors, children }) {
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: '22px',
        height: '22px',
        borderRadius: '6px',
        background: colors.mutedBg,
        fontFamily: MONO,
        fontSize: '12px',
        fontWeight: 600,
        color: colors.textSecondary,
        flexShrink: 0,
      }}
    >
      {children}
    </span>
  );
}

export function Bar({ fraction, color, colors, height = 6 }) {
  const width = fraction == null || Number.isNaN(fraction) ? 0 : Math.max(0, Math.min(1, fraction)) * 100;
  return (
    <div style={{ height: `${height}px`, width: '100%', borderRadius: '999px', background: colors.trackBg, overflow: 'hidden', flexShrink: 0 }}>
      <div style={{ width: `${width}%`, height: '100%', background: color, borderRadius: '999px', transition: 'width 0.4s ease' }} />
    </div>
  );
}

export function Spinner() {
  return (
    <div className="flex items-center justify-center h-64">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
    </div>
  );
}
