import React, { useState, useEffect, useMemo } from 'react';
import { useTheme } from '../../contexts/ThemeContext';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  BarChart, Bar
} from 'recharts';
import { ICONS, TYPOGRAPHY, getThemeColors, cardStyle, buttonStyle } from '../../utils/designTokens';

// Agent types and their actions
const AGENT_ACTIONS = {
  TranslationAgent: ['translate', 'detect_language', 'batch_translate'],
  CodeReviewAgent: ['review', 'analyze_code', 'suggest_fixes', 'security_scan'],
  DocumentationAgent: ['generate_docs', 'update_readme', 'extract_types'],
  SupportAgent: ['respond', 'escalate', 'search_kb', 'create_ticket'],
  DataAnalysisAgent: ['analyze', 'generate_report', 'visualize', 'predict'],
};

const AGENT_COLORS = {
  TranslationAgent: '#6366f1',
  CodeReviewAgent: '#10b981',
  DocumentationAgent: '#f59e0b',
  SupportAgent: '#ec4899',
  DataAnalysisAgent: '#3b82f6',
};

// Generate time-series throughput data (last 30 minutes, 1-minute buckets)
const generateThroughputData = () => {
  const now = Date.now();
  const data = [];
  const agents = Object.keys(AGENT_ACTIONS);

  for (let i = 29; i >= 0; i--) {
    const timestamp = new Date(now - i * 60000);
    const baseRate = 2 + Math.sin(i / 5) * 1.5;
    const totalRequests = Math.round(baseRate + Math.random() * 3);

    // Distribute requests across agents
    const agentBreakdown = {};
    let remaining = totalRequests;
    agents.forEach((agent, idx) => {
      if (idx === agents.length - 1) {
        agentBreakdown[agent] = remaining;
      } else {
        const count = Math.min(remaining, Math.round(Math.random() * (remaining / 2)));
        agentBreakdown[agent] = count;
        remaining -= count;
      }
    });

    // Generate traces for this time bucket
    const bucketTraces = [];
    Object.entries(agentBreakdown).forEach(([agent, count]) => {
      for (let j = 0; j < count; j++) {
        const actions = AGENT_ACTIONS[agent];
        const action = actions[Math.floor(Math.random() * actions.length)];
        const isError = Math.random() > 0.92;
        const duration = Math.round(400 + Math.random() * 2000);
        const thinkingTokens = Math.random() > 0.6 ? Math.round(500 + Math.random() * 1500) : 0;
        const hasToolCall = Math.random() > 0.7;
        const llmDuration = Math.round(duration * 0.7);
        const toolDuration = hasToolCall ? Math.round(duration * 0.15) : 0;

        // Generate spans for this trace
        const spans = [
          { name: `${agent}#${action}`, type: 'root', start: 0, duration },
          { name: 'prompt', type: 'prompt', start: 20, duration: Math.round(duration * 0.04), nested: 1 },
          { name: '#generate', type: 'generate', start: Math.round(duration * 0.05), duration: llmDuration, nested: 1, error: isError },
        ];

        if (!isError) {
          spans.push({
            name: agent.includes('Code') ? 'openai.chat' : 'anthropic.messages',
            type: 'llm',
            start: Math.round(duration * 0.08),
            duration: llmDuration - Math.round(duration * 0.1),
            model: agent.includes('Code') ? 'gpt-4o' : 'claude-sonnet-4',
            nested: 2
          });

          if (thinkingTokens > 0) {
            spans.push({
              name: 'extended_thinking',
              type: 'thinking',
              start: Math.round(duration * 0.1),
              duration: Math.round(llmDuration * 0.4),
              thinking_tokens: thinkingTokens,
              nested: 3
            });
          }

          if (hasToolCall) {
            const toolActions = ['analyze_code', 'search_kb', 'validate', 'fetch_data', 'format_output'];
            spans.push({
              name: `tool_call:${toolActions[Math.floor(Math.random() * toolActions.length)]}`,
              type: 'tool',
              start: Math.round(duration * 0.5),
              duration: toolDuration,
              nested: 3
            });
          }

          spans.push({
            name: 'response',
            type: 'response',
            start: duration - Math.round(duration * 0.05),
            duration: Math.round(duration * 0.04),
            nested: 1
          });
        }

        bucketTraces.push({
          id: `${agent.substring(0,3).toLowerCase()}-${Math.random().toString(36).substring(2,6)}`,
          agent,
          action,
          duration_ms: duration,
          cost: parseFloat((0.001 + Math.random() * 0.008).toFixed(4)),
          status: isError ? 500 : 200,
          error: isError ? ['Rate limit exceeded', 'Timeout', 'Invalid response'][Math.floor(Math.random() * 3)] : null,
          timestamp: new Date(timestamp.getTime() + Math.random() * 60000).getTime(),
          spans,
          tokens: {
            thinking: thinkingTokens,
            input: Math.round(300 + Math.random() * 2000),
            output: isError ? 0 : Math.round(200 + Math.random() * 2500),
          }
        });
      }
    });

    data.push({
      time: timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      timestamp: timestamp.getTime(),
      requests: totalRequests,
      errors: bucketTraces.filter(t => t.status !== 200).length,
      avgLatency: bucketTraces.length > 0
        ? Math.round(bucketTraces.reduce((a, t) => a + t.duration_ms, 0) / bucketTraces.length)
        : 0,
      p95Latency: Math.round(1500 + Math.random() * 2000),
      traces: bucketTraces,
      ...agentBreakdown,
    });
  }
  return data;
};

