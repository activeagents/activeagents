import React, { useState, useEffect, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';
import {
  LineChart, Line, AreaChart, Area, BarChart, Bar,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  PieChart, Pie, Cell
} from 'recharts';

// ---------------------------------------------------------------------------
// Color palette for the three concurrency strategies
// ---------------------------------------------------------------------------
const STRATEGY_COLORS = {
  Sequential:       { bar: '#6b7280', badge: '#f3f4f6', text: '#374151', span: 'bg-gray-400' },
  Threads:          { bar: '#3b82f6', badge: '#eff6ff', text: '#1d4ed8', span: 'bg-blue-400' },
  'Thread Pool':    { bar: '#0891b2', badge: '#ecfeff', text: '#0e7490', span: 'bg-cyan-400' },
  Ractors:          { bar: '#ef4444', badge: '#fef2f2', text: '#dc2626', span: 'bg-red-500' },
  'Ractor Pool':    { bar: '#f97316', badge: '#fff7ed', text: '#c2410c', span: 'bg-orange-400' },
  'Async Fibers':   { bar: '#8b5cf6', badge: '#f5f3ff', text: '#6d28d9', span: 'bg-purple-400' },
};

function strategyColor(name, field) {
  const key = Object.keys(STRATEGY_COLORS).find(k => name?.startsWith(k)) || 'Sequential';
  return STRATEGY_COLORS[key]?.[field] || STRATEGY_COLORS.Sequential[field];
}

// ---------------------------------------------------------------------------
// MiniSparkline — compact inline chart for stat cards
// ---------------------------------------------------------------------------
function MiniSparkline({ values, color = '#ef4444', height = 40 }) {
  if (!values || values.length < 2) return null;
  const data = values.map((v, i) => ({ run: i + 1, value: v }));
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 2, right: 2, left: 2, bottom: 2 }}>
        <defs>
          <linearGradient id={`gradient-${color.replace('#', '')}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="5%" stopColor={color} stopOpacity={0.3} />
            <stop offset="95%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <Area
          type="monotone"
          dataKey="value"
          stroke={color}
          strokeWidth={2}
          fill={`url(#gradient-${color.replace('#', '')})`}
        />
        <Tooltip
          contentStyle={{ background: '#1f2937', border: 'none', borderRadius: '6px', fontSize: '12px' }}
          labelStyle={{ color: '#9ca3af' }}
          itemStyle={{ color: color }}
          formatter={(value) => [`${value.toFixed(1)} req/s`, 'Throughput']}
          labelFormatter={(label) => `Run #${label}`}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}

// ---------------------------------------------------------------------------
// ThroughputHistoryChart — multi-line chart showing all strategies over time
// ---------------------------------------------------------------------------
function ThroughputHistoryChart({ runs, strategyNames, colors }) {
  if (!runs || runs.length < 2) return null;

  // Transform data: each run becomes a data point with all strategy values
  const data = runs.slice().reverse().map((r, idx) => {
    const point = { run: idx + 1, runId: r.id };
    (r.strategies || []).forEach(s => {
      // Normalize strategy name for data key
      const key = s.name?.replace(/[^a-zA-Z]/g, '') || 'unknown';
      point[key] = s.throughput || 0;
      point[`${key}_name`] = s.name;
    });
    return point;
  });

  // Get unique strategy keys from the data
  const strategyKeys = [...new Set(
    data.flatMap(d => Object.keys(d).filter(k => !k.includes('_name') && k !== 'run' && k !== 'runId'))
  )];

  return (
    <ResponsiveContainer width="100%" height={280}>
      <LineChart data={data} margin={{ top: 10, right: 30, left: 0, bottom: 10 }}>
        <CartesianGrid strokeDasharray="3 3" stroke={colors.borderLight} />
        <XAxis
          dataKey="run"
          tick={{ fill: colors.textMuted, fontSize: 11 }}
          tickLine={{ stroke: colors.borderLight }}
          axisLine={{ stroke: colors.borderLight }}
          label={{ value: 'Run #', position: 'bottom', fill: colors.textMuted, fontSize: 11 }}
        />
        <YAxis
          tick={{ fill: colors.textMuted, fontSize: 11 }}
          tickLine={{ stroke: colors.borderLight }}
          axisLine={{ stroke: colors.borderLight }}
          label={{ value: 'req/s', angle: -90, position: 'insideLeft', fill: colors.textMuted, fontSize: 11 }}
        />
        <Tooltip
          contentStyle={{
            background: colors.cardBg,
            border: `1px solid ${colors.border}`,
            borderRadius: '8px',
            fontSize: '12px'
          }}
          labelStyle={{ color: colors.textPrimary, fontWeight: 'bold', marginBottom: '4px' }}
          formatter={(value, name) => {
            const displayName = strategyNames.find(n => n.replace(/[^a-zA-Z]/g, '') === name) || name;
            return [`${value.toFixed(1)} req/s`, displayName];
          }}
          labelFormatter={(label) => `Run #${label}`}
        />
        <Legend
          wrapperStyle={{ fontSize: '11px', paddingTop: '10px' }}
          formatter={(value) => strategyNames.find(n => n.replace(/[^a-zA-Z]/g, '') === value) || value}
        />
        {strategyKeys.map((key, idx) => {
          const originalName = strategyNames.find(n => n.replace(/[^a-zA-Z]/g, '') === key) || key;
          return (
            <Line
              key={key}
              type="monotone"
              dataKey={key}
              name={key}
              stroke={strategyColor(originalName, 'bar')}
              strokeWidth={2}
              dot={{ r: 3, fill: strategyColor(originalName, 'bar') }}
              activeDot={{ r: 5 }}
            />
          );
        })}
      </LineChart>
    </ResponsiveContainer>
  );
}

// ---------------------------------------------------------------------------
// StrategyBarChart — Recharts horizontal bar chart for comparing strategies
// ---------------------------------------------------------------------------
function StrategyComparisonChart({ strategies, metric, unit, colors, title }) {
  if (!strategies || strategies.length === 0) return null;

  const data = strategies.map(s => ({
    name: s.name,
    value: s[metric] || 0,
    fill: strategyColor(s.name, 'bar')
  }));

  return (
    <div style={{ marginBottom: '24px' }}>
      {title && (
        <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
          {title}
        </div>
      )}
      <ResponsiveContainer width="100%" height={strategies.length * 45 + 40}>
        <BarChart data={data} layout="vertical" margin={{ top: 5, right: 60, left: 100, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={colors.borderLight} horizontal={false} />
          <XAxis
            type="number"
            tick={{ fill: colors.textMuted, fontSize: 11 }}
            tickLine={{ stroke: colors.borderLight }}
            axisLine={{ stroke: colors.borderLight }}
          />
          <YAxis
            type="category"
            dataKey="name"
            tick={{ fill: colors.textPrimary, fontSize: 12 }}
            tickLine={false}
            axisLine={false}
            width={95}
          />
          <Tooltip
            contentStyle={{
              background: colors.cardBg,
              border: `1px solid ${colors.border}`,
              borderRadius: '8px',
              fontSize: '12px'
            }}
            formatter={(value) => [`${typeof value === 'number' ? value.toFixed(2) : value}${unit}`, metric]}
          />
          <Bar dataKey="value" radius={[0, 4, 4, 0]}>
            {data.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={entry.fill} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
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
          <MiniSparkline values={sparkData} color={sparkColor || '#ef4444'} />
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
                        <MiniSparkline values={history} color={strategyColor(name, 'bar')} height={36} />
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
              <TabButton id="memory"     label="🧠 Memory" />
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
                  <div style={{ borderTop: `1px solid ${colors.border}`, paddingTop: '16px', marginTop: '20px' }}>
                    <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '16px' }}>
                      Throughput history across {runs.length} runs
                    </div>
                    <ThroughputHistoryChart
                      runs={runs}
                      strategyNames={strategyNames}
                      colors={colors}
                    />
                  </div>
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

            {/* ── Memory tab ─────────────────────────────── */}
            {activeTab === 'memory' && (() => {
              const hasMemoryData = strategies.some(s => s.memory_delta_mb !== undefined || s.gc_runs !== undefined);
              const maxMemDelta = Math.max(...strategies.map(s => Math.abs(s.memory_delta_mb || 0)), 0.1);
              const maxGcRuns = Math.max(...strategies.map(s => s.gc_runs || 0), 1);
              const maxMemEnd = Math.max(...strategies.map(s => s.memory_end_mb || s.memory_mb_after || 0), 1);
              const totalContextMb = strategies.reduce((sum, s) => sum + (s.context_allocated_mb || 0), 0);

              // Calculate memory efficiency (tokens processed per MB of memory used)
              const memoryEfficiency = strategies.map(s => {
                const tokens = (s.total_input_tokens || 0) + (s.total_output_tokens || 0);
                const memDelta = Math.abs(s.memory_delta_mb || 0.01);
                return { name: s.name, efficiency: tokens / memDelta };
              });
              const maxEfficiency = Math.max(...memoryEfficiency.map(m => m.efficiency), 1);

              return (
                <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
                  <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px', marginTop: 0 }}>
                    Memory Utilization & Garbage Collection
                  </h3>

                  {!hasMemoryData ? (
                    <div style={{ textAlign: 'center', padding: '40px 0', color: colors.textSecondary }}>
                      <div style={{ fontSize: '32px', marginBottom: '12px' }}>📊</div>
                      <p style={{ marginBottom: '8px' }}>No memory data available for this run.</p>
                      <p style={{ fontSize: '12px', color: colors.textMuted }}>
                        Run <code style={{ fontFamily: 'monospace', background: colors.borderLight, padding: '2px 6px', borderRadius: '4px' }}>bin/bench --context-kb 512</code> to simulate LLM context memory and track GC behavior.
                      </p>
                    </div>
                  ) : (
                    <>
                      {/* Memory summary cards */}
                      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '12px', marginBottom: '24px' }}>
                        <div style={{ background: darkMode ? 'rgba(239, 68, 68, 0.1)' : '#fef2f2', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(239, 68, 68, 0.2)' : '#fecaca'}` }}>
                          <div style={{ fontSize: '11px', color: '#ef4444', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                            Peak Memory
                          </div>
                          <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#ef4444', fontFamily: 'monospace' }}>
                            {maxMemEnd.toFixed(1)} MB
                          </div>
                          <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                            highest across strategies
                          </div>
                        </div>
                        <div style={{ background: darkMode ? 'rgba(34, 197, 94, 0.1)' : '#f0fdf4', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(34, 197, 94, 0.2)' : '#bbf7d0'}` }}>
                          <div style={{ fontSize: '11px', color: '#16a34a', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                            Min Memory Delta
                          </div>
                          <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#16a34a', fontFamily: 'monospace' }}>
                            {Math.min(...strategies.map(s => Math.abs(s.memory_delta_mb || 0))).toFixed(2)} MB
                          </div>
                          <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                            most memory efficient
                          </div>
                        </div>
                        <div style={{ background: darkMode ? 'rgba(139, 92, 246, 0.1)' : '#f5f3ff', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(139, 92, 246, 0.2)' : '#c4b5fd'}` }}>
                          <div style={{ fontSize: '11px', color: '#7c3aed', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                            Context Allocated
                          </div>
                          <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#7c3aed', fontFamily: 'monospace' }}>
                            {totalContextMb.toFixed(1)} MB
                          </div>
                          <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                            simulated LLM context
                          </div>
                        </div>
                        <div style={{ background: darkMode ? 'rgba(245, 158, 11, 0.1)' : '#fffbeb', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(245, 158, 11, 0.2)' : '#fde68a'}` }}>
                          <div style={{ fontSize: '11px', color: '#d97706', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                            Total GC Cycles
                          </div>
                          <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#d97706', fontFamily: 'monospace' }}>
                            {strategies.reduce((sum, s) => sum + (s.gc_runs || 0), 0)}
                          </div>
                          <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                            across all strategies
                          </div>
                        </div>
                      </div>

                      {/* Context allocated badge */}
                      {strategies.some(s => s.context_allocated_mb) && (
                        <div style={{
                          background: darkMode ? 'rgba(139, 92, 246, 0.15)' : '#f5f3ff',
                          border: `1px solid ${darkMode ? 'rgba(139, 92, 246, 0.3)' : '#c4b5fd'}`,
                          borderRadius: '8px',
                          padding: '12px 16px',
                          marginBottom: '20px',
                          display: 'flex',
                          alignItems: 'center',
                          gap: '12px'
                        }}>
                          <span style={{ fontSize: '20px' }}>🧪</span>
                          <div>
                            <div style={{ fontSize: '13px', fontWeight: '600', color: darkMode ? '#c4b5fd' : '#6d28d9' }}>
                              Simulated LLM Context: {strategies[0]?.context_allocated_mb?.toFixed(1) || 0} MB per request
                            </div>
                            <div style={{ fontSize: '12px', color: colors.textSecondary, marginTop: '2px' }}>
                              Each request allocates context memory to simulate large LLM conversation windows
                            </div>
                          </div>
                        </div>
                      )}

                      {/* Memory waterfall - before/after visualization */}
                      <div style={{ marginBottom: '24px' }}>
                        <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                          Memory Usage (Before → After)
                        </div>
                        {strategies.map((s, i) => {
                          const memStart = s.memory_start_mb || s.memory_mb_before || 0;
                          const memEnd = s.memory_end_mb || s.memory_mb_after || 0;
                          const startPct = maxMemEnd > 0 ? (memStart / maxMemEnd) * 100 : 0;
                          const endPct = maxMemEnd > 0 ? (memEnd / maxMemEnd) * 100 : 0;
                          const delta = memEnd - memStart;

                          return (
                            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
                              <div style={{ width: '160px', fontSize: '13px', color: colors.textPrimary, flexShrink: 0, fontWeight: '500' }}>
                                {s.name}
                              </div>
                              <div style={{ flex: 1, background: colors.borderLight, borderRadius: '4px', height: '28px', position: 'relative', overflow: 'hidden' }}>
                                {/* Before bar */}
                                <div style={{
                                  position: 'absolute',
                                  left: 0,
                                  top: '2px',
                                  width: `${startPct}%`,
                                  height: '10px',
                                  background: '#94a3b8',
                                  borderRadius: '3px',
                                  transition: 'width 0.6s ease'
                                }} />
                                {/* After bar */}
                                <div style={{
                                  position: 'absolute',
                                  left: 0,
                                  bottom: '2px',
                                  width: `${endPct}%`,
                                  height: '10px',
                                  background: delta > 1 ? '#ef4444' : delta > 0.1 ? '#f59e0b' : '#22c55e',
                                  borderRadius: '3px',
                                  transition: 'width 0.6s ease'
                                }} />
                              </div>
                              <div style={{ width: '100px', textAlign: 'right', fontSize: '11px', fontFamily: 'monospace', color: delta > 1 ? '#ef4444' : delta > 0.1 ? '#f59e0b' : '#22c55e', flexShrink: 0 }}>
                                {delta >= 0 ? '+' : ''}{delta.toFixed(2)} MB
                              </div>
                            </div>
                          );
                        })}
                        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '16px', marginTop: '8px', fontSize: '11px' }}>
                          <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                            <span style={{ width: '10px', height: '6px', background: '#94a3b8', borderRadius: '2px' }} />
                            <span style={{ color: colors.textMuted }}>Before</span>
                          </span>
                          <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                            <span style={{ width: '10px', height: '6px', background: '#22c55e', borderRadius: '2px' }} />
                            <span style={{ color: colors.textMuted }}>After</span>
                          </span>
                        </div>
                      </div>

                      {/* Memory efficiency bars */}
                      <div style={{ marginBottom: '24px' }}>
                        <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                          Memory Efficiency (tokens processed per MB)
                        </div>
                        <p style={{ fontSize: '12px', color: colors.textMuted, marginBottom: '12px' }}>
                          Higher is better. Shows how efficiently each strategy processes tokens relative to memory consumed.
                        </p>
                        {memoryEfficiency.map((m, i) => (
                          <StrategyBar
                            key={i}
                            strategy={m.name}
                            value={m.efficiency}
                            maxValue={maxEfficiency}
                            unit=" tok/MB"
                            colors={colors}
                          />
                        ))}
                      </div>

                      {/* Memory delta bars */}
                      <div style={{ marginBottom: '24px' }}>
                        <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                          Memory Pressure (delta MB during benchmark)
                        </div>
                        <p style={{ fontSize: '12px', color: colors.textMuted, marginBottom: '12px' }}>
                          Lower is better. Ractors have isolated GC per worker, reducing shared heap pressure.
                        </p>
                        {strategies.map((s, i) => (
                          <StrategyBar
                            key={i}
                            strategy={s.name}
                            value={Math.abs(s.memory_delta_mb || 0)}
                            maxValue={maxMemDelta}
                            unit=" MB"
                            colors={colors}
                          />
                        ))}
                      </div>

                      {/* GC runs bars */}
                      <div style={{ marginBottom: '24px' }}>
                        <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                          GC Cycles During Benchmark
                        </div>
                        <p style={{ fontSize: '12px', color: colors.textMuted, marginBottom: '12px' }}>
                          Fewer GC pauses = more consistent latency. Ractors GC independently without stop-the-world pauses.
                        </p>
                        {strategies.map((s, i) => (
                          <StrategyBar
                            key={i}
                            strategy={s.name}
                            value={s.gc_runs || 0}
                            maxValue={maxGcRuns}
                            unit=" cycles"
                            colors={colors}
                          />
                        ))}
                      </div>

                      {/* Memory detail table */}
                      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                        <thead>
                          <tr style={{ borderBottom: `1px solid ${colors.border}`, color: colors.textSecondary }}>
                            <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Strategy</th>
                            <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Mem Start</th>
                            <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Mem End</th>
                            <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Delta</th>
                            <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>GC Runs</th>
                            <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Tok/MB</th>
                          </tr>
                        </thead>
                        <tbody>
                          {strategies.map((s, i) => {
                            const tokens = (s.total_input_tokens || 0) + (s.total_output_tokens || 0);
                            const memDelta = Math.abs(s.memory_delta_mb || 0.01);
                            const efficiency = tokens / memDelta;

                            return (
                              <tr key={i} style={{ borderBottom: i < strategies.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                                <td style={{ padding: '10px 0', color: colors.textPrimary, fontWeight: '500' }}>{s.name}</td>
                                <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textSecondary }}>
                                  {(s.memory_start_mb || s.memory_mb_before)?.toFixed(1) || '—'} MB
                                </td>
                                <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textSecondary }}>
                                  {(s.memory_end_mb || s.memory_mb_after)?.toFixed(1) || '—'} MB
                                </td>
                                <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: (s.memory_delta_mb || 0) > 1 ? '#ef4444' : '#22c55e' }}>
                                  {s.memory_delta_mb !== undefined ? `${s.memory_delta_mb >= 0 ? '+' : ''}${s.memory_delta_mb.toFixed(2)} MB` : '—'}
                                </td>
                                <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                                  {s.gc_runs !== undefined ? s.gc_runs : '—'}
                                </td>
                                <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#0891b2' }}>
                                  {efficiency.toFixed(0)}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>

                      <div style={{
                        marginTop: '20px',
                        padding: '16px',
                        background: darkMode ? 'rgba(34, 197, 94, 0.1)' : '#f0fdf4',
                        borderRadius: '8px',
                        border: `1px solid ${darkMode ? 'rgba(34, 197, 94, 0.2)' : '#bbf7d0'}`
                      }}>
                        <div style={{ fontSize: '13px', fontWeight: '600', color: darkMode ? '#86efac' : '#166534', marginBottom: '8px' }}>
                          💎 Ruby 4.x Ractor Advantage
                        </div>
                        <p style={{ fontSize: '12px', color: colors.textSecondary, margin: 0, lineHeight: 1.6 }}>
                          Ractors provide true parallelism with <strong>isolated garbage collection</strong>. Each Ractor has its own heap,
                          eliminating stop-the-world GC pauses that affect other workers. This is especially beneficial for
                          LLM workloads with large context windows where memory churn is high.
                        </p>
                      </div>
                    </>
                  )}
                </div>
              );
            })()}

            {/* ── Tokens tab ──────────────────────────────── */}
            {activeTab === 'tokens' && (() => {
              const maxTotalTokens = Math.max(...strategies.map(s => (s.total_input_tokens || 0) + (s.total_output_tokens || 0)), 1);
              const maxInputTokens = Math.max(...strategies.map(s => s.total_input_tokens || 0), 1);
              const maxOutputTokens = Math.max(...strategies.map(s => s.total_output_tokens || 0), 1);
              const totalTokensAllStrategies = strategies.reduce((sum, s) => sum + (s.total_input_tokens || 0) + (s.total_output_tokens || 0), 0);
              const totalInputAll = strategies.reduce((sum, s) => sum + (s.total_input_tokens || 0), 0);
              const totalOutputAll = strategies.reduce((sum, s) => sum + (s.total_output_tokens || 0), 0);

              // Estimated cost calculation (using OpenAI GPT-4 pricing as baseline)
              const INPUT_COST_PER_1K = 0.01;   // $0.01 per 1K input tokens
              const OUTPUT_COST_PER_1K = 0.03;  // $0.03 per 1K output tokens

              return (
                <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
                  <h3 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px', marginTop: 0 }}>
                    Token Utilization & Cost Analysis
                  </h3>

                  {/* Token summary cards */}
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '12px', marginBottom: '24px' }}>
                    <div style={{ background: darkMode ? 'rgba(37, 99, 235, 0.1)' : '#eff6ff', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(37, 99, 235, 0.2)' : '#bfdbfe'}` }}>
                      <div style={{ fontSize: '11px', color: '#2563eb', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                        ↓ Total Input
                      </div>
                      <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#2563eb', fontFamily: 'monospace' }}>
                        {totalInputAll.toLocaleString()}
                      </div>
                      <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                        ~${((totalInputAll / 1000) * INPUT_COST_PER_1K).toFixed(4)}
                      </div>
                    </div>
                    <div style={{ background: darkMode ? 'rgba(124, 58, 237, 0.1)' : '#f5f3ff', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(124, 58, 237, 0.2)' : '#c4b5fd'}` }}>
                      <div style={{ fontSize: '11px', color: '#7c3aed', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                        ↑ Total Output
                      </div>
                      <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#7c3aed', fontFamily: 'monospace' }}>
                        {totalOutputAll.toLocaleString()}
                      </div>
                      <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                        ~${((totalOutputAll / 1000) * OUTPUT_COST_PER_1K).toFixed(4)}
                      </div>
                    </div>
                    <div style={{ background: darkMode ? 'rgba(255, 255, 255, 0.05)' : '#f9fafb', borderRadius: '10px', padding: '16px', border: `1px solid ${colors.border}` }}>
                      <div style={{ fontSize: '11px', color: colors.textSecondary, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                        Total Tokens
                      </div>
                      <div style={{ fontSize: '24px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>
                        {totalTokensAllStrategies.toLocaleString()}
                      </div>
                      <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                        across {strategies.length} strategies
                      </div>
                    </div>
                    <div style={{ background: darkMode ? 'rgba(34, 197, 94, 0.1)' : '#f0fdf4', borderRadius: '10px', padding: '16px', border: `1px solid ${darkMode ? 'rgba(34, 197, 94, 0.2)' : '#bbf7d0'}` }}>
                      <div style={{ fontSize: '11px', color: '#16a34a', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '6px' }}>
                        Est. API Cost
                      </div>
                      <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#16a34a', fontFamily: 'monospace' }}>
                        ${(((totalInputAll / 1000) * INPUT_COST_PER_1K) + ((totalOutputAll / 1000) * OUTPUT_COST_PER_1K)).toFixed(4)}
                      </div>
                      <div style={{ fontSize: '12px', color: colors.textMuted, marginTop: '4px' }}>
                        GPT-4 pricing estimate
                      </div>
                    </div>
                  </div>

                  {/* Token distribution bars */}
                  <div style={{ marginBottom: '24px' }}>
                    <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                      Token Distribution by Strategy
                    </div>
                    {strategies.map((s, i) => {
                      const inputTokens = s.total_input_tokens || 0;
                      const outputTokens = s.total_output_tokens || 0;
                      const totalTokens = inputTokens + outputTokens;
                      const inputPct = totalTokens > 0 ? (inputTokens / totalTokens) * 100 : 50;
                      const barWidth = maxTotalTokens > 0 ? Math.max((totalTokens / maxTotalTokens) * 100, 2) : 2;

                      return (
                        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '10px' }}>
                          <div style={{ width: '160px', fontSize: '13px', color: colors.textPrimary, flexShrink: 0, fontWeight: '500' }}>
                            {s.name}
                          </div>
                          <div style={{ flex: 1, background: colors.borderLight, borderRadius: '4px', height: '24px', overflow: 'hidden', position: 'relative' }}>
                            <div style={{ width: `${barWidth}%`, height: '100%', display: 'flex', borderRadius: '4px', overflow: 'hidden' }}>
                              <div style={{ width: `${inputPct}%`, height: '100%', background: '#2563eb', transition: 'width 0.6s ease' }} />
                              <div style={{ width: `${100 - inputPct}%`, height: '100%', background: '#7c3aed', transition: 'width 0.6s ease' }} />
                            </div>
                          </div>
                          <div style={{ width: '100px', textAlign: 'right', fontSize: '12px', fontFamily: 'monospace', color: colors.textSecondary, flexShrink: 0 }}>
                            {totalTokens.toLocaleString()}
                          </div>
                        </div>
                      );
                    })}
                    <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '16px', marginTop: '8px', fontSize: '11px' }}>
                      <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                        <span style={{ width: '10px', height: '10px', background: '#2563eb', borderRadius: '2px' }} />
                        <span style={{ color: colors.textMuted }}>Input</span>
                      </span>
                      <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                        <span style={{ width: '10px', height: '10px', background: '#7c3aed', borderRadius: '2px' }} />
                        <span style={{ color: colors.textMuted }}>Output</span>
                      </span>
                    </div>
                  </div>

                  {/* Tokens per second / efficiency metrics */}
                  <div style={{ marginBottom: '24px' }}>
                    <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                      Token Throughput (tokens/second)
                    </div>
                    {(() => {
                      const tokensPerSec = strategies.map(s => {
                        const totalTokens = (s.total_input_tokens || 0) + (s.total_output_tokens || 0);
                        const wallSec = (s.wall_time_ms || 1) / 1000;
                        return { name: s.name, tps: totalTokens / wallSec };
                      });
                      const maxTps = Math.max(...tokensPerSec.map(t => t.tps), 1);

                      return tokensPerSec.map((t, i) => (
                        <StrategyBar
                          key={i}
                          strategy={t.name}
                          value={t.tps}
                          maxValue={maxTps}
                          unit=" tok/s"
                          colors={colors}
                        />
                      ));
                    })()}
                  </div>

                  {/* Detailed token table */}
                  <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                    <thead>
                      <tr style={{ borderBottom: `1px solid ${colors.border}`, color: colors.textSecondary }}>
                        <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Strategy</th>
                        <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>↓ Input</th>
                        <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>↑ Output</th>
                        <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Total</th>
                        <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Tok/sec</th>
                        <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Est. Cost</th>
                        <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Errors</th>
                      </tr>
                    </thead>
                    <tbody>
                      {strategies.map((s, i) => {
                        const inputTokens = s.total_input_tokens || 0;
                        const outputTokens = s.total_output_tokens || 0;
                        const totalTokens = inputTokens + outputTokens;
                        const wallSec = (s.wall_time_ms || 1) / 1000;
                        const tps = totalTokens / wallSec;
                        const cost = ((inputTokens / 1000) * INPUT_COST_PER_1K) + ((outputTokens / 1000) * OUTPUT_COST_PER_1K);

                        return (
                          <tr key={i} style={{ borderBottom: i < strategies.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                            <td style={{ padding: '10px 0', color: colors.textPrimary, fontWeight: '500' }}>{s.name}</td>
                            <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#2563eb' }}>
                              {inputTokens.toLocaleString()}
                            </td>
                            <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#7c3aed' }}>
                              {outputTokens.toLocaleString()}
                            </td>
                            <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                              {totalTokens.toLocaleString()}
                            </td>
                            <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#0891b2' }}>
                              {tps.toFixed(0)}
                            </td>
                            <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: '#16a34a' }}>
                              ${cost.toFixed(4)}
                            </td>
                            <td style={{ padding: '10px 0', textAlign: 'right', color: s.errors > 0 ? '#ef4444' : colors.textMuted }}>
                              {s.errors || 0}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>

                  {/* Context Window Utilization - Token Type Breakdown */}
                  <div style={{ marginTop: '32px', borderTop: `1px solid ${colors.border}`, paddingTop: '24px' }}>
                    <h4 style={{ fontSize: '15px', fontWeight: '600', color: colors.textPrimary, marginBottom: '8px', marginTop: 0 }}>
                      Context Window Utilization
                    </h4>
                    <p style={{ fontSize: '12px', color: colors.textMuted, marginBottom: '20px' }}>
                      Input tokens break down into overhead (system prompts, tool schemas, structured output schemas) and productive content (user messages, conversation history). Tool/schema overhead can consume 20-40% of context.
                    </p>

                    {/* Token type breakdown visualization */}
                    {(() => {
                      // Token type colors
                      const TOKEN_TYPES = {
                        system_prompt: { color: '#6366f1', label: 'System Prompt', description: 'Base instructions' },
                        tool_schemas: { color: '#f59e0b', label: 'Tool Schemas', description: 'Function definitions (JSON)' },
                        structured_output: { color: '#ec4899', label: 'Structured Output', description: 'Response format schema' },
                        conversation: { color: '#10b981', label: 'Conversation', description: 'User + assistant history' },
                        user_input: { color: '#3b82f6', label: 'User Input', description: 'Current request' },
                        available: { color: darkMode ? 'rgba(255,255,255,0.1)' : '#e5e7eb', label: 'Available', description: 'Remaining context' }
                      };

                      // Model context windows for reference
                      const CONTEXT_WINDOWS = {
                        'GPT-4': 8192,
                        'GPT-4-32K': 32768,
                        'GPT-4-Turbo': 128000,
                        'Claude-3': 200000,
                        'Gemini-Pro': 32000
                      };

                      // Calculate token breakdown per strategy (use actual data if available, otherwise estimate)
                      const getTokenBreakdown = (s) => {
                        const inputTokens = s.total_input_tokens || 0;
                        const outputTokens = s.total_output_tokens || 0;
                        const nRequests = run?.config?.n_requests || 1;
                        const avgInputPerReq = inputTokens / nRequests;

                        // Use actual breakdown if available, otherwise estimate typical distribution
                        const breakdown = {
                          system_prompt: s.system_prompt_tokens || Math.round(avgInputPerReq * 0.10),
                          tool_schemas: s.tool_schema_tokens || Math.round(avgInputPerReq * 0.25),
                          structured_output: s.structured_output_tokens || Math.round(avgInputPerReq * 0.08),
                          conversation: s.conversation_tokens || Math.round(avgInputPerReq * 0.12),
                          user_input: s.user_input_tokens || Math.round(avgInputPerReq * 0.45),
                        };

                        const totalUsed = Object.values(breakdown).reduce((a, b) => a + b, 0);
                        const contextWindow = 128000; // GPT-4-Turbo default
                        breakdown.available = Math.max(0, contextWindow - totalUsed);

                        return { ...breakdown, total: totalUsed, contextWindow };
                      };

                      // Get first strategy's breakdown for the main visualization
                      const firstStrategy = strategies[0];
                      const breakdown = firstStrategy ? getTokenBreakdown(firstStrategy) : null;

                      if (!breakdown) return null;

                      // Calculate percentages for stacked bar
                      const usedPct = (breakdown.total / breakdown.contextWindow) * 100;
                      const overheadTokens = breakdown.system_prompt + breakdown.tool_schemas + breakdown.structured_output;
                      const overheadPct = (overheadTokens / breakdown.total) * 100;

                      return (
                        <>
                          {/* Overhead warning banner */}
                          {overheadPct > 30 && (
                            <div style={{
                              background: darkMode ? 'rgba(245, 158, 11, 0.15)' : '#fffbeb',
                              border: `1px solid ${darkMode ? 'rgba(245, 158, 11, 0.3)' : '#fde68a'}`,
                              borderRadius: '8px',
                              padding: '12px 16px',
                              marginBottom: '20px',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '12px'
                            }}>
                              <span style={{ fontSize: '20px' }}>⚠️</span>
                              <div>
                                <div style={{ fontSize: '13px', fontWeight: '600', color: '#d97706' }}>
                                  High Schema Overhead: {overheadPct.toFixed(0)}% of input tokens
                                </div>
                                <div style={{ fontSize: '12px', color: colors.textSecondary, marginTop: '2px' }}>
                                  Tool and structured output schemas consume significant context. Consider schema optimization or splitting tools.
                                </div>
                              </div>
                            </div>
                          )}

                          {/* Context utilization gauge */}
                          <div style={{ marginBottom: '24px' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: '8px' }}>
                              <span style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary }}>
                                Context Window Usage (per request)
                              </span>
                              <span style={{ fontSize: '12px', color: colors.textMuted }}>
                                {breakdown.total.toLocaleString()} / {breakdown.contextWindow.toLocaleString()} tokens ({usedPct.toFixed(1)}%)
                              </span>
                            </div>

                            {/* Stacked bar showing token types */}
                            <div style={{ background: TOKEN_TYPES.available.color, borderRadius: '6px', height: '32px', overflow: 'hidden', display: 'flex' }}>
                              {Object.entries(TOKEN_TYPES).filter(([key]) => key !== 'available').map(([key, config]) => {
                                const tokens = breakdown[key] || 0;
                                const pct = (tokens / breakdown.contextWindow) * 100;
                                if (pct < 0.5) return null;
                                return (
                                  <div
                                    key={key}
                                    style={{
                                      width: `${pct}%`,
                                      height: '100%',
                                      background: config.color,
                                      transition: 'width 0.6s ease',
                                      display: 'flex',
                                      alignItems: 'center',
                                      justifyContent: 'center',
                                      overflow: 'hidden'
                                    }}
                                    title={`${config.label}: ${tokens.toLocaleString()} tokens (${pct.toFixed(1)}%)`}
                                  >
                                    {pct > 8 && (
                                      <span style={{ fontSize: '10px', color: 'white', fontWeight: '500', whiteSpace: 'nowrap' }}>
                                        {pct.toFixed(0)}%
                                      </span>
                                    )}
                                  </div>
                                );
                              })}
                            </div>

                            {/* Legend */}
                            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', marginTop: '12px' }}>
                              {Object.entries(TOKEN_TYPES).map(([key, config]) => {
                                const tokens = breakdown[key] || 0;
                                if (key === 'available' && tokens === 0) return null;
                                return (
                                  <div key={key} style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                    <span style={{ width: '12px', height: '12px', borderRadius: '3px', background: config.color, flexShrink: 0 }} />
                                    <span style={{ fontSize: '11px', color: colors.textSecondary }}>
                                      {config.label}
                                      <span style={{ color: colors.textMuted, marginLeft: '4px' }}>
                                        ({tokens.toLocaleString()})
                                      </span>
                                    </span>
                                  </div>
                                );
                              })}
                            </div>
                          </div>

                          {/* Token type breakdown table */}
                          <div style={{ marginBottom: '24px' }}>
                            <div style={{ fontSize: '13px', fontWeight: '600', color: colors.textSecondary, marginBottom: '12px' }}>
                              Token Type Breakdown (Average per Request)
                            </div>
                            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                              <thead>
                                <tr style={{ borderBottom: `1px solid ${colors.border}`, color: colors.textSecondary }}>
                                  <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Token Type</th>
                                  <th style={{ textAlign: 'left', padding: '8px 0', fontWeight: '500' }}>Description</th>
                                  <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>Tokens</th>
                                  <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>% of Input</th>
                                  <th style={{ textAlign: 'right', padding: '8px 0', fontWeight: '500' }}>% of Context</th>
                                </tr>
                              </thead>
                              <tbody>
                                {Object.entries(TOKEN_TYPES).filter(([key]) => key !== 'available').map(([key, config], i, arr) => {
                                  const tokens = breakdown[key] || 0;
                                  const pctInput = breakdown.total > 0 ? (tokens / breakdown.total) * 100 : 0;
                                  const pctContext = (tokens / breakdown.contextWindow) * 100;
                                  const isOverhead = ['system_prompt', 'tool_schemas', 'structured_output'].includes(key);

                                  return (
                                    <tr key={key} style={{ borderBottom: i < arr.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                                      <td style={{ padding: '10px 0' }}>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                          <span style={{ width: '10px', height: '10px', borderRadius: '2px', background: config.color }} />
                                          <span style={{ color: colors.textPrimary, fontWeight: '500' }}>{config.label}</span>
                                          {isOverhead && (
                                            <span style={{
                                              fontSize: '9px',
                                              padding: '1px 4px',
                                              borderRadius: '3px',
                                              background: darkMode ? 'rgba(245, 158, 11, 0.2)' : '#fef3c7',
                                              color: '#d97706',
                                              fontWeight: '600'
                                            }}>
                                              OVERHEAD
                                            </span>
                                          )}
                                        </div>
                                      </td>
                                      <td style={{ padding: '10px 0', color: colors.textMuted, fontSize: '12px' }}>
                                        {config.description}
                                      </td>
                                      <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                                        {tokens.toLocaleString()}
                                      </td>
                                      <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: isOverhead ? '#d97706' : '#10b981' }}>
                                        {pctInput.toFixed(1)}%
                                      </td>
                                      <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textSecondary }}>
                                        {pctContext.toFixed(2)}%
                                      </td>
                                    </tr>
                                  );
                                })}
                                {/* Totals row */}
                                <tr style={{ borderTop: `2px solid ${colors.border}`, fontWeight: '600' }}>
                                  <td style={{ padding: '10px 0', color: colors.textPrimary }} colSpan={2}>
                                    Total Input
                                  </td>
                                  <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                                    {breakdown.total.toLocaleString()}
                                  </td>
                                  <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                                    100%
                                  </td>
                                  <td style={{ padding: '10px 0', textAlign: 'right', fontFamily: 'monospace', color: colors.textPrimary }}>
                                    {usedPct.toFixed(2)}%
                                  </td>
                                </tr>
                              </tbody>
                            </table>
                          </div>

                          {/* Schema overhead insights */}
                          <div style={{
                            padding: '16px',
                            background: darkMode ? 'rgba(99, 102, 241, 0.1)' : '#eef2ff',
                            borderRadius: '8px',
                            border: `1px solid ${darkMode ? 'rgba(99, 102, 241, 0.2)' : '#c7d2fe'}`
                          }}>
                            <div style={{ fontSize: '13px', fontWeight: '600', color: darkMode ? '#a5b4fc' : '#4338ca', marginBottom: '8px' }}>
                              💡 Schema Optimization Tips
                            </div>
                            <ul style={{ fontSize: '12px', color: colors.textSecondary, margin: 0, paddingLeft: '20px', lineHeight: 1.8 }}>
                              <li><strong>Tool Schemas:</strong> Each tool definition adds ~100-500 tokens. Group related tools or use tool routing.</li>
                              <li><strong>Structured Output:</strong> JSON Schema definitions grow with complexity. Flatten nested structures.</li>
                              <li><strong>System Prompts:</strong> Long instructions accumulate per request. Move static content to fine-tuning.</li>
                              <li><strong>Multi-turn:</strong> Conversation history grows linearly. Implement summarization for long sessions.</li>
                            </ul>
                          </div>
                        </>
                      );
                    })()}
                  </div>

                  <p style={{ fontSize: '12px', color: colors.textMuted, marginTop: '24px', marginBottom: 0 }}>
                    Cost estimates based on GPT-4 pricing ($0.01/1K input, $0.03/1K output). Actual costs vary by provider.
                    Token breakdown shows estimates when actual metrics are not available.
                  </p>
                </div>
              );
            })()}

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
