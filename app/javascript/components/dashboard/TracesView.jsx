import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer
} from 'recharts';
import { ICONS, TYPOGRAPHY } from '../../utils/designTokens';

// Deterministic color assignment for agent classes
const AGENT_PALETTE = ['#6366f1', '#10b981', '#f59e0b', '#ec4899', '#3b82f6', '#8b5cf6', '#14b8a6', '#f97316'];

const WINDOW_MINUTES = 30;
const REFRESH_INTERVAL_MS = 30000;

const buildAgentColors = (agents) => {
  const colors = {};
  agents.forEach((agent, idx) => {
    colors[agent] = AGENT_PALETTE[idx % AGENT_PALETTE.length];
  });
  return colors;
};

// Aggregate span durations by operation name across traces, so the Spans
// view can rank which agent/llm/tool steps take the longest. Root spans are
// skipped — they equal the whole trace and would dominate every ranking.
const buildSpanStats = (traces) => {
  const stats = {};
  traces.forEach((trace) => {
    (trace.spans || []).forEach((span) => {
      if ((span.nested || 0) === 0) return;
      const key = span.name || span.type || 'unknown';
      if (!stats[key]) {
        stats[key] = { name: key, type: span.type, count: 0, total: 0, max: 0, errors: 0 };
      }
      const entry = stats[key];
      entry.count += 1;
      entry.total += span.duration || 0;
      entry.max = Math.max(entry.max, span.duration || 0);
      if (span.error) entry.errors += 1;
    });
  });
  return Object.values(stats)
    .map((entry) => ({ ...entry, avg: entry.total / entry.count }))
    .sort((a, b) => b.total - a.total);
};

// Bucket traces into 1-minute intervals for the throughput chart
const buildThroughputData = (traces, agents, windowMinutes) => {
  const now = Date.now();
  const data = [];

  for (let i = windowMinutes - 1; i >= 0; i--) {
    const bucketStart = now - (i + 1) * 60000;
    const bucketEnd = now - i * 60000;
    const bucketTraces = traces.filter(
      (t) => t.timestamp_ms >= bucketStart && t.timestamp_ms < bucketEnd
    );

    const agentBreakdown = {};
    agents.forEach((agent) => {
      agentBreakdown[agent] = bucketTraces.filter((t) => t.agent === agent).length;
    });

    data.push({
      time: new Date(bucketEnd).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      timestamp: bucketEnd,
      requests: bucketTraces.length,
      errors: bucketTraces.filter((t) => t.status === 'ERROR').length,
      avgLatency: bucketTraces.length > 0
        ? Math.round(bucketTraces.reduce((a, t) => a + (t.duration_ms || 0), 0) / bucketTraces.length)
        : 0,
      traces: bucketTraces,
      ...agentBreakdown,
    });
  }
  return data;
};