// Mock data matching the lander preview design
const MOCK_TRACES = [
  {
    id: 'abc-7f2e',
    agent: 'TranslationAgent',
    action: 'translate',
    duration_ms: 1240,
    cost: 0.0034,
    status: 200,
    created_at: new Date().toISOString(),
    spans: [
      { name: 'TranslationAgent#translate', type: 'root', start: 0, duration: 1240 },
      { name: 'prompt', type: 'prompt', start: 25, duration: 45, nested: 1 },
      { name: '#generate', type: 'generate', start: 124, duration: 987, nested: 1 },
      { name: 'anthropic.messages', type: 'llm', start: 149, duration: 892, model: 'claude-sonnet-4', tokens: 2847, nested: 2 },
      { name: 'extended_thinking', type: 'thinking', start: 149, duration: 412, thinking_tokens: 1600, nested: 3 },
      { name: 'response', type: 'response', start: 1140, duration: 52, nested: 1 },
    ],
    tokens: { thinking: 1600, input: 892, output: 355 }
  },
  {
    id: 'def-3a1b',
    agent: 'CodeReviewAgent',
    action: 'review',
    duration_ms: 2340,
    cost: 0.0089,
    status: 200,
    created_at: new Date(Date.now() - 300000).toISOString(),
    spans: [
      { name: 'CodeReviewAgent#review', type: 'root', start: 0, duration: 2340 },
      { name: 'prompt', type: 'prompt', start: 20, duration: 65, nested: 1 },
      { name: '#generate', type: 'generate', start: 100, duration: 2100, nested: 1 },
      { name: 'openai.chat', type: 'llm', start: 120, duration: 1980, model: 'gpt-4o', tokens: 4521, nested: 2 },
      { name: 'tool_call:analyze_code', type: 'tool', start: 800, duration: 340, nested: 3 },
      { name: 'response', type: 'response', start: 2220, duration: 80, nested: 1 },
    ],
    tokens: { thinking: 0, input: 2100, output: 2421 }
  },
  {
    id: 'ghi-9c4d',
    agent: 'DocumentationAgent',
    action: 'generate_docs',
    duration_ms: 890,
    cost: 0.0012,
    status: 500,
    error: 'Rate limit exceeded',
    created_at: new Date(Date.now() - 600000).toISOString(),
    spans: [
      { name: 'DocumentationAgent#generate_docs', type: 'root', start: 0, duration: 890 },
      { name: 'prompt', type: 'prompt', start: 15, duration: 35, nested: 1 },
      { name: '#generate', type: 'generate', start: 60, duration: 830, nested: 1, error: true },
    ],
    tokens: { thinking: 0, input: 450, output: 0 }
  }
];

