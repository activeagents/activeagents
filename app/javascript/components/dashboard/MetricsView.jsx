import React, { useState, useEffect } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

// Mock data matching the lander preview design
const MOCK_METRICS = {
  summary: {
    total_requests: 12847,
    requests_change: 23,
    avg_latency_ms: 847,
    latency_change: -12,
    total_cost: 42.18,
    tokens_used: 2400000,
    tokens_input: 1800000,
    tokens_output: 600000,
  },
  hourly_requests: [
    { hour: '00:00', count: 423, height: 40 },
    { hour: '04:00', count: 267, height: 25 },
    { hour: '08:00', count: 634, height: 60 },
    { hour: '12:00', count: 478, height: 45 },
    { hour: '16:00', count: 847, height: 80 },
    { hour: '20:00', count: 1012, height: 95 },
    { hour: '22:00', count: 743, height: 70 },
    { hour: 'Now', count: 582, height: 55, active: true },
  ],
  by_agent: [
    { name: 'TranslationAgent', requests: 4521, cost: 12.34 },
    { name: 'CodeReviewAgent', requests: 3892, cost: 18.92 },
    { name: 'DocumentationAgent', requests: 2341, cost: 6.78 },
    { name: 'ResearchAgent', requests: 2093, cost: 4.14 },
  ],
};

