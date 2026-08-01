/**
 * Shared math, formatting and color logic for the context-utilization
 * visualizations (ContextMeter, growth chart, turn deltas, headroom).
 *
 * Kept in one place so the meter, the charts and the list rows can never
 * disagree about a threshold or a segment color — the legend has to key
 * the bar, and a second copy of the ramp is how that stops being true.
 */

export const WARN_AT = 0.75;
export const CRITICAL_AT = 0.9;

// A tool result over this size is the single most common reason a window
// fills up, so it gets called out wherever a per-turn number is shown.
export const LARGE_TURN_TOKENS = 15000;

/**
 * Never render a raw token integer — an operator reads `412.4k` faster
 * than `412400`, and the meter is a scanning surface.
 */
export const formatTokens = (n) => {
  const value = Number(n) || 0;
  if (Math.abs(value) >= 1e6) return (value / 1e6).toFixed(1).replace(/\.0$/, '') + 'M';
  if (Math.abs(value) >= 1e3) return (value / 1e3).toFixed(1) + 'k';
  return String(Math.round(value));
};

export const formatPercent = (pct, decimals = 0) => `${((Number(pct) || 0) * 100).toFixed(decimals)}%`;

/**
 * Thresholds are semantic, not decorative: `warning` means an operator
 * should consider trimming, `critical` means the next turn is at risk, and
 * `over` means the window was already exceeded — a different event that
 * must not render identically to "full".
 */
export const pressureState = (pct) => {
  if (pct > 1) return 'over';
  if (pct >= CRITICAL_AT) return 'critical';
  if (pct >= WARN_AT) return 'warning';
  return 'ok';
};

export const STATE_COLOR = {
  ok: null,
  warning: '#eab308',
  critical: '#dc2626',
  over: '#dc2626',
};

// ASCII markers rather than color alone, matching the TUI vocabulary in
// utils/designTokens.js. Threshold state must survive a screenshot in
// grayscale and a colorblind operator.
export const STATE_GLYPH = {
  ok: '',
  warning: '[!]',
  critical: '[!]',
  over: '[!!]',
};

/**
 * What actually happens at the limit on this platform: nothing compacts
 * the history, so the window is simply exceeded and the provider truncates
 * (finish_reason: "length"). The copy says that rather than promising an
 * eviction policy the runtime does not implement.
 */
export const STATE_NOTE = {
  ok: null,
  warning: 'window filling — consider trimming tool results or older turns',
  critical: 'window nearly full — the next turn may truncate (finish_reason: length)',
  over: 'window exceeded — the provider truncated this request',
};

const TOKEN_IN = '#2563eb';

const hexToRgb = (hex) => {
  const value = hex.replace('#', '');
  const full = value.length === 3 ? value.split('').map((c) => c + c).join('') : value;
  return [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16));
};

const rgbToHex = (rgb) => '#' + rgb.map((c) => Math.round(c).toString(16).padStart(2, '0')).join('');

const mix = (hex, background, pct) => {
  const a = hexToRgb(hex);
  const b = hexToRgb(background);
  return rgbToHex(a.map((channel, i) => (channel * pct) + (b[i] * (1 - pct))));
};

/**
 * The segment ramp is blue on purpose. Amber and red are the only warm
 * colors allowed in these components — if a source were red, the 75% and
 * 90% states would stop reading as alarms.
 */
export const segmentRamp = (darkMode) => {
  const card = darkMode ? '#1f1f1f' : '#ffffff';
  return {
    messages: TOKEN_IN,
    tool_results: mix(TOKEN_IN, card, 0.74),
    instructions: mix(TOKEN_IN, card, 0.54),
    tool_schemas: mix(TOKEN_IN, card, 0.38),
    mcp_schemas: mix(TOKEN_IN, card, 0.24),
    memory: mix(TOKEN_IN, card, 0.14),
    // Must clear the rail it sits on — an unattributed remainder that
    // reads as empty track makes a full window look empty.
    unattributed: darkMode ? 'rgba(255,255,255,0.34)' : '#9ca3af',
    __free: darkMode ? 'rgba(255,255,255,0.06)' : '#f3f4f6',
  };
};

// Hatching marks a region as "not a source" (unattributed) or "cache-warm"
// without introducing another hue into a deliberately two-color palette.
export const hatch = (color) =>
  `repeating-linear-gradient(135deg, ${color} 0 3px, transparent 3px 6px)`;

export const contextColors = (darkMode) => ({
  card: darkMode ? '#1f1f1f' : '#ffffff',
  border: darkMode ? '#2a2a2a' : '#e5e7eb',
  borderStrong: darkMode ? '#3a3a3a' : '#d1d5db',
  rail: darkMode ? 'rgba(255,255,255,0.08)' : '#f3f4f6',
  textPrimary: darkMode ? '#ffffff' : '#111827',
  textCell: darkMode ? 'rgba(255,255,255,0.7)' : '#4b5563',
  textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
  textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
  tokenIn: TOKEN_IN,
  tokenOut: '#7c3aed',
  warning: '#eab308',
  warningText: darkMode ? '#fcd34d' : '#854d0e',
  error: '#dc2626',
  accent: '#ef4444',
});

/**
 * The alarm has to point at the actual culprit. Recoloring a fixed segment
 * would blame `messages` for a window filled by tool results, which is the
 * documented common case.
 */
export const dominantSegmentKey = (segments = []) => {
  const ranked = segments.filter((s) => s.key !== 'unattributed');
  const pool = ranked.length ? ranked : segments;
  return pool.reduce((best, s) => (!best || s.tokens > best.tokens ? s : best), null)?.key || null;
};

/**
 * Everything left of the cached prefix is cache-warm: cheap to keep and
 * expensive to break, because trimming into it invalidates the prefix and
 * makes the *next* call cost more. That boundary is the actual answer to
 * "what do I evict", so it is drawn on the bar rather than footnoted.
 */
export const cachedShare = (cached, limit) => {
  if (!cached || !limit) return 0;
  return Math.min(1, cached / limit);
};
