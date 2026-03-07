import React, { useState, useEffect, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

// ---------------------------------------------------------------------------
// Color palette for the three concurrency strategies
// ---------------------------------------------------------------------------
const STRATEGY_COLORS = {
  Sequential:       { bar: '#6b7280', badge: '#f3f4f6', text: '#374151', span: 'bg-gray-400' },
  Threads:          { bar: '#3b82f6', badge: '#eff6ff', text: '#1d4ed8', span: 'bg-blue-400' },
  Ractors:          { bar: '#ef4444', badge: '#fef2f2', text: '#dc2626', span: 'bg-red-500' },
  'Ractor Pool':    { bar: '#f97316', badge: '#fff7ed', text: '#c2410c', span: 'bg-orange-400' },
  'Async Fibers':   { bar: '#8b5cf6', badge: '#f5f3ff', text: '#6d28d9', span: 'bg-purple-400' },
};

function strategyColor(name, field) {
  const key = Object.keys(STRATEGY_COLORS).find(k => name?.startsWith(k)) || 'Sequential';
  return STRATEGY_COLORS[key]?.[field] || STRATEGY_COLORS.Sequential[field];
}

// ---------------------------------------------------------------------------
// Sparkline — tiny inline SVG trend line (matches MetricsView style)
// ---------------------------------------------------------------------------
function Sparkline({ values, color = '#ef4444', height = 30 }) {
  if (!values || values.length < 2) return null;
  const max = Math.max(...values);
  const min = Math.min(...values);
  const range = max - min || 1;
  const w = 100;
  const h = height;
  const pts = values.map((v, i) => {
    const x = (i / (values.length - 1)) * w;
    const y = h - ((v - min) / range) * (h - 4) - 2;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  return (
    <svg viewBox={`0 0 ${w} ${h}`} style={{ width: '100%', height: `${h}px` }}>
      <polyline points={pts} fill="none" stroke={color} strokeWidth="2" strokeLinejoin="round" />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Bar chart row — horizontal bar comparing one metric across strategies
// ---------------------------------------------------------------------------
function StrategyBar({ strategy, value, maxValue, unit = '', colors }) {
  const pct = maxValue > 0 ? Math.max((value / maxValue) * 100, 2) : 2;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '10px' }}>
      <div style={{ width: '160px', fontSize: '13px', color: colors.textPrimary, flexShrink: 0, fontWeight: '500' }}>
        {strategy}
      </div>
      <div style={{ flex: 1, background: colors.borderLight, borderRadius: '4px', height: '20px', overflow: 'hidden' }}>
        <div
          style={{
            width: `${pct}%`,
            height: '100%',
            background: strategyColor(strategy, 'bar'),
            borderRadius: '4px',
            transition: 'width 0.6s ease'
          }}
        />
      </div>
      <div style={{ width: '80px', textAlign: 'right', fontSize: '13px', fontFamily: 'monospace', color: colors.textPrimary, flexShrink: 0 }}>
        {typeof value === 'number' ? value.toFixed(value < 10 ? 2 : 1) : value}{unit}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Waterfall / Gantt span bar (matches TracesView timeline style)
// ---------------------------------------------------------------------------
function StrategyTimeline({ strategies, totalMs, colors }) {
  if (!strategies?.length) return null;
  return (
    <div>
      {/* Scale */}
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: colors.textMuted, marginBottom: '8px' }}>
        <span>0ms</span>
        <span>{Math.round(totalMs * 0.25)}ms</span>
        <span>{Math.round(totalMs * 0.5)}ms</span>
        <span>{Math.round(totalMs * 0.75)}ms</span>
        <span>{Math.round(totalMs)}ms</span>
      </div>
      {strategies.map((s, idx) => {
        const name = s.name || s.strategy;
        const wallMs = s.wall_time_ms || 0;
        const pct = totalMs > 0 ? Math.max((wallMs / totalMs) * 100, 1) : 1;
        return (
          <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
            <div style={{ width: '160px', fontSize: '12px', color: colors.textPrimary, flexShrink: 0 }}>
              {name}
            </div>
            <div style={{ flex: 1, background: colors.borderLight, borderRadius: '4px', height: '20px', position: 'relative' }}>
              <div
                style={{
                  position: 'absolute',
                  left: 0,
                  width: `${pct}%`,
                  height: '100%',
                  background: strategyColor(name, 'bar'),
                  borderRadius: '4px',
                  transition: 'width 0.6s ease',
                  display: 'flex',
                  alignItems: 'center',
                  paddingLeft: '6px'
                }}
              >
                {pct > 15 && (
                  <span style={{ fontSize: '11px', color: 'white', fontFamily: 'monospace' }}>
                    {wallMs.toFixed(0)}ms
                  </span>
                )}
              </div>
            </div>
            <div style={{ width: '80px', textAlign: 'right', fontSize: '12px', fontFamily: 'monospace', color: colors.textSecondary, flexShrink: 0 }}>
              {s.speedup_vs_sequential?.toFixed(2)}x
            </div>
          </div>
        );
      })}
      <div style={{ display: 'flex', justifyContent: 'flex-end', fontSize: '11px', color: colors.textMuted, marginTop: '4px' }}>
        speedup →
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Stat card (matches MetricsView 2×2 grid style)
// ---------------------------------------------------------------------------
function StatCard({ label, value, sub, sparkData, sparkColor, colors }) {
  return (
    <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
      <div style={{ fontSize: '11px', color: colors.textSecondary, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '8px' }}>
        {label}
      </div>
      <div style={{ fontSize: '28px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>
        {value}
      </div>
      {sub && (
        <div style={{ fontSize: '13px', color: colors.textSecondary, marginTop: '6px' }}>{sub}</div>
      )}
      {sparkData && (
        <div style={{ marginTop: '12px' }}>
          <Sparkline values={sparkData} color={sparkColor || '#ef4444'} />
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
function EmptyState({ colors }) {
  return (
    <div style={{ textAlign: 'center', padding: '64px 0' }}>
      <div style={{ fontSize: '48px', marginBottom: '16px' }}>⚡</div>
      <div style={{ fontSize: '20px', fontWeight: '600', color: colors.textPrimary, marginBottom: '8px' }}>
        No benchmark runs yet
      </div>
      <p style={{ fontSize: '14px', color: colors.textSecondary, maxWidth: '420px', margin: '0 auto 24px' }}>
        Run <code style={{ fontFamily: 'monospace', background: colors.borderLight, padding: '2px 6px', borderRadius: '4px' }}>bin/bench</code> from
        your <code style={{ fontFamily: 'monospace', background: colors.borderLight, padding: '2px 6px', borderRadius: '4px' }}>ragents</code> directory
        to generate your first report.
      </p>
      <div style={{
        background: colors.cardBg,
        border: `1px solid ${colors.border}`,
        borderRadius: '12px',
        padding: '20px',
        maxWidth: '560px',
        margin: '0 auto',
        textAlign: 'left'
      }}>
        <div style={{ fontSize: '12px', fontFamily: 'monospace', color: colors.textSecondary, lineHeight: '1.8' }}>
          <div style={{ color: colors.textMuted, marginBottom: '4px' }}># One-liner for M1 Pro (simulated, no API key needed)</div>
          <div style={{ color: '#ef4444' }}>bin/bench --requests 20 --post http://localhost:3000 --watch</div>
          <div style={{ marginTop: '12px', color: colors.textMuted }}># With real OpenAI API</div>
          <div style={{ color: '#ef4444' }}>OPENAI_API_KEY=sk-... bin/bench --provider openai --requests 10 --post http://localhost:3000</div>
          <div style={{ marginTop: '12px', color: colors.textMuted }}># Include Async fiber strategy</div>
          <div style={{ color: '#ef4444' }}>bin/bench --async --requests 20 --post http://localhost:3000</div>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main BenchmarkView component
// ---------------------------------------------------------------------------
export default function BenchmarkView() {
  const { darkMode } = useTheme();
  const [data, setData]         = useState(null);
  const [isLoading, setLoading] = useState(true);
  const [selectedRun, setSelectedRun] = useState(0);
  const [activeTab, setActiveTab] = useState('timeline'); // timeline | throughput | latency | tokens
  const [lastFetch, setLastFetch] = useState(null);
  const [autoRefresh, setAutoRefresh] = useState(true);

  // Theme — exact same pattern as MetricsView / TracesView
  const colors = {
    bg:            darkMode ? 'transparent' : '#f9fafb',
    cardBg:        darkMode ? 'rgba(255,255,255,0.05)' : '#ffffff',
    border:        darkMode ? 'rgba(255,255,255,0.1)' : '#e5e7eb',
    borderLight:   darkMode ? 'rgba(255,255,255,0.08)' : '#f3f4f6',
    textPrimary:   darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted:     darkMode ? 'rgba(255,255,255,0.35)' : '#9ca3af',
    accent:        '#ef4444',
  };

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch('/api/benchmarks');
      if (res.ok) {
        const json = await res.json();
        setData(json);
        setLastFetch(new Date().toLocaleTimeString());
      }
    } catch (_) {
      // silently fail — dashboard still works with empty state
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
    if (!autoRefresh) return;
    const interval = setInterval(fetchData, 10_000); // poll every 10s for live watch mode
    return () => clearInterval(interval);
  }, [fetchData, autoRefresh]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500" />
      </div>
    );
  }

  const runs = data?.runs || [];
  const run  = runs[selectedRun] || null;
  const strategies = run?.strategies || [];
  const maxWall   = Math.max(...strategies.map(s => s.wall_time_ms || 0), 1);
  const maxTput   = Math.max(...strategies.map(s => s.throughput || 0), 1);
  const maxP95    = Math.max(...strategies.map(s => s.p95_latency_ms || 0), 1);
  const summary   = data?.strategy_summary || [];

  // Sparkline data — throughput across runs per strategy
  const strategyNames = [...new Set(runs.flatMap(r => (r.strategies || []).map(s => s.name)))];
  const throughputHistory = (name) =>
    runs.slice().reverse().map(r => (r.strategies || []).find(s => s.name === name)?.throughput || 0);

  const TabButton = ({ id, label }) => (
    <button
      onClick={() => setActiveTab(id)}
      style={{
        padding: '8px 16px',
        borderRadius: '8px',
        border: 'none',
        cursor: 'pointer',
        fontSize: '13px',
        fontWeight: '500',
        background: activeTab === id ? colors.accent : colors.borderLight,
        color: activeTab === id ? 'white' : colors.textSecondary,
        transition: 'all 0.15s ease'
      }}
    >
      {label}
    </button>
  );

  return (
    <div style={{ borderRadius: '12px', overflow: 'hidden', minHeight: 'calc(100vh - 200px)', backgroundColor: colors.bg }}>

      {/* ── Header ─────────────────────────────────────────── */}
      <div style={{ padding: '24px 24px 16px', borderBottom: `1px solid ${colors.border}`, marginBottom: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
          <div>
            <h1 style={{ fontSize: '24px', fontWeight: 'bold', color: colors.textPrimary, margin: 0 }}>
              Ragents Benchmarks
            </h1>
            <p style={{ fontSize: '14px', color: colors.textSecondary, marginTop: '4px' }}>
              Sequential · Threads · Ractors · Async — live results from <code style={{ fontFamily: 'monospace' }}>bin/bench</code>
            </p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
            {lastFetch && (
              <span style={{ fontSize: '12px', color: colors.textMuted }}>Updated {lastFetch}</span>
            )}
            <button
              onClick={() => setAutoRefresh(v => !v)}
              style={{
                padding: '6px 12px',
                borderRadius: '8px',
                border: `1px solid ${colors.border}`,
                background: autoRefresh ? '#dcfce7' : colors.borderLight,
                color: autoRefresh ? '#16a34a' : colors.textSecondary,
                fontSize: '12px',
                cursor: 'pointer',
                fontWeight: '500'
              }}
            >
              {autoRefresh ? '● Live' : '○ Paused'}
            </button>
            <button
              onClick={fetchData}
              style={{
                padding: '8px 16px',
                background: colors.accent,
                color: 'white',
                borderRadius: '8px',
                border: 'none',
                fontSize: '13px',
                fontWeight: '500',
                cursor: 'pointer'
              }}
            >
              Refresh
            </button>
          </div>
        </div>
      </div>

      <div style={{ padding: '0 24px 24px' }}>

        {/* ── Empty state ─────────────────────────────────── */}
        {runs.length === 0 && <EmptyState colors={colors} />}

        {runs.length > 0 && (
          <>
            {/* ── Run selector ───────────────────────────── */}
            {runs.length > 1 && (
              <div style={{ marginBottom: '16px', display: 'flex', gap: '8px', overflowX: 'auto', paddingBottom: '4px' }}>
                {runs.map((r, idx) => {
                  const hw = r.hardware || {};
                  const cfg = r.config || {};
                  return (
                    <button
                      key={r.id}
                      onClick={() => setSelectedRun(idx)}
                      style={{
                        padding: '8px 14px',
                        borderRadius: '8px',
                        border: `1px solid ${selectedRun === idx ? colors.accent : colors.border}`,
                        background: selectedRun === idx ? (darkMode ? 'rgba(239,68,68,0.15)' : '#fef2f2') : colors.cardBg,
                        color: selectedRun === idx ? colors.accent : colors.textSecondary,
                        fontSize: '12px',
                        cursor: 'pointer',
                        whiteSpace: 'nowrap',
                        flexShrink: 0
                      }}
                    >
                      <span style={{ fontWeight: '600' }}>#{runs.length - idx}</span>
                      {' · '}N={cfg.n_requests || '?'}
                      {' · '}IO={cfg.io_latency_ms || '?'}ms
                      {' · '}{new Date(r.run_at).toLocaleTimeString()}
                    </button>
                  );
                })}
              </div>
            )}

            {/* ── Hardware context ───────────────────────── */}
            {run?.hardware && (
              <div style={{
                background: colors.cardBg,
                border: `1px solid ${colors.border}`,
                borderRadius: '10px',
                padding: '12px 16px',
                marginBottom: '16px',
                display: 'flex',
                gap: '24px',
                flexWrap: 'wrap',
                fontSize: '12px',
                color: colors.textSecondary
              }}>
                <span>🖥 <strong style={{ color: colors.textPrimary }}>{run.hardware.cpu_model}</strong></span>
                <span>⚙ <strong style={{ color: colors.textPrimary }}>{run.hardware.cpu_cores}</strong> cores</span>
                <span>💎 Ruby <strong style={{ color: colors.textPrimary }}>{run.hardware.ruby_version}</strong></span>
                <span>📦 N=<strong style={{ color: colors.textPrimary }}>{run.config?.n_requests}</strong></span>
                <span>⏱ I/O=<strong style={{ color: colors.textPrimary }}>{run.config?.io_latency_ms}ms</strong></span>
                <span>🔢 CPU=<strong style={{ color: colors.textPrimary }}>{(run.config?.cpu_iterations || 0).toLocaleString()}</strong> iters</span>
                {run.winner && (
                  <span>🏆 Winner: <strong style={{ color: colors.accent }}>{run.winner.name}</strong> at {run.winner.throughput?.toFixed(1)} req/s</span>
                )}
              </div>
            )}

            {/* ── Summary stat cards ─────────────────────── */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '12px', marginBottom: '16px' }}>
              {strategies.map((s, idx) => {
                const name = s.name;
                const history = throughputHistory(name);
                return (
                  <div key={idx} style={{ background: colors.cardBg, borderRadius: '12px', padding: '16px', border: `1px solid ${colors.border}` }}>
                    <div style={{
                      display: 'inline-block',
                      fontSize: '11px',
                      fontWeight: '600',
                      padding: '2px 8px',
                      borderRadius: '4px',
                      background: strategyColor(name, 'badge'),
                      color: strategyColor(name, 'text'),
                      marginBottom: '8px'
                    }}>
                      {name}
                    </div>
                    <div style={{ fontSize: '26px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>
                      {(s.throughput || 0).toFixed(1)}
                      <span style={{ fontSize: '12px', color: colors.textMuted, marginLeft: '4px' }}>req/s</span>
                    </div>
                    <div style={{ fontSize: '12px', color: colors.textSecondary, marginTop: '4px' }}>
                      {(s.wall_time_ms || 0).toFixed(0)}ms total · {(s.speedup_vs_sequential || 1).toFixed(2)}x speedup
                    </div>
                    {history.length > 1 && (
                      <div style={{ marginTop: '10px' }}>
                        <Sparkline values={history} color={strategyColor(name, 'bar')} height={28} />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* ── Tab bar ────────────────────────────────── */}
            <div style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
              <TabButton id="timeline"   label="⏱ Timeline" />
              <TabButton id="throughput" label="📈 Throughput" />
              <TabButton id="latency"    label="⚡ Latency" />
              <TabButton id="tokens"     label="🔤 Tokens" />
            </div>

            {/* ── Timeline tab (Gantt / waterfall, matches TracesView) ── */}
            {activeTab === 'timeline' && (
              <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
                <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px', marginTop: 0 }}>
                  Wall-clock time — {run?.config?.n_requests} concurrent requests
                </h3>
                <StrategyTimeline strategies={strategies} totalMs={maxWall} colors={colors} />
                <p style={{ fontSize: '12px', color: colors.textMuted, marginTop: '16px', marginBottom: 0 }}>
                  Each bar represents total elapsed time from first request to last response.
                  Speedup is relative to sequential baseline.
                </p>
              </div>
            )}

            {/* ── Throughput tab ──────────────────────────── */}
            {activeTab === 'throughput' && (
              <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
                <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px', marginTop: 0 }}>
                  Throughput (requests / second)
                </h3>
                {strategies.map((s, i) => (
                  <StrategyBar
                    key={i}
                    strategy={s.name}
                    value={s.throughput || 0}
                    maxValue={maxTput}
                    unit=" req/s"
                    colors={colors}
                  />
                ))}

                {/* Across-run history chart */}
                {runs.length > 1 && (
                  <>
                    <div style={{ borderTop: `1px solid ${colors.border}`, paddingTop: '16px', marginTop: '20px' }}>
                      <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                        Throughput history across {runs.length} runs
                      </div>
                      {strategyNames.map(name => (
                        <div key={name} style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '8px' }}>
                          <span style={{ width: '160px', fontSize: '12px', color: colors.textPrimary, flexShrink: 0 }}>{name}</span>
                          <div style={{ flex: 1 }}>
                            <Sparkline values={throughputHistory(name)} color={strategyColor(name, 'bar')} height={28} />
                          </div>
                        </div>
                      ))}
                    </div>
                  </>
                )}
              </div>
            )}

            {/* ── Latency tab ─────────────────────────────── */}
            {activeTab === 'latency' && (
              <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
                <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px', marginTop: 0 }}>
                  Per-request latency (ms)
                </h3>

                {/* p95 bars */}
                <div style={{ marginBottom: '20px' }}>
                  <div style={{ fontSize: '12px', color: colors.textMuted, marginBottom: '8px' }}>p95 Latency</div>
                  {strategies.map((s, i) => (
                    <StrategyBar key={i} strategy={s.name} value={s.p95_latency_ms || 0} maxValue={maxP95} unit="ms" colors={colors} />
                  ))}
                </div>

                {/* Latency detail table */}
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: `1px solid ${colors.border}`, color: colors.textSecondary }}>
                      <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Strategy</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>avg</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>min</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>p50</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>p95</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>max</th>
                    </tr>
                  </thead>
                  <tbody>
                    {strategies.map((s, i) => (
                      <tr key={i} style={{ borderBottom: i < strategies.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                        <td style={{ padding: '10px 0', color: colors.textPrimary, fontWeight: '500' }}>{s.name}</td>
                        {['avg_latency_ms', 'min_latency_ms', 'p50_latency_ms', 'p95_latency_ms', 'max_latency_ms'].map(key => (
                          <td key={key} style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textSecondary }}>
                            {(s[key] || 0).toFixed(0)}ms
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {/* ── Tokens tab ──────────────────────────────── */}
            {activeTab === 'tokens' && (
              <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
                <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px', marginTop: 0 }}>
                  Token usage across strategies
                </h3>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: `1px solid ${colors.border}`, color: colors.textSecondary }}>
                      <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Strategy</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>↓ Input</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>↑ Output</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Total</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Errors</th>
                    </tr>
                  </thead>
                  <tbody>
                    {strategies.map((s, i) => (
                      <tr key={i} style={{ borderBottom: i < strategies.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                        <td style={{ padding: '10px 0', color: colors.textPrimary, fontWeight: '500' }}>{s.name}</td>
                        <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#2563eb' }}>
                          {(s.total_input_tokens || 0).toLocaleString()}
                        </td>
                        <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#7c3aed' }}>
                          {(s.total_output_tokens || 0).toLocaleString()}
                        </td>
                        <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                          {((s.total_input_tokens || 0) + (s.total_output_tokens || 0)).toLocaleString()}
                        </td>
                        <td style={{ padding: '10px 0', textAlign: 'right', color: s.errors > 0 ? '#ef4444' : colors.textMuted }}>
                          {s.errors || 0}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p style={{ fontSize: '12px', color: colors.textMuted, marginTop: '12px', marginBottom: 0 }}>
                  Token counts reflect actual provider API responses. Simulated provider uses estimated counts.
                </p>
              </div>
            )}

            {/* ── Cross-run summary (all time) ────────────── */}
            {summary.length > 0 && (
              <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
                <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '4px', marginTop: 0 }}>
                  All-time averages across {runs.length} run{runs.length !== 1 ? 's' : ''}
                </h3>
                <p style={{ fontSize: '13px', color: colors.textSecondary, marginBottom: '16px' }}>
                  Aggregate performance across all benchmark runs stored in the dashboard
                </p>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: `1px solid ${colors.border}`, color: colors.textSecondary }}>
                      <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Strategy</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Runs</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Avg req/s</th>
                      <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Avg wall time</th>
                    </tr>
                  </thead>
                  <tbody>
                    {summary.map((s, i) => (
                      <tr key={i} style={{ borderBottom: i < summary.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                        <td style={{ padding: '10px 0' }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                            <span style={{
                              width: '10px',
                              height: '10px',
                              borderRadius: '50%',
                              background: strategyColor(s.name, 'bar'),
                              flexShrink: 0,
                              display: 'inline-block'
                            }} />
                            <span style={{ color: colors.textPrimary, fontWeight: '500' }}>{s.name}</span>
                          </div>
                        </td>
                        <td style={{ padding: '10px 0', textAlign: 'right', color: colors.textSecondary }}>{s.run_count}</td>
                        <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                          {s.avg_throughput.toFixed(1)} req/s
                        </td>
                        <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textSecondary }}>
                          {s.avg_wall_time_ms.toFixed(0)}ms
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