export default function MetricsView() {
  const { darkMode } = useTheme();
  const [metrics, setMetrics] = useState(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    setTimeout(() => {
      setMetrics(MOCK_METRICS);
      setIsLoading(false);
    }, 500);
  }, []);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  const formatNumber = (num) => {
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  };

  // Theme colors - single source of truth
  const colors = {
    bg: darkMode ? 'transparent' : '#f9fafb',
    cardBg: darkMode ? 'rgba(255,255,255,0.05)' : '#ffffff',
    border: darkMode ? 'rgba(255,255,255,0.1)' : '#e5e7eb',
    borderLight: darkMode ? 'rgba(255,255,255,0.05)' : '#f3f4f6',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
    textCell: darkMode ? 'rgba(255,255,255,0.7)' : '#4b5563',
    trendUp: '#16a34a',
    trendDown: '#16a34a',
    tokenIn: '#2563eb',
    tokenOut: '#7c3aed',
    badgeBg: darkMode ? 'rgba(239, 68, 68, 0.2)' : '#fef2f2',
    badgeText: '#ef4444',
  };

  return (
    <div style={{ borderRadius: '12px', overflow: 'hidden', minHeight: 'calc(100vh - 200px)', backgroundColor: colors.bg }}>
      {/* Header */}
      <div style={{ padding: '24px 24px 0 24px', borderBottom: `1px solid ${colors.border}`, marginBottom: '16px', paddingBottom: '16px' }}>
        <h1 style={{ fontSize: '24px', fontWeight: 'bold', color: colors.textPrimary, margin: 0 }}>Metrics</h1>
        <p style={{ fontSize: '14px', color: colors.textSecondary, marginTop: '4px' }}>Track requests, latency, costs, and token usage in real-time</p>
      </div>

      {/* Metrics Grid - 2x2 layout */}
      <div style={{ padding: '0 24px 24px 24px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '16px', marginBottom: '16px' }}>
          {/* Total Requests */}
          <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
            <div style={{ fontSize: '11px', color: colors.textSecondary, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '8px' }}>Total Requests</div>
            <div style={{ fontSize: '32px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>{formatNumber(metrics.summary.total_requests)}</div>
            <div style={{ fontSize: '13px', color: colors.trendUp, marginTop: '8px' }}>
              ↑ {metrics.summary.requests_change}% vs last week
            </div>
            <div style={{ marginTop: '16px', height: '40px' }}>
              <svg viewBox="0 0 100 30" style={{ width: '100%', height: '100%' }}>
                <polyline points="0,25 15,20 30,22 50,12 70,15 85,8 100,10" fill="none" stroke="#ef4444" strokeWidth="2" />
              </svg>
            </div>
          </div>

          {/* Avg Latency */}
          <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
            <div style={{ fontSize: '11px', color: colors.textSecondary, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '8px' }}>Avg Latency</div>
            <div style={{ fontSize: '32px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>
              {metrics.summary.avg_latency_ms}<span style={{ fontSize: '14px', color: colors.textMuted, marginLeft: '4px' }}>ms</span>
            </div>
            <div style={{ fontSize: '13px', color: colors.trendDown, marginTop: '8px' }}>
              ↓ {Math.abs(metrics.summary.latency_change)}% faster
            </div>
            <div style={{ marginTop: '16px', height: '40px' }}>
              <svg viewBox="0 0 100 30" style={{ width: '100%', height: '100%' }}>
                <polyline points="0,8 15,12 30,10 50,15 70,18 85,22 100,25" fill="none" stroke="#22c55e" strokeWidth="2" />
              </svg>
            </div>
          </div>

          {/* Total Cost */}
          <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
            <div style={{ fontSize: '11px', color: colors.textSecondary, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '8px' }}>Total Cost</div>
            <div style={{ fontSize: '32px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>${metrics.summary.total_cost.toFixed(2)}</div>
            <div style={{ fontSize: '13px', color: colors.textSecondary, marginTop: '8px' }}>this period</div>
            <div style={{ marginTop: '16px', height: '40px' }}>
              <svg viewBox="0 0 100 30" style={{ width: '100%', height: '100%' }}>
                <polyline points="0,15 15,16 30,14 50,15 70,15 85,16 100,15" fill="none" stroke="#9ca3af" strokeWidth="2" />
              </svg>
            </div>
          </div>

          {/* Tokens Used */}
          <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
            <div style={{ fontSize: '11px', color: colors.textSecondary, textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '8px' }}>Tokens Used</div>
            <div style={{ fontSize: '32px', fontWeight: 'bold', color: colors.textPrimary, fontFamily: 'monospace' }}>{formatNumber(metrics.summary.tokens_used)}</div>
            <div style={{ fontSize: '13px', marginTop: '8px', display: 'flex', gap: '16px' }}>
              <span style={{ color: colors.tokenIn }}>↓ {formatNumber(metrics.summary.tokens_input)}</span>
              <span style={{ color: colors.tokenOut }}>↑ {formatNumber(metrics.summary.tokens_output)}</span>
            </div>
          </div>
        </div>

        {/* Chart */}
        <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}`, marginBottom: '16px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
            <span style={{ fontSize: '14px', fontWeight: '600', color: colors.textPrimary }}>Requests / Hour</span>
            <span style={{ fontSize: '13px', color: colors.textSecondary }}>Last 24h</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', height: '120px', gap: '8px' }}>
            {metrics.hourly_requests.map((item, idx) => (
              <div
                key={idx}
                style={{
                  flex: 1,
                  height: `${item.height}%`,
                  background: item.active
                    ? 'linear-gradient(180deg, #ef4444 0%, #dc2626 100%)'
                    : 'linear-gradient(180deg, #fca5a5 0%, #f87171 100%)',
                  borderRadius: '4px 4px 0 0',
                  transition: 'all 0.2s ease'
                }}
                title={`${item.count} requests at ${item.hour}`}
              />
            ))}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '8px' }}>
            {metrics.hourly_requests.map((item, idx) => (
              <span key={idx} style={{ flex: 1, textAlign: 'center', fontSize: '11px', color: colors.textMuted }}>{item.hour}</span>
            ))}
          </div>
        </div>

        {/* Top Agents Table */}
        <div style={{ background: colors.cardBg, borderRadius: '12px', padding: '20px', border: `1px solid ${colors.border}` }}>
          <h3 style={{ fontSize: '16px', fontWeight: '600', color: colors.textPrimary, marginBottom: '16px' }}>Top Agents by Usage</h3>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ textAlign: 'left', fontSize: '13px', color: colors.textSecondary, borderBottom: `1px solid ${colors.border}` }}>
                <th style={{ paddingBottom: '12px', fontWeight: '500' }}>Agent</th>
                <th style={{ paddingBottom: '12px', fontWeight: '500', textAlign: 'right' }}>Requests</th>
                <th style={{ paddingBottom: '12px', fontWeight: '500', textAlign: 'right' }}>Cost</th>
                <th style={{ paddingBottom: '12px', fontWeight: '500', textAlign: 'right' }}>Avg Cost/Request</th>
              </tr>
            </thead>
            <tbody>
              {metrics.by_agent.map((agent, idx) => (
                <tr key={agent.name} style={{ borderBottom: idx < metrics.by_agent.length - 1 ? `1px solid ${colors.borderLight}` : 'none' }}>
                  <td style={{ padding: '12px 0' }}>
                    <div style={{ display: 'flex', alignItems: 'center' }}>
                      <span style={{
                        width: '24px',
                        height: '24px',
                        borderRadius: '50%',
                        background: colors.badgeBg,
                        color: colors.badgeText,
                        fontSize: '12px',
                        fontWeight: '500',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        marginRight: '12px'
                      }}>
                        {idx + 1}
                      </span>
                      <span style={{ fontWeight: '500', color: colors.textPrimary }}>{agent.name}</span>
                    </div>
                  </td>
                  <td style={{ padding: '12px 0', textAlign: 'right', color: colors.textCell }}>{formatNumber(agent.requests)}</td>
                  <td style={{ padding: '12px 0', textAlign: 'right', color: colors.textCell }}>${agent.cost.toFixed(2)}</td>
                  <td style={{ padding: '12px 0', textAlign: 'right', color: colors.textCell }}>${((agent.cost / agent.requests) * 1000).toFixed(4)}/1K</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