export default function TracesView() {
  const { darkMode } = useTheme();
  const [traces, setTraces] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedTrace, setSelectedTrace] = useState(null);
  const [filter, setFilter] = useState({ status: 'all', agent: 'all', action: 'all' });
  const [throughputData, setThroughputData] = useState([]);
  const [selectedTimeBucket, setSelectedTimeBucket] = useState(null);
  const [viewMode, setViewMode] = useState('timeline'); // 'timeline', 'agents', or 'actions'

  useEffect(() => {
    setTimeout(() => {
      const generatedData = generateThroughputData();
      setThroughputData(generatedData);
      // Flatten all traces from throughput data
      const allTraces = generatedData.flatMap(bucket => bucket.traces || []);
      setTraces(allTraces.length > 0 ? allTraces : MOCK_TRACES);
      setIsLoading(false);
    }, 500);
  }, []);

  // Filter traces based on selected time bucket and filters
  const filteredTraces = useMemo(() => {
    let result = traces;

    // Filter by time bucket if selected
    if (selectedTimeBucket !== null) {
      const bucket = throughputData[selectedTimeBucket];
      if (bucket) {
        result = bucket.traces || [];
      }
    }

    // Filter by status
    if (filter.status !== 'all') {
      result = result.filter(t =>
        filter.status === 'success' ? t.status === 200 : t.status !== 200
      );
    }

    // Filter by agent
    if (filter.agent !== 'all') {
      result = result.filter(t => t.agent === filter.agent);
    }

    // Filter by action (format: "Agent#action" or just "action")
    if (filter.action !== 'all') {
      if (filter.action.includes('#')) {
        // Full Agent#action format
        const [agent, action] = filter.action.split('#');
        result = result.filter(t => t.agent === agent && t.action === action);
      } else {
        // Just action name
        result = result.filter(t => t.action === filter.action);
      }
    }

    return result;
  }, [traces, selectedTimeBucket, throughputData, filter]);

  // Aggregate agent stats for selected time range
  const agentStats = useMemo(() => {
    const targetTraces = selectedTimeBucket !== null
      ? (throughputData[selectedTimeBucket]?.traces || [])
      : traces;

    const stats = {};
    targetTraces.forEach(trace => {
      if (!stats[trace.agent]) {
        stats[trace.agent] = {
          agent: trace.agent,
          count: 0,
          totalDuration: 0,
          totalCost: 0,
          errors: 0,
          actions: {},
          tokens: { thinking: 0, input: 0, output: 0 },
        };
      }
      stats[trace.agent].count++;
      stats[trace.agent].totalDuration += trace.duration_ms;
      stats[trace.agent].totalCost += trace.cost;
      if (trace.status !== 200) stats[trace.agent].errors++;
      if (trace.tokens) {
        stats[trace.agent].tokens.thinking += trace.tokens.thinking || 0;
        stats[trace.agent].tokens.input += trace.tokens.input || 0;
        stats[trace.agent].tokens.output += trace.tokens.output || 0;
      }
      // Track actions
      if (!stats[trace.agent].actions[trace.action]) {
        stats[trace.agent].actions[trace.action] = 0;
      }
      stats[trace.agent].actions[trace.action]++;
    });

    return Object.values(stats).sort((a, b) => b.count - a.count);
  }, [traces, throughputData, selectedTimeBucket]);

  // Aggregate action stats for selected time range (Agent#action level)
  const actionStats = useMemo(() => {
    const targetTraces = selectedTimeBucket !== null
      ? (throughputData[selectedTimeBucket]?.traces || [])
      : traces;

    const stats = {};
    targetTraces.forEach(trace => {
      const key = `${trace.agent}#${trace.action}`;
      if (!stats[key]) {
        stats[key] = {
          key,
          agent: trace.agent,
          action: trace.action,
          count: 0,
          totalDuration: 0,
          totalCost: 0,
          errors: 0,
          minDuration: Infinity,
          maxDuration: 0,
          tokens: { thinking: 0, input: 0, output: 0 },
        };
      }
      stats[key].count++;
      stats[key].totalDuration += trace.duration_ms;
      stats[key].totalCost += trace.cost;
      stats[key].minDuration = Math.min(stats[key].minDuration, trace.duration_ms);
      stats[key].maxDuration = Math.max(stats[key].maxDuration, trace.duration_ms);
      if (trace.status !== 200) stats[key].errors++;
      if (trace.tokens) {
        stats[key].tokens.thinking += trace.tokens.thinking || 0;
        stats[key].tokens.input += trace.tokens.input || 0;
        stats[key].tokens.output += trace.tokens.output || 0;
      }
    });

    // Fix Infinity for actions with no traces
    Object.values(stats).forEach(s => {
      if (s.minDuration === Infinity) s.minDuration = 0;
    });

    return Object.values(stats).sort((a, b) => b.count - a.count);
  }, [traces, throughputData, selectedTimeBucket]);

  // Get available actions for the selected agent (for filter dropdown)
  const availableActions = useMemo(() => {
    if (filter.agent === 'all') {
      // Show all Agent#action combinations
      return actionStats.map(s => s.key);
    }
    // Show just actions for selected agent
    return (AGENT_ACTIONS[filter.agent] || []).map(a => `${filter.agent}#${a}`);
  }, [filter.agent, actionStats]);

  // Chart click handler
  const handleChartClick = (data) => {
    if (data && data.activeTooltipIndex !== undefined) {
      const idx = data.activeTooltipIndex;
      setSelectedTimeBucket(selectedTimeBucket === idx ? null : idx);
      setSelectedTrace(null);
    }
  };

  const formatDuration = (ms) => {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatCost = (cost) => `$${cost.toFixed(4)}`;

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

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  // Dark mode uses lander CSS classes, light mode uses Tailwind
  if (darkMode) {
    return (
      <div className="preview-content" style={{ borderRadius: '12px', overflow: 'hidden', minHeight: 'calc(100vh - 200px)' }}>
        {/* Header inside dark container */}
        <div style={{ padding: '24px 24px 0 24px', borderBottom: '1px solid rgba(255,255,255,0.1)', marginBottom: '16px', paddingBottom: '16px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <h1 style={{ fontSize: '24px', fontWeight: 'bold', color: 'white', margin: 0 }}>Traces</h1>
              <p style={{ fontSize: '14px', color: 'rgba(255,255,255,0.6)', marginTop: '4px' }}>
                {selectedTimeBucket !== null
                  ? `Viewing ${throughputData[selectedTimeBucket]?.time} • ${filteredTraces.length} requests`
                  : 'Agent requests per second • Click timeline to drill down'}
              </p>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              {/* View Mode Toggle */}
              <div style={{ display: 'flex', background: 'rgba(255,255,255,0.1)', borderRadius: '8px', padding: '2px' }}>
                <button
                  onClick={() => setViewMode('timeline')}
                  style={{
                    padding: '6px 12px',
                    background: viewMode === 'timeline' ? '#ef4444' : 'transparent',
                    color: 'white',
                    borderRadius: '6px',
                    border: 'none',
                    fontSize: '13px',
                    cursor: 'pointer',
                  }}
                >
                  Timeline
                </button>
                <button
                  onClick={() => setViewMode('agents')}
                  style={{
                    padding: '6px 12px',
                    background: viewMode === 'agents' ? '#ef4444' : 'transparent',
                    color: 'white',
                    borderRadius: '6px',
                    border: 'none',
                    fontSize: '13px',
                    cursor: 'pointer',
                  }}
                >
                  Agents
                </button>
                <button
                  onClick={() => setViewMode('actions')}
                  style={{
                    padding: '6px 12px',
                    background: viewMode === 'actions' ? '#ef4444' : 'transparent',
                    color: 'white',
                    borderRadius: '6px',
                    border: 'none',
                    fontSize: '13px',
                    cursor: 'pointer',
                  }}
                >
                  Actions
                </button>
              </div>
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
                {Object.keys(AGENT_ACTIONS).map(agent => (
                  <option key={agent} value={agent}>{agent}</option>
                ))}
              </select>
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
                {availableActions.map(action => (
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
              <div style={{ display: 'flex', gap: '16px' }}>
                {Object.entries(AGENT_COLORS).map(([agent, color]) => (
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
                    {Object.entries(AGENT_COLORS).map(([agent, color]) => (
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
                  {Object.keys(AGENT_COLORS).map((agent) => (
                    <Area
                      key={agent}
                      type="monotone"
                      dataKey={agent}
                      stackId="1"
                      stroke={AGENT_COLORS[agent]}
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
                  {throughputData.reduce((sum, b) => sum + b.requests, 0)}
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Total Requests</div>
              </div>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: '#ef4444' }}>
                  {throughputData.reduce((sum, b) => sum + b.errors, 0)}
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Errors</div>
              </div>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: '#10b981' }}>
                  {Math.round(throughputData.reduce((sum, b) => sum + b.avgLatency, 0) / throughputData.length)}ms
                </div>
                <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Avg Latency</div>
              </div>
              <div>
                <div style={{ fontSize: '20px', fontWeight: '700', color: '#f59e0b' }}>
                  {(throughputData.reduce((sum, b) => sum + b.requests, 0) / 30).toFixed(1)}/min
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
              {agentStats.map(stat => (
                <div
                  key={stat.agent}
                  style={{
                    background: 'rgba(0,0,0,0.3)',
                    borderRadius: '12px',
                    padding: '16px',
                    border: `1px solid ${AGENT_COLORS[stat.agent]}40`,
                    cursor: 'pointer',
                  }}
                  onClick={() => setFilter({ ...filter, agent: filter.agent === stat.agent ? 'all' : stat.agent })}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                    <div style={{
                      width: '8px',
                      height: '8px',
                      borderRadius: '50%',
                      background: AGENT_COLORS[stat.agent]
                    }} />
                    <span style={{ fontSize: '15px', fontWeight: '600', color: 'white' }}>
                      {stat.agent}
                    </span>
                    <span style={{
                      marginLeft: 'auto',
                      fontSize: '13px',
                      padding: '2px 8px',
                      background: AGENT_COLORS[stat.agent] + '30',
                      color: AGENT_COLORS[stat.agent],
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
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Total Cost</div>
                      <div style={{ fontSize: '14px', color: 'white' }}>${stat.totalCost.toFixed(4)}</div>
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Error Rate</div>
                      <div style={{ fontSize: '14px', color: stat.errors > 0 ? '#ef4444' : '#10b981' }}>
                        {((stat.errors / stat.count) * 100).toFixed(1)}%
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: '11px', color: 'rgba(255,255,255,0.5)' }}>Total Tokens</div>
                      <div style={{ fontSize: '14px', color: 'white' }}>
                        {(stat.tokens.thinking + stat.tokens.input + stat.tokens.output).toLocaleString()}
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
              {actionStats.map(stat => {
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
                      border: isActive ? '1px solid #ef4444' : `1px solid ${AGENT_COLORS[stat.agent]}30`,
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
                          background: AGENT_COLORS[stat.agent]
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
                        background: AGENT_COLORS[stat.agent] + '30',
                        color: AGENT_COLORS[stat.agent],
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
                          {stat.minDuration}ms / {stat.maxDuration}ms
                        </div>
                      </div>
                      <div>
                        <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.5)' }}>Cost</div>
                        <div style={{ fontSize: '13px', color: 'white' }}>${stat.totalCost.toFixed(4)}</div>
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
                          {(stat.tokens.thinking + stat.tokens.input + stat.tokens.output).toLocaleString()}
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Trace List */}
        {viewMode === 'timeline' && (
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
                  <span className="trace-hash">{trace.id}</span>
                  <span style={{ marginLeft: '12px', color: 'rgba(255,255,255,0.9)', fontWeight: '500' }}>
                    {trace.agent}#{trace.action}
                  </span>
                </div>
                <div className="trace-meta">
                  <span className="meta-item"><i className="fa-solid fa-clock"></i> {formatDuration(trace.duration_ms)}</span>
                  <span className="meta-item"><i className="fa-solid fa-coins"></i> {formatCost(trace.cost)}</span>
                  <span className={`meta-item ${trace.status === 200 ? 'success' : 'error'}`}>
                    <i className={`fa-solid ${trace.status === 200 ? 'fa-check' : 'fa-xmark'}`}></i> {trace.status}
                  </span>
                </div>
              </div>

              {selectedTrace === trace.id && (
                <div className="trace-timeline">
                  <div className="timeline-scale">
                    <span>0ms</span>
                    <span>{Math.round(trace.duration_ms * 0.33)}ms</span>
                    <span>{Math.round(trace.duration_ms * 0.66)}ms</span>
                    <span>{formatDuration(trace.duration_ms)}</span>
                  </div>

                  {(trace.spans || []).map((span, idx) => (
                    <div key={idx} className={`span-row ${span.nested ? `nested-${span.nested}` : ''}`}>
                      <div className="span-label">
                        <span className={`span-icon ${span.type}`}>{getSpanIcon(span.type)}</span>
                        <span className={`span-name ${span.error ? 'error' : ''}`}>{span.name}</span>
                      </div>
                      <div className="span-bar-container">
                        <div
                          className={`span-bar ${span.type} ${span.error ? 'error' : ''}`}
                          style={{
                            left: `${(span.start / trace.duration_ms) * 100}%`,
                            width: `${Math.max((span.duration / trace.duration_ms) * 100, 2)}%`
                          }}
                        ></div>
                      </div>
                    </div>
                  ))}

                  {/* Token Breakdown Row */}
                  <div className="span-row nested-3">
                    <div className="span-label">
                      <span className="span-icon" style={{ fontFamily: TYPOGRAPHY.mono }}>+--</span>
                      <span className="span-name tokens" style={{ fontFamily: TYPOGRAPHY.mono }}>
                        {(trace.tokens.thinking + trace.tokens.input + trace.tokens.output).toLocaleString()} tokens
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

        {traces.length === 0 && viewMode === 'timeline' && (
          <div style={{ textAlign: 'center', padding: '48px 0' }}>
            <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: '18px' }}>No traces yet</div>
            <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: '14px', marginTop: '8px' }}>Run an agent to see traces appear here</p>
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
              : 'Agent requests per second • Click timeline to drill down'}
          </p>
        </div>
        <div className="flex items-center space-x-3">
          {/* View Mode Toggle */}
          <div className="flex bg-gray-100 rounded-lg p-1">
            <button
              onClick={() => setViewMode('timeline')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                viewMode === 'timeline' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              Timeline
            </button>
            <button
              onClick={() => setViewMode('agents')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                viewMode === 'agents' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              Agents
            </button>
            <button
              onClick={() => setViewMode('actions')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                viewMode === 'actions' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              Actions
            </button>
          </div>
          <select
            value={filter.agent}
            onChange={(e) => setFilter({ ...filter, agent: e.target.value, action: 'all' })}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500"
          >
            <option value="all">All Agents</option>
            {Object.keys(AGENT_ACTIONS).map(agent => (
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
            {availableActions.map(action => (
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

      {/* Throughput Chart */}
      <div className="bg-white rounded-xl border border-gray-200 p-4">
        <div className="flex justify-between items-center mb-3">
          <h3 className="text-sm font-semibold text-gray-700">Agent Requests / Minute</h3>
          <div className="flex gap-4">
            {Object.entries(AGENT_COLORS).map(([agent, color]) => (
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
                {Object.entries(AGENT_COLORS).map(([agent, color]) => (
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
              {Object.keys(AGENT_COLORS).map((agent) => (
                <Area
                  key={agent}
                  type="monotone"
                  dataKey={agent}
                  stackId="1"
                  stroke={AGENT_COLORS[agent]}
                  fill={`url(#gradient-light-${agent})`}
                />
              ))}
            </AreaChart>
          </ResponsiveContainer>
        </div>
        {/* Summary Stats */}
        <div className="flex gap-6 mt-3 pt-3 border-t border-gray-100">
          <div>
            <div className="text-lg font-bold text-gray-900">
              {throughputData.reduce((sum, b) => sum + b.requests, 0)}
            </div>
            <div className="text-xs text-gray-500">Total Requests</div>
          </div>
          <div>
            <div className="text-lg font-bold text-red-500">
              {throughputData.reduce((sum, b) => sum + b.errors, 0)}
            </div>
            <div className="text-xs text-gray-500">Errors</div>
          </div>
          <div>
            <div className="text-lg font-bold text-green-600">
              {Math.round(throughputData.reduce((sum, b) => sum + b.avgLatency, 0) / throughputData.length)}ms
            </div>
            <div className="text-xs text-gray-500">Avg Latency</div>
          </div>
          <div>
            <div className="text-lg font-bold text-amber-500">
              {(throughputData.reduce((sum, b) => sum + b.requests, 0) / 30).toFixed(1)}/min
            </div>
            <div className="text-xs text-gray-500">Throughput</div>
          </div>
        </div>
      </div>

      {/* Agent Breakdown View */}
      {viewMode === 'agents' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {agentStats.map(stat => (
            <div
              key={stat.agent}
              className="bg-white rounded-xl border border-gray-200 p-4 cursor-pointer hover:border-gray-300 transition-colors"
              style={{ borderLeftColor: AGENT_COLORS[stat.agent], borderLeftWidth: '4px' }}
              onClick={() => setFilter({ ...filter, agent: filter.agent === stat.agent ? 'all' : stat.agent })}
            >
              <div className="flex items-center justify-between mb-3">
                <span className="font-semibold text-gray-900">{stat.agent}</span>
                <span
                  className="text-sm px-2 py-0.5 rounded"
                  style={{ background: AGENT_COLORS[stat.agent] + '20', color: AGENT_COLORS[stat.agent] }}
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
                  <div className="text-gray-500 text-xs">Total Cost</div>
                  <div className="font-medium">${stat.totalCost.toFixed(4)}</div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Error Rate</div>
                  <div className={`font-medium ${stat.errors > 0 ? 'text-red-600' : 'text-green-600'}`}>
                    {((stat.errors / stat.count) * 100).toFixed(1)}%
                  </div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs">Total Tokens</div>
                  <div className="font-medium">
                    {(stat.tokens.thinking + stat.tokens.input + stat.tokens.output).toLocaleString()}
                  </div>
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
          {actionStats.map(stat => {
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
                style={{ borderLeftColor: AGENT_COLORS[stat.agent], borderLeftWidth: isActive ? '2px' : '4px' }}
              >
                {/* Header: Agent#action */}
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <div
                      className="w-2 h-2 rounded-full"
                      style={{ background: AGENT_COLORS[stat.agent] }}
                    />
                    <span className="font-semibold text-gray-900">{stat.agent}</span>
                    <span className="text-gray-500">#{stat.action}</span>
                  </div>
                  <span
                    className="text-xs px-2 py-0.5 rounded"
                    style={{ background: AGENT_COLORS[stat.agent] + '20', color: AGENT_COLORS[stat.agent] }}
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
                    <div className="text-gray-600">{stat.minDuration}ms / {stat.maxDuration}ms</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Cost</div>
                    <div className="font-medium">${stat.totalCost.toFixed(4)}</div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Errors</div>
                    <div className={stat.errors > 0 ? 'text-red-600' : 'text-green-600'}>
                      {stat.errors} ({((stat.errors / stat.count) * 100).toFixed(0)}%)
                    </div>
                  </div>
                  <div>
                    <div className="text-xs text-gray-500">Tokens</div>
                    <div className="text-gray-600">
                      {(stat.tokens.thinking + stat.tokens.input + stat.tokens.output).toLocaleString()}
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Trace List */}
      {viewMode === 'timeline' && (
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
                  <span className="text-sm font-mono text-gray-500">{trace.id}</span>
                </div>
                <span className="text-sm font-medium text-gray-900">
                  {trace.agent}#{trace.action}
                </span>
              </div>
              <div className="flex items-center space-x-4">
                <span className="text-sm text-gray-500">
                  <i className="fa-solid fa-clock mr-1"></i>
                  {formatDuration(trace.duration_ms)}
                </span>
                <span className="text-sm text-gray-500">
                  <i className="fa-solid fa-coins mr-1"></i>
                  {formatCost(trace.cost)}
                </span>
                <span className={`text-sm ${trace.status === 200 ? 'text-green-600' : 'text-red-600'}`}>
                  <i className={`fa-solid ${trace.status === 200 ? 'fa-check' : 'fa-xmark'} mr-1`}></i>
                  {trace.status}
                </span>
              </div>
            </div>

            {/* Expanded Timeline */}
            {selectedTrace === trace.id && (
              <div className="border-t border-gray-100 p-4 bg-gray-50">
                <div className="flex justify-between text-xs text-gray-400 mb-2 px-32">
                  <span>0ms</span>
                  <span>{Math.round(trace.duration_ms * 0.33)}ms</span>
                  <span>{Math.round(trace.duration_ms * 0.66)}ms</span>
                  <span>{formatDuration(trace.duration_ms)}</span>
                </div>

                <div className="space-y-2">
                  {(trace.spans || []).map((span, idx) => (
                    <div
                      key={idx}
                      className="flex items-center group"
                      style={{ paddingLeft: `${(span.nested || 0) * 16}px` }}
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
                            left: `${(span.start / trace.duration_ms) * 100}%`,
                            width: `${Math.max((span.duration / trace.duration_ms) * 100, 1)}%`
                          }}
                        />
                      </div>
                    </div>
                  ))}
                </div>

                <div className="mt-4 pt-4 border-t border-gray-200 flex items-center space-x-6">
                  <span className="text-sm text-gray-500">Tokens:</span>
                  {trace.tokens.thinking > 0 && (
                    <span className="text-sm text-amber-600" style={{ fontFamily: TYPOGRAPHY.mono }}>T:{trace.tokens.thinking.toLocaleString()}</span>
                  )}
                  <span className="text-sm text-blue-600" style={{ fontFamily: TYPOGRAPHY.mono }}>in:{trace.tokens.input.toLocaleString()}</span>
                  <span className="text-sm text-green-600" style={{ fontFamily: TYPOGRAPHY.mono }}>out:{trace.tokens.output.toLocaleString()}</span>
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

      {traces.length === 0 && viewMode === 'timeline' && (
        <div className="text-center py-12">
          <div className="text-gray-400 text-lg">No traces yet</div>
          <p className="text-gray-500 text-sm mt-2">Run an agent to see traces appear here</p>
        </div>
      )}
    </div>
  );
}