// agentClass scopes the view to one agent's traces (per-agent embed: same
// component, different UX context); embedded hides the page title.
export default function TracesView({ agentClass = null, embedded = false }) {
  const { darkMode } = useTheme();
  const [traces, setTraces] = useState([]);
  const [agentsList, setAgentsList] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [selectedTrace, setSelectedTrace] = useState(null);
  const [expandedSpan, setExpandedSpan] = useState(null); // `${trace.id}:${spanIdx}`
  const [filter, setFilter] = useState({ status: 'all', agent: 'all', action: 'all' });
  const [sortBy, setSortBy] = useState('time'); // 'time' (chronological) | 'latency' (slowest first)
  const [selectedTimeBucket, setSelectedTimeBucket] = useState(null);
  const [viewMode, setViewMode] = useState('timeline'); // 'timeline', 'agents', 'actions', or 'spans'

  const fetchTraces = useCallback(async () => {
    try {
      const scope = agentClass ? `&agent=${encodeURIComponent(agentClass)}` : '';
      const response = await fetch(`/api/traces?minutes=${WINDOW_MINUTES}${scope}`);
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setTraces(data.traces || []);
      setAgentsList(agentClass ? [agentClass] : (data.agents || []));
      setLoadError(null);
    } catch (error) {
      setLoadError(error.message);
    } finally {
      setIsLoading(false);
    }
  }, [agentClass]);

  useEffect(() => {
    fetchTraces();
    const interval = setInterval(fetchTraces, REFRESH_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [fetchTraces]);

  const agentColors = useMemo(() => buildAgentColors(agentsList), [agentsList]);

  const throughputData = useMemo(
    () => buildThroughputData(traces, agentsList, WINDOW_MINUTES),
    [traces, agentsList]
  );

  // Filter traces based on selected time bucket and filters
  const filteredTraces = useMemo(() => {
    let result = traces;

    if (selectedTimeBucket !== null) {
      const bucket = throughputData[selectedTimeBucket];
      if (bucket) {
        result = bucket.traces || [];
      }
    }

    if (filter.status !== 'all') {
      result = result.filter((t) =>
        filter.status === 'success' ? t.status !== 'ERROR' : t.status === 'ERROR'
      );
    }

    if (filter.agent !== 'all') {
      result = result.filter((t) => t.agent === filter.agent);
    }

    if (filter.action !== 'all') {
      if (filter.action.includes('#')) {
        const [agent, action] = filter.action.split('#');
        result = result.filter((t) => t.agent === agent && t.action === action);
      } else {
        result = result.filter((t) => t.action === filter.action);
      }
    }

    if (sortBy === 'latency') {
      result = [...result].sort((a, b) => (b.duration_ms || 0) - (a.duration_ms || 0));
    }

    return result;
  }, [traces, selectedTimeBucket, throughputData, filter, sortBy]);

  // Aggregate agent stats for selected time range
  const agentStats = useMemo(() => {
    const targetTraces = selectedTimeBucket !== null
      ? (throughputData[selectedTimeBucket]?.traces || [])
      : traces;

    const stats = {};
    targetTraces.forEach((trace) => {
      if (!trace.agent) return;
      if (!stats[trace.agent]) {
        stats[trace.agent] = {
          agent: trace.agent,
          count: 0,
          totalDuration: 0,
          errors: 0,
          actions: {},
          tokens: { thinking: 0, input: 0, output: 0 },
        };
      }
      stats[trace.agent].count++;
      stats[trace.agent].totalDuration += trace.duration_ms || 0;
      if (trace.status === 'ERROR') stats[trace.agent].errors++;
      if (trace.tokens) {
        stats[trace.agent].tokens.thinking += trace.tokens.thinking || 0;
        stats[trace.agent].tokens.input += trace.tokens.input || 0;
        stats[trace.agent].tokens.output += trace.tokens.output || 0;
      }
      if (trace.action) {
        stats[trace.agent].actions[trace.action] = (stats[trace.agent].actions[trace.action] || 0) + 1;
      }
    });

    return Object.values(stats).sort((a, b) => b.count - a.count);
  }, [traces, throughputData, selectedTimeBucket]);

  // Aggregate action stats for selected time range (Agent#action level)
  const actionStats = useMemo(() => {
    const targetTraces = selectedTimeBucket !== null
      ? (throughputData[selectedTimeBucket]?.traces || [])
      : traces;

    const stats = {};
    targetTraces.forEach((trace) => {
      if (!trace.agent) return;
      const key = `${trace.agent}#${trace.action || 'unknown'}`;
      if (!stats[key]) {
        stats[key] = {
          key,
          agent: trace.agent,
          action: trace.action || 'unknown',
          count: 0,
          totalDuration: 0,
          errors: 0,
          minDuration: Infinity,
          maxDuration: 0,
          tokens: { thinking: 0, input: 0, output: 0 },
        };
      }
      stats[key].count++;
      stats[key].totalDuration += trace.duration_ms || 0;
      stats[key].minDuration = Math.min(stats[key].minDuration, trace.duration_ms || 0);
      stats[key].maxDuration = Math.max(stats[key].maxDuration, trace.duration_ms || 0);
      if (trace.status === 'ERROR') stats[key].errors++;
      if (trace.tokens) {
        stats[key].tokens.thinking += trace.tokens.thinking || 0;
        stats[key].tokens.input += trace.tokens.input || 0;
        stats[key].tokens.output += trace.tokens.output || 0;
      }
    });

    Object.values(stats).forEach((s) => {
      if (s.minDuration === Infinity) s.minDuration = 0;
    });

    return Object.values(stats).sort((a, b) => b.count - a.count);
  }, [traces, throughputData, selectedTimeBucket]);

  // Get available actions for the selected agent (for filter dropdown)
  const availableActions = useMemo(() => {
    if (filter.agent === 'all') {
      return actionStats.map((s) => s.key);
    }
    return actionStats.filter((s) => s.agent === filter.agent).map((s) => s.key);
  }, [filter.agent, actionStats]);

  // Span duration ranking for the Spans view (respects filters/time bucket)
  const spanStats = useMemo(() => buildSpanStats(filteredTraces), [filteredTraces]);

  // Chart click handler
  const handleChartClick = (data) => {
    if (data && data.activeTooltipIndex !== undefined) {
      const idx = data.activeTooltipIndex;
      setSelectedTimeBucket(selectedTimeBucket === idx ? null : idx);
      setSelectedTrace(null);
    }
  };

  const formatDuration = (ms) => {
    if (ms == null) return '—';
    if (ms < 1000) return `${Math.round(ms)}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatTokens = (tokens) => {
    if (!tokens) return '0';
    const total = (tokens.input || 0) + (tokens.output || 0) + (tokens.thinking || 0);
    if (total >= 1000) return `${(total / 1000).toFixed(1)}K`;
    return `${total}`;
  };

  const totalTokensOf = (tokens) =>
    (tokens?.input || 0) + (tokens?.output || 0) + (tokens?.thinking || 0);

  const formatCost = (cost) => {
    if (cost == null) return null;
    return `$${cost.toFixed(4)}`;
  };

  const getSpanIcon = (type) => {
    switch (type) {
      case 'root': return ICONS.spans.root;
      case 'prompt': return ICONS.spans.prompt;
      case 'generate': return ICONS.spans.generate;
      case 'llm': return ICONS.spans.llm;
      case 'thinking': return ICONS.spans.thinking;
      case 'tool': return ICONS.spans.tool;
      case 'response': return ICONS.spans.response;
      default: return '-';
    }
  };

  const isSuccess = (trace) => trace.status !== 'ERROR';

  const spanShareLabel = (span, trace) => {
    if (!trace.duration_ms) return formatDuration(span.duration);
    const share = ((span.duration || 0) / trace.duration_ms) * 100;
    return `${formatDuration(span.duration)} · ${share < 1 ? share.toFixed(2) : share.toFixed(1)}%`;
  };

  const spanTokens = (span) => {
    const tokens = span.tokens || {};
    return (tokens.input || 0) + (tokens.output || 0) + (tokens.thinking || 0);
  };

  // Attribute values that hold JSON payloads (tool inputs/outputs) get
  // pretty-printed blocks; everything else renders inline.
  const prettyAttribute = (value) => {
    if (typeof value !== 'string') return null;
    try {
      return JSON.stringify(JSON.parse(value), null, 2);
    } catch {
      return null;
    }
  };

  // Display order for span attributes: system message first, then the tool
  // roster, then everything else, with the (long) message history last.
  // jsonb storage normalizes key order, so sorting has to happen here.
  const attributeRank = (key) => {
    if (key.endsWith('.instructions')) return 0;
    if (key.endsWith('.tools')) return 1;
    if (key.endsWith('.messages')) return 3;
    return 2;
  };

  // Expanded detail panel for a single span (attributes, tokens, ids).
  const renderSpanDetails = (span, dark) => {
    const attributes = Object.entries(span.attributes || {}).sort(
      (a, b) => attributeRank(a[0]) - attributeRank(b[0])
    );
    const textColor = dark ? 'rgba(255,255,255,0.75)' : '#4b5563';
    const mutedColor = dark ? 'rgba(255,255,255,0.45)' : '#9ca3af';
    const preStyle = {
      background: dark ? 'rgba(255,255,255,0.06)' : '#eef0f3',
      borderRadius: '6px',
      padding: '6px 8px',
      margin: '2px 0 4px 0',
      overflowX: 'auto',
      whiteSpace: 'pre',
    };
    return (
      <div
        style={{
          margin: '4px 0 8px 176px',
          padding: '10px 12px',
          borderRadius: '8px',
          background: dark ? 'rgba(0,0,0,0.35)' : '#f9fafb',
          border: `1px solid ${dark ? 'rgba(255,255,255,0.1)' : '#e5e7eb'}`,
          fontFamily: TYPOGRAPHY.mono,
          fontSize: '12px',
          color: textColor,
        }}
      >
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 20px' }}>
          <span>duration: {formatDuration(span.duration)}</span>
          <span>status: {span.status || 'OK'}</span>
          {spanTokens(span) > 0 && (
            <span>
              tokens in:{span.tokens.input || 0} out:{span.tokens.output || 0}
              {span.tokens.thinking > 0 ? ` thinking:${span.tokens.thinking}` : ''}
            </span>
          )}
          <span style={{ color: mutedColor }}>span: {span.span_id}</span>
        </div>
        {attributes.length > 0 && (
          <div style={{ marginTop: '6px', display: 'grid', gap: '2px' }}>
            {attributes.map(([key, value]) => {
              const pretty = key.match(/args|result|input|output/) ? prettyAttribute(value) : null;
              // Plain-text prose (rendered instructions) gets a wrapped block
              // rather than one inline run-on line.
              const prose = !pretty && key.endsWith('.instructions') && typeof value === 'string' ? value : null;
              const block = pretty || prose;
              return (
                <div key={key} style={{ wordBreak: 'break-all' }}>
                  <span style={{ color: mutedColor }}>{key}:</span>{' '}
                  {block
                    ? <pre style={prose ? { ...preStyle, whiteSpace: 'pre-wrap' } : preStyle}>{block}</pre>
                    : (typeof value === 'string' ? value : JSON.stringify(value))}
                </div>
              );
            })}
          </div>
        )}
      </div>
    );
  };

  // Generation vs tool time for one trace: how much of the wall clock went
  // to the LLM, to each tool, and to unattributed overhead. Tool calls run
  // inside the provider's generate loop, so their time is subtracted from
  // the llm span to get pure generation time — the segments sum to ~100%.
  const traceTimeBreakdown = (trace) => {
    let generation = 0;
    const tools = [];
    (trace.spans || []).forEach((span) => {
      if ((span.nested || 0) === 0) return;
      if (span.type === 'tool') {
        tools.push(span);
      } else if (span.type === 'llm' || span.type === 'generate') {
        generation = Math.max(generation, span.duration || 0);
      }
    });
    const toolTotal = tools.reduce((sum, span) => sum + (span.duration || 0), 0);
    generation = Math.max(generation - toolTotal, 0);
    const total = trace.duration_ms || generation + toolTotal || 1;
    return { generation, tools, toolTotal, total, overhead: Math.max(total - generation - toolTotal, 0) };
  };

  const renderTraceBreakdown = (trace, dark) => {
    const { generation, tools, toolTotal, total, overhead } = traceTimeBreakdown(trace);
    if (generation === 0 && toolTotal === 0) return null;
    const muted = dark ? 'rgba(255,255,255,0.5)' : '#6b7280';
    const text = dark ? 'rgba(255,255,255,0.85)' : '#374151';
    const pct = (ms) => `${((ms / total) * 100).toFixed(ms / total < 0.01 ? 2 : 1)}%`;
    const segment = (ms, color) => (
      <div style={{ width: `${Math.max((ms / total) * 100, 0.4)}%`, background: color, height: '100%' }} />
    );
    return (
      <div style={{ marginTop: '14px', paddingTop: '12px', borderTop: `1px solid ${dark ? 'rgba(255,255,255,0.1)' : '#e5e7eb'}` }}>
        <div style={{ fontSize: '11px', textTransform: 'uppercase', letterSpacing: '0.05em', color: muted, marginBottom: '6px' }}>
          Time breakdown — generation vs tools
        </div>
        <div style={{ display: 'flex', height: '10px', borderRadius: '5px', overflow: 'hidden', background: dark ? 'rgba(255,255,255,0.08)' : '#f3f4f6' }}>
          {segment(generation, '#ef4444')}
          {segment(toolTotal, '#10b981')}
          {overhead > 0 && segment(overhead, dark ? 'rgba(255,255,255,0.2)' : '#d1d5db')}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 18px', marginTop: '8px', fontSize: '12px', fontFamily: TYPOGRAPHY.mono, color: text }}>
          <span><span style={{ color: '#ef4444' }}>■</span> generation {formatDuration(generation)} ({pct(generation)})</span>
          <span><span style={{ color: '#10b981' }}>■</span> tools {formatDuration(toolTotal)} ({pct(toolTotal)})</span>
          {overhead > 0 && <span><span style={{ color: muted }}>■</span> overhead {formatDuration(overhead)} ({pct(overhead)})</span>}
        </div>
        {tools.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 18px', marginTop: '4px', fontSize: '12px', fontFamily: TYPOGRAPHY.mono, color: muted }}>
            {tools.map((span, idx) => (
              <span key={idx}>{span.name} {formatDuration(span.duration)} ({pct(span.duration || 0)})</span>
            ))}
          </div>
        )}
      </div>
    );
  };

  // "Slowest operations" ranking across the filtered traces.
  const renderSpansBreakdown = (dark) => {
    const maxTotal = spanStats[0]?.total || 1;
    const cardBg = dark ? 'rgba(0,0,0,0.3)' : 'white';
    const border = dark ? '1px solid rgba(255,255,255,0.1)' : '1px solid #e5e7eb';
    const text = dark ? 'white' : '#111827';
    const muted = dark ? 'rgba(255,255,255,0.5)' : '#6b7280';
    const barColorByType = { llm: '#ef4444', tool: '#10b981', generate: '#8b5cf6', prompt: '#3b82f6' };
    return (
      <div style={{ padding: dark ? '0 24px 24px 24px' : 0 }}>
        <div style={{ background: cardBg, border, borderRadius: '12px', padding: '16px' }}>
          <div style={{ fontSize: '14px', fontWeight: 600, color: text, marginBottom: '4px' }}>
            Slowest operations
          </div>
          <div style={{ fontSize: '12px', color: muted, marginBottom: '14px' }}>
            Span durations aggregated across {filteredTraces.length} trace{filteredTraces.length === 1 ? '' : 's'} — ranked by total time
          </div>
          {spanStats.length === 0 ? (
            <div style={{ fontSize: '13px', color: muted, padding: '12px 0' }}>No spans in the current selection</div>
          ) : (
            <div style={{ display: 'grid', gap: '10px' }}>
              {spanStats.map((stat) => (
                <div key={stat.name} style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <div style={{ width: '220px', flexShrink: 0, display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ color: muted }}>{getSpanIcon(stat.type)}</span>
                    <span style={{ fontSize: '13px', color: stat.errors > 0 ? '#ef4444' : text, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {stat.name}
                    </span>
                  </div>
                  <div style={{ flex: 1, height: '18px', background: dark ? 'rgba(255,255,255,0.06)' : '#f3f4f6', borderRadius: '4px', position: 'relative' }}>
                    <div
                      style={{
                        position: 'absolute', top: '3px', left: 0, height: '12px', borderRadius: '3px',
                        width: `${Math.max((stat.total / maxTotal) * 100, 0.5)}%`,
                        background: barColorByType[stat.type] || '#6366f1',
                      }}
                    />
                  </div>
                  <div style={{ width: '260px', flexShrink: 0, fontSize: '12px', color: muted, fontFamily: TYPOGRAPHY.mono, textAlign: 'right' }}>
                    {stat.count}× · avg {formatDuration(stat.avg)} · max {formatDuration(stat.max)} · Σ {formatDuration(stat.total)}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    );
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  const summaryStats = {
    requests: throughputData.reduce((sum, b) => sum + b.requests, 0),
    errors: throughputData.reduce((sum, b) => sum + b.errors, 0),
    avgLatency: (() => {
      const withTraffic = throughputData.filter((b) => b.requests > 0);
      if (withTraffic.length === 0) return 0;
      return Math.round(withTraffic.reduce((sum, b) => sum + b.avgLatency, 0) / withTraffic.length);
    })(),
    throughput: (throughputData.reduce((sum, b) => sum + b.requests, 0) / WINDOW_MINUTES).toFixed(1),
  };

  const emptyState = traces.length === 0;

  // Dark mode uses lander CSS classes, light mode uses Tailwind
  if (darkMode) {
    return (
      <div className="preview-content" style={{ borderRadius: '12px', overflow: 'hidden', minHeight: 'calc(100vh - 200px)' }}>
        {/* Header inside dark container */}
        <div style={{ padding: '24px 24px 0 24px', borderBottom: '1px solid rgba(255,255,255,0.1)', marginBottom: '16px', paddingBottom: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              {!embedded && <h1 style={{ fontSize: '24px', fontWeight: 'bold', color: 'white', margin: 0 }}>Traces</h1>}
              <p style={{ fontSize: '14px', color: 'rgba(255,255,255,0.6)', marginTop: '4px' }}>
                {selectedTimeBucket !== null
                  ? `Viewing ${throughputData[selectedTimeBucket]?.time} • ${filteredTraces.length} requests`
                  : `Last ${WINDOW_MINUTES} minutes • Click timeline to drill down`}
              </p>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              {/* View Mode Toggle */}
              <div style={{ display: 'flex', background: 'rgba(255,255,255,0.1)', borderRadius: '8px', padding: '2px' }}>
                {['timeline', 'agents', 'actions', 'spans'].map((mode) => (
                  <button
                    key={mode}
                    onClick={() => setViewMode(mode)}
                    style={{
                      padding: '6px 12px',
                      background: viewMode === mode ? '#ef4444' : 'transparent',
                      color: 'white',
                      borderRadius: '6px',
                      border: 'none',
                      fontSize: '13px',
                      cursor: 'pointer',
                      textTransform: 'capitalize',
                    }}
                  >
                    {mode}
                  </button>
                ))}
              </div>
              {!agentClass && (
              <select
                value={filter.agent}
                onChange={(e) => setFilter({ ...filter, agent: e.target.value, action: 'all' })}
                style={{
                  padding: '8px 12px',
                  background: 'rgba(255,255,255,0.1)',
                  border: '1px solid rgba(255,255,255,0.2)',
                  borderRadius: '8px',
                  color: 'white',
                  fontSize: '14px'
                }}
              >
                <option value="all">All Agents</option>
                {agentsList.map((agent) => (
                  <option key={agent} value={agent}>{agent}</option>
                ))}
              </select>
              )}
              <select
                value={filter.action}
                onChange={(e) => setFilter({ ...filter, action: e.target.value })}
                style={{
                  padding: '8px 12px',
                  background: filter.action !== 'all' ? 'rgba(239, 68, 68, 0.3)' : 'rgba(255,255,255,0.1)',
                  border: filter.action !== 'all' ? '1px solid #ef4444' : '1px solid rgba(255,255,255,0.2)',
                  borderRadius: '8px',
                  color: 'white',
                  fontSize: '14px'
                }}
              >
                <option value="all">All Actions</option>
                {availableActions.map((action) => (
                  <option key={action} value={action}>{action}</option>
                ))}
              </select>
              <select
                value={filter.status}
                onChange={(e) => setFilter({ ...filter, status: e.target.value })}
                style={{
                  padding: '8px 12px',
                  background: 'rgba(255,255,255,0.1)',
                  border: '1px solid rgba(255,255,255,0.2)',
                  borderRadius: '8px',
                  color: 'white',
                  fontSize: '14px'
                }}
              >
                <option value="all">All Status</option>
                <option value="success">Success</option>
                <option value="error">Error</option>
              </select>
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value)}
                style={{
                  padding: '8px 12px',
                  background: 'rgba(255,255,255,0.1)',
                  border: '1px solid rgba(255,255,255,0.2)',
                  borderRadius: '8px',
                  color: 'white',
                  fontSize: '14px'
                }}
              >
                <option value="time">Newest first</option>
                <option value="latency">Slowest first</option>
              </select>
              {selectedTimeBucket !== null && (
                <button
                  onClick={() => setSelectedTimeBucket(null)}
                  style={{
                    padding: '8px 16px',
                    background: 'rgba(255,255,255,0.2)',
                    color: 'white',
                    borderRadius: '8px',
                    border: 'none',
                    fontSize: '14px',
                    fontWeight: '500',
                    cursor: 'pointer'
                  }}
                >
                  Clear Selection
                </button>
              )}
            </div>
          </div>
        </div>

        {loadError && (
          <div style={{ margin: '0 24px 16px 24px', padding: '12px 16px', background: 'rgba(239, 68, 68, 0.1)', borderRadius: '8px', color: '#ef4444', fontSize: '13px' }}>
            Failed to load traces: {loadError}
          </div>
        )}

        {/* Throughput Chart - New Relic style */}
        <div style={{ padding: '0 24px', marginBottom: '24px' }}>
          <div style={{
            background: 'rgba(0,0,0,0.3)',
            borderRadius: '12px',
            padding: '16px',
            border: '1px solid rgba(255,255,255,0.1)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
              <div style={{ fontSize: '14px', fontWeight: '600', color: 'white' }}>
                Agent Requests / Minute
              </div>
              <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
                {Object.entries(agentColors).map(([agent, color]) => (
                  <div key={agent} style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <div style={{ width: '10px', height: '10px', borderRadius: '2px', background: color }} />
                    <span style={{ fontSize: '11px', color: 'rgba(255,255,255,0.7)' }}>
                      {agent.replace('Agent', '')}
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <div style={{ height: '150px' }}>
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart
                  data={throughputData}
                  onClick={handleChartClick}
                  style={{ cursor: 'pointer' }}
                >
                  <defs>
                    {Object.entries(agentColors).map(([agent, color]) => (
                      <linearGradient key={agent} id={`gradient-${agent}`} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor={color} stopOpacity={0.8}/>
                        <stop offset="95%" stopColor={color} stopOpacity={0.1}/>
                      </linearGradient>
                    ))}
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                  <XAxis
                    dataKey="time"
                    stroke="rgba(255,255,255,0.5)"
                    tick={{ fontSize: 10, fill: 'rgba(255,255,255,0.5)' }}
                    tickLine={false}
                    interval={4}
                  />
                  <YAxis
                    stroke="rgba(255,255,255,0.5)"
                    tick={{ fontSize: 10, fill: 'rgba(255,255,255,0.5)' }}
                    tickLine={false}
                    axisLine={false}
                    allowDecimals={false}
                  />
                  <Tooltip
                    contentStyle={{
                      background: 'rgba(0,0,0,0.9)',
                      border: '1px solid rgba(255,255,255,0.2)',
                      borderRadius: '8px',
                      padding: '12px'
                    }}
                    labelStyle={{ color: 'white', fontWeight: '600', marginBottom: '8px' }}
                    itemStyle={{ color: 'rgba(255,255,255,0.8)', fontSize: '12px' }}
                    formatter={(value, name) => [value, name.replace('Agent', '')]}
                  />
                  {Object.keys(agentColors).map((agent) => (
                    <Area
                      key={agent}
                      type="monotone"
                      dataKey={agent}
                      stackId="1"
                      stroke={agentColors[agent]}
                      fill={`url(#gradient-${agent})`}
                    />
                  ))}
                </AreaChart>
              </ResponsiveContainer>
            </div>
            {/* Summary Stats */}
            <div style={{ display: 'flex', gap: '24px', marginTop: '12px', paddingTop: '12px', borderTop: '1px solid rgba(255,255,255,0.1)' }}>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: 'white' }}>
                  {summaryStats.requests}
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Total Requests</div>
              </div>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: '#ef4444' }}>
                  {summaryStats.errors}
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Errors</div>
              </div>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: '#10b981' }}>
                  {summaryStats.avgLatency}ms
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Avg Latency</div>
              </div>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: '#f59e0b' }}>
                  {summaryStats.throughput}/min
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Throughput</div>
              </div>
            </div>
          </div>
        </div>

        {/* Agent Breakdown View */}
        {viewMode === 'agents' && (
          <div style={{ padding: '0 24px', marginBottom: '24px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '16px' }}>
              {agentStats.map((stat) => (
                <div
                  key={stat.agent}
                  style={{
                    background: 'rgba(0,0,0,0.3)',
                    borderRadius: '12px',
                    padding: '16px',
                    border: `1px solid ${agentColors[stat.agent]}40`,
                    cursor: 'pointer',
                  }}
                  onClick={() => setFilter({ ...filter, agent: filter.agent === stat.agent ? 'all' : stat.agent })}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                    <div style={{
                      width: '8px',
                      height: '8px',
                      borderRadius: '50%',
                      background: agentColors[stat.agent]
                    }} />
                    <span style={{ fontSize: '15px', fontWeight: '600', color: 'white' }}>
                      {stat.agent}
                    </span>
                    <span style={{
                      marginLeft: 'auto',
                      fontSize: '13px',
                      padding: '2px 8px',
                      background: agentColors[stat.agent] + '30',
                      color: agentColors[stat.agent],
                      borderRadius: '4px'
                    }}>
                      {stat.count} calls
                    </span>
                  </div>

                  {/* Agent Metrics */}
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px', marginBottom: '12px' }}>
                    <div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Avg Latency</div>
                      <div style={{ fontSize: '14px', color: 'white' }}>
                        {Math.round(stat.totalDuration / stat.count)}ms
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Total Tokens</div>
                      <div style={{ fontSize: '14px', color: 'white' }}>
                        {totalTokensOf(stat.tokens).toLocaleString()}
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Error Rate</div>
                      <div style={{ fontSize: '14px', color: stat.errors > 0 ? '#ef4444' : '#10b981' }}>
                        {((stat.errors / stat.count) * 100).toFixed(1)}%
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Thinking Tokens</div>
                      <div style={{ fontSize: '14px', color: 'white' }}>
                        {stat.tokens.thinking.toLocaleString()}
                      </div>
                    </div>
                  </div>

                  {/* Actions Breakdown - clickable */}
                  <div style={{ borderTop: '1px solid rgba(255,255,255,0.1)', paddingTop: '10px' }}>
                    <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)', marginBottom: '6px' }}>Actions (click to filter)</div>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                      {Object.entries(stat.actions).map(([action, count]) => {
                        const actionKey = `${stat.agent}#${action}`;
                        const isActive = filter.action === actionKey;
                        return (
                          <span
                            key={action}
                            onClick={(e) => {
                              e.stopPropagation();
                              setFilter({ ...filter, action: isActive ? 'all' : actionKey });
                              setViewMode('timeline');
                            }}
                            style={{
                              fontSize: '11px',
                              padding: '3px 8px',
                              background: isActive ? '#ef4444' : 'rgba(255,255,255,0.1)',
                              borderRadius: '4px',
                              color: isActive ? 'white' : 'rgba(255,255,255,0.8)',
                              cursor: 'pointer',
                              transition: 'all 0.15s'
                            }}
                          >
                            {action} ({count})
                          </span>
                        );
                      })}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Actions Breakdown View - per Agent#action */}
        {viewMode === 'actions' && (
          <div style={{ padding: '0 24px', marginBottom: '24px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '12px' }}>
              {actionStats.map((stat) => {
                const isActive = filter.action === stat.key;
                return (
                  <div
                    key={stat.key}
                    onClick={() => {
                      setFilter({ ...filter, action: isActive ? 'all' : stat.key });
                      setViewMode('timeline');
                    }}
                    style={{
                      background: isActive ? 'rgba(239, 68, 68, 0.15)' : 'rgba(0,0,0,0.3)',
                      borderRadius: '10px',
                      padding: '14px',
                      border: isActive ? '1px solid #ef4444' : `1px solid ${agentColors[stat.agent]}30`,
                      cursor: 'pointer',
                      transition: 'all 0.15s'
                    }}
                  >
                    {/* Header: Agent#action */}
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '10px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <div style={{
                          width: '6px',
                          height: '6px',
                          borderRadius: '50%',
                          background: agentColors[stat.agent]
                        }} />
                        <span style={{ fontSize: '14px', fontWeight: '600', color: 'white' }}>
                          {stat.agent}
                        </span>
                        <span style={{ fontSize: '13px', color: 'rgba(255,255,255,0.7)' }}>
                          #{stat.action}
                        </span>
                      </div>
                      <span style={{
                        fontSize: '12px',
                        padding: '2px 8px',
                        background: agentColors[stat.agent] + '30',
                        color: agentColors[stat.agent],
                        borderRadius: '4px'
                      }}>
                        {stat.count} calls
                      </span>
                    </div>

                    {/* Metrics Row */}
                    <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
                      <div>
                        <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)' }}>Avg</div>
                        <div style={{ fontSize: '13px', color: 'white', fontWeight: '500' }}>
                          {Math.round(stat.totalDuration / stat.count)}ms
                        </div>
                      </div>
                      <div>
                        <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)' }}>Min/Max</div>
                        <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.8)' }}>
                          {Math.round(stat.minDuration)}ms / {Math.round(stat.maxDuration)}ms
                        </div>
                      </div>
                      <div>
                        <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)' }}>Errors</div>
                        <div style={{ fontSize: '13px', color: stat.errors > 0 ? '#ef4444' : '#10b981' }}>
                          {stat.errors} ({((stat.errors / stat.count) * 100).toFixed(0)}%)
                        </div>
                      </div>
                      <div>
                        <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)' }}>Tokens</div>
                        <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.8)' }}>
                          {totalTokensOf(stat.tokens).toLocaleString()}
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Span Duration Breakdown View */}
        {viewMode === 'spans' && renderSpansBreakdown(true)}

        {/* Trace List */}
        {viewMode === 'timeline' && !emptyState && (
        <div className="preview-traces">
          {filteredTraces.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '32px' }}>
              <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: '14px' }}>
                No traces match filters
              </div>
            </div>
          ) : filteredTraces.map((trace) => (
            <React.Fragment key={trace.id}>
              <div
                className="trace-header-row"
                onClick={() => setSelectedTrace(selectedTrace === trace.id ? null : trace.id)}
                style={{ cursor: 'pointer' }}
              >
                <div className="trace-id">
                  <span className="trace-badge">TRACE</span>
                  <span className="trace-hash">{trace.short_id}</span>
                  <span style={{ marginLeft: '12px', color: 'rgba(255,255,255,0.9)', fontWeight: '500' }}>
                    {trace.display_name}
                  </span>
                </div>
                <div className="trace-meta">
                  {trace.model && (
                    <span
                      className="meta-item"
                      title="Model that generated this trace"
                      style={{ fontFamily: TYPOGRAPHY.mono, background: 'rgba(99,102,241,0.2)', color: '#a5b4fc', padding: '2px 8px', borderRadius: '4px' }}
                    >
                      {trace.model}
                    </span>
                  )}
                  <span className="meta-item"><i className="fa-solid fa-clock"></i> {formatDuration(trace.duration_ms)}</span>
                  <span className="meta-item">{formatTokens(trace.tokens)} tokens</span>
                  {trace.estimated_cost != null && (
                    <span className="meta-item"><i className="fa-solid fa-coins"></i> {formatCost(trace.estimated_cost)}</span>
                  )}
                  <span className={`meta-item ${isSuccess(trace) ? 'success' : 'error'}`}>
                    <i className={`fa-solid ${isSuccess(trace) ? 'fa-check' : 'fa-xmark'}`}></i> {isSuccess(trace) ? 'OK' : 'ERROR'}
                  </span>
                </div>
              </div>

              {selectedTrace === trace.id && (
                <div className="trace-timeline">
                  <div className="timeline-scale">
                    <span>0ms</span>
                    <span>{Math.round((trace.duration_ms || 0) * 0.33)}ms</span>
                    <span>{Math.round((trace.duration_ms || 0) * 0.66)}ms</span>
                    <span>{formatDuration(trace.duration_ms)}</span>
                  </div>

                  {(trace.spans || []).map((span, idx) => {
                    const spanKey = `${trace.id}:${idx}`;
                    const isSpanExpanded = expandedSpan === spanKey;
                    return (
                      <React.Fragment key={idx}>
                        <div
                          className={`span-row ${span.nested ? `nested-${Math.min(span.nested, 3)}` : ''}`}
                          onClick={() => setExpandedSpan(isSpanExpanded ? null : spanKey)}
                          style={{ cursor: 'pointer' }}
                          title="Click for span details"
                        >
                          <div className="span-label">
                            <span className={`span-icon ${span.type}`}>{getSpanIcon(span.type)}</span>
                            <span className={`span-name ${span.error ? 'error' : ''}`}>{span.name}</span>
                          </div>
                          <div className="span-bar-container">
                            <div
                              className={`span-bar ${span.type} ${span.error ? 'error' : ''}`}
                              style={{
                                left: `${trace.duration_ms ? (span.start / trace.duration_ms) * 100 : 0}%`,
                                width: `${trace.duration_ms ? Math.max((span.duration / trace.duration_ms) * 100, 2) : 2}%`
                              }}
                            ></div>
                          </div>
                          <span
                            style={{
                              flexShrink: 0, width: '130px', textAlign: 'right', fontSize: '11px',
                              fontFamily: TYPOGRAPHY.mono, color: 'rgba(255,255,255,0.55)', paddingLeft: '8px'
                            }}
                          >
                            {spanShareLabel(span, trace)}
                          </span>
                        </div>
                        {isSpanExpanded && renderSpanDetails(span, true)}
                      </React.Fragment>
                    );
                  })}

                  {renderTraceBreakdown(trace, true)}

                  {/* Token Breakdown Row */}
                  <div className="span-row nested-3">
                    <div className="span-label">
                      <span className="span-icon" style={{ fontFamily: TYPOGRAPHY.mono }}>+--</span>
                      <span className="span-name tokens" style={{ fontFamily: TYPOGRAPHY.mono }}>
                        {totalTokensOf(trace.tokens).toLocaleString()} tokens
                      </span>
                    </div>
                    <div className="span-bar-container">
                      <div className="token-breakdown" style={{ fontFamily: TYPOGRAPHY.mono }}>
                        {trace.tokens.thinking > 0 && (
                          <span className="token-thinking">T:{trace.tokens.thinking.toLocaleString()}</span>
                        )}
                        <span className="token-in">in:{trace.tokens.input.toLocaleString()}</span>
                        <span className="token-out">out:{trace.tokens.output.toLocaleString()}</span>
                      </div>
                    </div>
                  </div>

                  {trace.error && (
                    <div style={{ padding: '12px 16px', background: 'rgba(239, 68, 68, 0.1)', borderRadius: '6px', marginTop: '12px' }}>
                      <span style={{ color: '#ef4444', fontSize: '13px' }}>
                        <i className="fa-solid fa-exclamation-triangle" style={{ marginRight: '8px' }}></i>
                        {trace.error}
                      </span>
                    </div>
                  )}
                </div>
              )}
            </React.Fragment>
          ))}
        </div>
        )}

        {emptyState && viewMode === 'timeline' && (
          <div style={{ textAlign: 'center', padding: '48px 0' }}>
            <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: '18px' }}>No traces yet</div>
            <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: '14px', marginTop: '8px' }}>
              Run an agent, or point your app's ActiveAgent telemetry at this workspace to see traces appear here
            </p>
          </div>
        )}
      </div>
    );
  }

  // Light mode - Tailwind classes
  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Traces</h1>
          <p className="text-sm text-gray-500">
            {selectedTimeBucket !== null
              ? `Viewing ${throughputData[selectedTimeBucket]?.time} • ${filteredTraces.length} requests`
              : `Last ${WINDOW_MINUTES} minutes • Click timeline to drill down`}
          </p>
        </div>
        <div className="flex items-center space-x-3">
          {/* View Mode Toggle */}
          <div className="flex bg-gray-100 rounded-lg p-1">
            {['timeline', 'agents', 'actions', 'spans'].map((mode) => (
              <button
                key={mode}
                onClick={() => setViewMode(mode)}
                className={`px-3 py-1 text-sm rounded-md transition-colors capitalize ${
                  viewMode === mode ? 'bg-white shadow text-gray-900' : 'text-gray-600'
                }`}
              >
                {mode}
              </button>
            ))}
          </div>
          <select
            value={filter.agent}
            onChange={(e) => setFilter({ ...filter, agent: e.target.value, action: 'all' })}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500"
          >
            <option value="all">All Agents</option>
            {agentsList.map((agent) => (
              <option key={agent} value={agent}>{agent}</option>
            ))}
          </select>
          <select
            value={filter.action}
            onChange={(e) => setFilter({ ...filter, action: e.target.value })}
            className={`px-3 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-red-500 ${
              filter.action !== 'all' ? 'border-red-500 bg-red-50' : 'border-gray-300'
            }`}
          >
            <option value="all">All Actions</option>
            {availableActions.map((action) => (
              <option key={action} value={action}>{action}</option>
            ))}
          </select>
          <select
            value={filter.status}
            onChange={(e) => setFilter({ ...filter, status: e.target.value })}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500"
          >
            <option value="all">All Status</option>
            <option value="success">Success</option>
            <option value="error">Error</option>
          </select>
          <select
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500"
          >
            <option value="time">Newest first</option>
            <option value="latency">Slowest first</option>
          </select>
          {selectedTimeBucket !== null && (
            <button
              onClick={() => setSelectedTimeBucket(null)}
              className="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors text-sm font-medium"
            >
              Clear Selection
            </button>
          )}
        </div>
      </div>

      {loadError && (
        <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">
          Failed to load traces: {loadError}
        </div>
      )}

      {/* Throughput Chart */}
      <div className="bg-white rounded-xl border border-gray-200 p-4">
        <div className="flex justify-between items-center mb-3">
          <h3 className="text-sm font-semibold text-gray-700">Agent Requests / Minute</h3>
          <div className="flex gap-4 flex-wrap">
            {Object.entries(agentColors).map(([agent, color]) => (
              <div key={agent} className="flex items-center gap-1.5">
                <div className="w-2.5 h-2.5 rounded-sm" style={{ background: color }} />
                <span className="text-xs text-gray-500">{agent.replace('Agent', '')}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="h-36">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={throughputData} onClick={handleChartClick} style={{ cursor: 'pointer' }}>
              <defs>
                {Object.entries(agentColors).map(([agent, color]) => (
                  <linearGradient key={agent} id={`gradient-light-${agent}`} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={color} stopOpacity={0.6}/>
                    <stop offset="95%" stopColor={color} stopOpacity={0.05}/>
                  </linearGradient>
                ))}
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis
                dataKey="time"
                stroke="#9ca3af"
                tick={{ fontSize: 10, fill: '#6b7280' }}
                tickLine={false}
                interval={4}
              />
              <YAxis
                stroke="#9ca3af"
                tick={{ fontSize: 10, fill: '#6b7280' }}
                tickLine={false}
                axisLine={false}
                allowDecimals={false}
              />
              <Tooltip
                contentStyle={{
                  background: 'white',
                  border: '1px solid #e5e7eb',
                  borderRadius: '8px',
                  boxShadow: '0 4px 6px -1px rgba(0,0,0,0.1)'
                }}
                labelStyle={{ color: '#111827', fontWeight: '600', marginBottom: '8px' }}
                formatter={(value, name) => [value, name.replace('Agent', '')]}
              />
              {Object.keys(agentColors).map((agent) => (
                <Area
                  key={agent}
                  type="monotone"
                  dataKey={agent}
                  stackId="1"
                  stroke={agentColors[agent]}
                  fill={`url(#gradient-light-${agent})`}
                />
              ))}
            </AreaChart>
          </ResponsiveContainer>
        </div>
        {/* Summary Stats */}
        <div className="flex gap-6 mt-3 pt-3 border-t border-gray-100">
          <div>
            <div className="text-lg font-bold text-gray-900">{summaryStats.requests}</div>
            <div className="text-xs text-gray-500">Total Requests</div>
          </div>
          <div>
            <div className="text-lg font-bold text-red-500">{summaryStats.errors}</div>
            <div className="text-xs text-gray-500">Errors</div>
          </div>
          <div>
            <div className="text-lg font-bold text-green-600">{summaryStats.avgLatency}ms</div>
            <div className="text-xs text-gray-500">Avg Latency</div>
          </div>
          <div>
            <div className="text-lg font-bold text-amber-500">{summaryStats.throughput}/min</div>
            <div className="text-xs text-gray-500">Throughput</div>
          </div>
        </div>
      </div>

      {/* Agent Breakdown View */}
      {viewMode === 'agents' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {agentStats.map((stat) => (
            <div
              key={stat.agent}
              className="bg-white rounded-xl border border-gray-200 p-4 cursor-pointer hover:border-gray-300 transition-colors"
              style={{ borderLeftColor: agentColors[stat.agent], borderLeftWidth: '4px' }}
              onClick={() => setFilter({ ...filter, agent: filter.agent === stat.agent ? 'all' : stat.agent })}
            >
              <div className="flex items-center justify-between mb-3">
                <span className="font-semibold text-gray-900">{stat.agent}</span>
                <span
                  className="text-sm px-2 py-0.5 rounded"
                  style={{ background: agentColors[stat.agent] + '20', color: agentColors[stat.agent] }}
                >
                  {stat.count} calls
                </span>
              </div>
              <div className="grid grid-cols-2 gap-2 text-sm mb-3">
                <div>
                  <div className="text-gray-500 text-xs">Avg Latency</div>
                  <div className="font-medium">{Math.round(stat.totalDuration / stat.count)}ms</div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Total Tokens</div>
                  <div className="font-medium">{totalTokensOf(stat.tokens).toLocaleString()}</div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Error Rate</div>
                  <div className={`font-medium ${stat.errors > 0 ? 'text-red-600' : 'text-green-600'}`}>
                    {((stat.errors / stat.count) * 100).toFixed(1)}%
                  </div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Thinking Tokens</div>
                  <div className="font-medium">{stat.tokens.thinking.toLocaleString()}</div>
                </div>
              </div>
              <div className="border-t border-gray-100 pt-2">
                <div className="text-xs text-gray-500 mb-1">Actions (click to filter)</div>
                <div className="flex flex-wrap gap-1">
                  {Object.entries(stat.actions).map(([action, count]) => {
                    const actionKey = `${stat.agent}#${action}`;
                    const isActive = filter.action === actionKey;
                    return (
                      <span
                        key={action}
                        onClick={(e) => {
                          e.stopPropagation();
                          setFilter({ ...filter, action: isActive ? 'all' : actionKey });
                          setViewMode('timeline');
                        }}
                        className={`text-xs px-2 py-0.5 rounded cursor-pointer transition-colors ${
                          isActive ? 'bg-red-500 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                        }`}
                      >
                        {action} ({count})
                      </span>
                    );
                  })}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Actions Breakdown View - per Agent#action */}
      {viewMode === 'actions' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {actionStats.map((stat) => {
            const isActive = filter.action === stat.key;
            return (
              <div
                key={stat.key}
                onClick={() => {
                  setFilter({ ...filter, action: isActive ? 'all' : stat.key });
                  setViewMode('timeline');
                }}
                className={`rounded-xl p-4 cursor-pointer transition-all ${
                  isActive
                    ? 'bg-red-50 border-2 border-red-500'
                    : 'bg-white border border-gray-200 hover:border-gray-300'
                }`}
                style={{ borderLeftColor: agentColors[stat.agent], borderLeftWidth: isActive ? '2px' : '4px' }}
              >
                {/* Header: Agent#action */}
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <div
                      className="w-2 h-2 rounded-full"
                      style={{ background: agentColors[stat.agent] }}
                    />
                    <span className="font-semibold text-gray-900">{stat.agent}</span>
                    <span className="text-gray-500">#{stat.action}</span>
                  </div>
                  <span
                    className="text-xs px-2 py-0.5 rounded"
                    style={{ background: agentColors[stat.agent] + '20', color: agentColors[stat.agent] }}
                  >
                    {stat.count} calls
                  </span>
                </div>

                {/* Metrics Row */}
                <div className="flex flex-wrap gap-4 text-sm">
                  <div>
                    <div className="text-xs text-gray-500">Avg</div>
                    <div className="font-medium">{Math.round(stat.totalDuration / stat.count)}ms</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Min/Max</div>
                    <div className="text-gray-600">{Math.round(stat.minDuration)}ms / {Math.round(stat.maxDuration)}ms</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Errors</div>
                    <div className={stat.errors > 0 ? 'text-red-600' : 'text-green-600'}>
                      {stat.errors} ({((stat.errors / stat.count) * 100).toFixed(0)}%)
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Tokens</div>
                    <div className="text-gray-600">{totalTokensOf(stat.tokens).toLocaleString()}</div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Span Duration Breakdown View */}
      {viewMode === 'spans' && renderSpansBreakdown(false)}

      {/* Trace List */}
      {viewMode === 'timeline' && !emptyState && (
      <div className="space-y-4">
        {filteredTraces.length === 0 ? (
          <div className="text-center py-8 text-gray-500">No traces match filters</div>
        ) : filteredTraces.map((trace) => (
          <div
            key={trace.id}
            className="bg-white rounded-xl border border-gray-200 overflow-hidden hover:border-gray-300 transition-colors"
          >
            {/* Trace Header */}
            <div
              className="p-4 flex items-center justify-between cursor-pointer hover:bg-gray-50"
              onClick={() => setSelectedTrace(selectedTrace === trace.id ? null : trace.id)}
            >
              <div className="flex items-center space-x-4">
                <div className="flex items-center space-x-2">
                  <span className="px-2 py-1 bg-gray-100 text-gray-600 text-xs font-mono rounded">TRACE</span>
                  <span className="text-sm font-mono text-gray-500">{trace.short_id}</span>
                </div>
                <span className="text-sm font-medium text-gray-900">
                  {trace.display_name}
                </span>
              </div>
              <div className="flex items-center space-x-4">
                {trace.model && (
                  <span
                    className="text-xs px-2 py-0.5 rounded bg-indigo-50 text-indigo-700"
                    style={{ fontFamily: TYPOGRAPHY.mono }}
                    title="Model that generated this trace"
                  >
                    {trace.model}
                  </span>
                )}
                <span className="text-sm text-gray-500">
                  <i className="fa-solid fa-clock mr-1"></i>
                  {formatDuration(trace.duration_ms)}
                </span>
                <span className="text-sm text-gray-500">
                  {formatTokens(trace.tokens)} tokens
                </span>
                {trace.estimated_cost != null && (
                  <span className="text-sm text-gray-500">
                    <i className="fa-solid fa-coins mr-1"></i>
                    {formatCost(trace.estimated_cost)}
                  </span>
                )}
                <span className={`text-sm ${isSuccess(trace) ? 'text-green-600' : 'text-red-600'}`}>
                  <i className={`fa-solid ${isSuccess(trace) ? 'fa-check' : 'fa-xmark'} mr-1`}></i>
                  {isSuccess(trace) ? 'OK' : 'ERROR'}
                </span>
              </div>
            </div>

            {/* Expanded Timeline */}
            {selectedTrace === trace.id && (
              <div className="border-t border-gray-100 p-4 bg-gray-50">
                <div className="flex justify-between text-xs text-gray-400 mb-2 px-32">
                  <span>0ms</span>
                  <span>{Math.round((trace.duration_ms || 0) * 0.33)}ms</span>
                  <span>{Math.round((trace.duration_ms || 0) * 0.66)}ms</span>
                  <span>{formatDuration(trace.duration_ms)}</span>
                </div>

                <div className="space-y-2">
                  {(trace.spans || []).map((span, idx) => {
                    const spanKey = `${trace.id}:${idx}`;
                    const isSpanExpanded = expandedSpan === spanKey;
                    return (
                      <React.Fragment key={idx}>
                        <div
                          className="flex items-center group cursor-pointer hover:bg-gray-100 rounded"
                          style={{ paddingLeft: `${(span.nested || 0) * 16}px` }}
                          onClick={() => setExpandedSpan(isSpanExpanded ? null : spanKey)}
                          title="Click for span details"
                        >
                          <div className="w-40 flex items-center space-x-2 flex-shrink-0">
                            <span className={span.type === 'thinking' ? '' : 'text-gray-400'}>
                              {getSpanIcon(span.type)}
                            </span>
                            <span className={`text-sm truncate ${span.error ? 'text-red-600' : 'text-gray-700'}`}>
                              {span.name}
                            </span>
                          </div>
                          <div className="flex-1 h-6 relative bg-gray-100 rounded">
                            <div
                              className={`absolute h-4 top-1 rounded transition-opacity ${
                                span.type === 'root' ? 'bg-gray-400' :
                                span.type === 'prompt' ? 'bg-blue-400' :
                                span.type === 'generate' ? 'bg-purple-500' :
                                span.type === 'llm' ? 'bg-red-500' :
                                span.type === 'thinking' ? 'bg-amber-400' :
                                span.type === 'tool' ? 'bg-green-500' :
                                span.type === 'response' ? 'bg-teal-400' : 'bg-gray-300'
                              } ${span.error ? 'bg-red-400' : ''}`}
                              style={{
                                left: `${trace.duration_ms ? (span.start / trace.duration_ms) * 100 : 0}%`,
                                width: `${trace.duration_ms ? Math.max((span.duration / trace.duration_ms) * 100, 1) : 1}%`
                              }}
                            />
                          </div>
                          <span
                            className="flex-shrink-0 text-right text-xs text-gray-400 pl-2"
                            style={{ width: '130px', fontFamily: TYPOGRAPHY.mono }}
                          >
                            {spanShareLabel(span, trace)}
                          </span>
                        </div>
                        {isSpanExpanded && renderSpanDetails(span, false)}
                      </React.Fragment>
                    );
                  })}
                </div>

                {renderTraceBreakdown(trace, false)}

                <div className="mt-4 pt-4 border-t border-gray-200 flex items-center space-x-6">
                  <span className="text-sm text-gray-500">Tokens:</span>
                  {trace.tokens.thinking > 0 && (
                    <span className="text-sm text-amber-600" style={{ fontFamily: TYPOGRAPHY.mono }}>T:{trace.tokens.thinking.toLocaleString()}</span>
                  )}
                  <span className="text-sm text-blue-600" style={{ fontFamily: TYPOGRAPHY.mono }}>in:{trace.tokens.input.toLocaleString()}</span>
                  <span className="text-sm text-green-600" style={{ fontFamily: TYPOGRAPHY.mono }}>out:{trace.tokens.output.toLocaleString()}</span>
                  {trace.provider && (
                    <span className="text-sm text-gray-500" style={{ fontFamily: TYPOGRAPHY.mono }}>{trace.provider}{trace.model ? ` · ${trace.model}` : ''}</span>
                  )}
                </div>

                {trace.error && (
                  <div className="mt-4 p-3 bg-red-50 border border-red-200 rounded-lg">
                    <span className="text-sm text-red-700">{trace.error}</span>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
      </div>
      )}

      {emptyState && viewMode === 'timeline' && (
        <div className="text-center py-12">
          <div className="text-gray-400 text-lg">No traces yet</div>
          <p className="text-gray-500 text-sm mt-2">
            Run an agent, or point your app's ActiveAgent telemetry at this workspace to see traces appear here
          </p>
        </div>
      )}
    </div>
  );
}
