import React, { useState, useEffect } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

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
  const [filter, setFilter] = useState({ status: 'all', agent: 'all' });

  useEffect(() => {
    setTimeout(() => {
      setTraces(MOCK_TRACES);
      setIsLoading(false);
      setSelectedTrace(MOCK_TRACES[0]?.id);
    }, 500);
  }, []);

  const formatDuration = (ms) => {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatCost = (cost) => `$${cost.toFixed(4)}`;

  const getSpanIcon = (type) => {
    switch (type) {
      case 'root': return '→';
      case 'prompt': return '◇';
      case 'generate': return '▶';
      case 'llm': return '◆';
      case 'thinking': return '💭';
      case 'tool': return '🔧';
      case 'response': return '◇';
      default: return '•';
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
              <p style={{ fontSize: '14px', color: 'rgba(255,255,255,0.6)', marginTop: '4px' }}>Every agent call broken into spans with timing and costs</p>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
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
              <button style={{
                padding: '8px 16px',
                background: '#ef4444',
                color: 'white',
                borderRadius: '8px',
                border: 'none',
                fontSize: '14px',
                fontWeight: '500',
                cursor: 'pointer'
              }}>
                Export
              </button>
            </div>
          </div>
        </div>

        <div className="preview-traces">
          {traces.map((trace) => (
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

                  {trace.spans.map((span, idx) => (
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
                      <span className="span-icon">↳</span>
                      <span className="span-name tokens">
                        {(trace.tokens.thinking + trace.tokens.input + trace.tokens.output).toLocaleString()} tokens
                      </span>
                    </div>
                    <div className="span-bar-container">
                      <div className="token-breakdown">
                        {trace.tokens.thinking > 0 && (
                          <span className="token-thinking">🧠 {trace.tokens.thinking.toLocaleString()}</span>
                        )}
                        <span className="token-in">↓ {trace.tokens.input.toLocaleString()}</span>
                        <span className="token-out">↑ {trace.tokens.output.toLocaleString()}</span>
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

        {traces.length === 0 && (
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
          <p className="text-sm text-gray-500">Every agent call broken into spans with timing and costs</p>
        </div>
        <div className="flex items-center space-x-3">
          <select
            value={filter.status}
            onChange={(e) => setFilter({ ...filter, status: e.target.value })}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500"
          >
            <option value="all">All Status</option>
            <option value="success">Success</option>
            <option value="error">Error</option>
          </select>
          <button className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-colors text-sm font-medium">
            Export
          </button>
        </div>
      </div>

      {/* Trace List */}
      <div className="space-y-4">
        {traces.map((trace) => (
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
                  {trace.spans.map((span, idx) => (
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
                    <span className="text-sm text-amber-600">🧠 {trace.tokens.thinking.toLocaleString()}</span>
                  )}
                  <span className="text-sm text-blue-600">↓ {trace.tokens.input.toLocaleString()}</span>
                  <span className="text-sm text-green-600">↑ {trace.tokens.output.toLocaleString()}</span>
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

      {traces.length === 0 && (
        <div className="text-center py-12">
          <div className="text-gray-400 text-lg">No traces yet</div>
          <p className="text-gray-500 text-sm mt-2">Run an agent to see traces appear here</p>
        </div>
      )}
    </div>
  );
}
