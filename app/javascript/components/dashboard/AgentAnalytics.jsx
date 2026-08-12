import React, { useState, useEffect } from 'react';
import { useTimeWindow } from '../../contexts/TimeWindowContext';
import TimeWindowSelector from './TimeWindowSelector';
import TracesView from './TracesView';
import InteractionsView from './InteractionsView';

const TABS = [
  { id: 'overview', label: 'Overview' },
  { id: 'traces', label: 'Traces' },
  { id: 'interactions', label: 'Interactions' }
];

// embedded drops the page header and the nested tab bar: when this renders
// inside the agent detail page's Metrics tab, that page already owns the
// heading and the tab row, and Traces/Interactions are siblings there.
export default function AgentAnalytics({ agent, onBack, embedded = false }) {
  const [analytics, setAnalytics] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  // This endpoint takes whole days; the shared window rounds up so a
  // sub-day selection still returns the current day rather than nothing.
  const { timeWindow, days: period } = useTimeWindow();
  const [activeTab, setActiveTab] = useState('overview');

  // Correlation key between this Agent record and its telemetry traces
  // (mirrors Agent#telemetry_agent_class for shallow agent objects).
  const telemetryAgentClass = agent.telemetry_agent_class ||
    (() => {
      const base = agent.agent_class_name ||
        `${(agent.name || '').replace(/[^a-zA-Z0-9]+(.)/g, (_, c) => c.toUpperCase()).replace(/^./, c => c.toUpperCase()).replace(/[^a-zA-Z0-9]/g, '')}`;
      return base.endsWith('Agent') ? base : `${base}Agent`;
    })();

  useEffect(() => {
    loadAnalytics();
  }, [agent?.id, period]);

  const loadAnalytics = async () => {
    if (!agent?.id) return;

    setIsLoading(true);
    try {
      const response = await fetch(`/api/agents/${agent.id}/analytics?days=${period}`);
      const data = await response.json();
      setAnalytics(data);
    } catch (error) {
      console.error('Failed to load analytics:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const formatDuration = (ms) => {
    if (!ms) return '-';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  const formatNumber = (num) => {
    if (!num) return '0';
    if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
    if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
    return num.toString();
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'complete': return 'bg-green-500';
      case 'failed': return 'bg-red-500';
      case 'running': return 'bg-blue-500';
      case 'pending': return 'bg-yellow-500';
      case 'cancelled': return 'bg-gray-500';
      default: return 'bg-gray-400';
    }
  };

  if (isLoading && !analytics) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  const maxRuns = analytics?.runs_by_day?.length > 0
    ? Math.max(...analytics.runs_by_day.map(d => d.count))
    : 1;

  // Embedded, this is only ever the overview — the host page owns the tabs.
  const shownTab = embedded ? 'overview' : activeTab;

  return (
    <div className="space-y-6">
      {/* Header */}
      {embedded ? (
        <div className="flex items-center justify-end gap-2">
          {timeWindow.minutes < 1440 && (
            <span className="text-xs text-gray-400" title="This view aggregates by day">
              showing 1 day
            </span>
          )}
          <TimeWindowSelector />
        </div>
      ) : (
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <button
              onClick={onBack}
              className="p-2 text-gray-400 hover:text-gray-600 transition-colors"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <div>
              <h1 className="text-2xl font-bold text-gray-900">{agent.name} Analytics</h1>
              <p className="text-sm text-gray-500">Performance metrics and usage data</p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {timeWindow.minutes < 1440 && (
              <span className="text-xs text-gray-400" title="This view aggregates by day">
                showing 1 day
              </span>
            )}
            <TimeWindowSelector />
          </div>
        </div>
      )}

      {/* Shared-view tabs: Traces and Interactions are the same components
          as the global observability views, scoped to this agent. */}
      {!embedded && (
        <div className="flex bg-gray-100 rounded-lg p-1 w-fit">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-1.5 text-sm rounded-md transition-colors ${
                activeTab === tab.id ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      )}

      {shownTab === 'traces' && (
        <TracesView agentClass={telemetryAgentClass} embedded />
      )}

      {shownTab === 'interactions' && (
        <InteractionsView agentId={agent.id} embedded />
      )}

      {shownTab === 'overview' && (<>
      {/* Stats Cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Total Runs"
          value={analytics?.summary?.total_runs || 0}
          icon={
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
            </svg>
          }
          color="rose"
        />
        <StatCard
          title="Success Rate"
          value={`${analytics?.summary?.success_rate || 0}%`}
          icon={
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          }
          color="green"
        />
        <StatCard
          title="Avg Duration"
          value={formatDuration(analytics?.summary?.avg_duration_ms)}
          icon={
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          }
          color="blue"
        />
        <StatCard
          title="Total Tokens"
          value={formatNumber(analytics?.summary?.total_tokens)}
          icon={
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
            </svg>
          }
          color="purple"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Runs Chart */}
        <div className="lg:col-span-2 bg-white rounded-xl border border-gray-200 p-6">
          <h3 className="font-semibold text-gray-900 mb-4">Runs Over Time</h3>
          {analytics?.runs_by_day?.length > 0 ? (
            <div className="h-48">
              <div className="flex items-end justify-between h-full space-x-1">
                {analytics.runs_by_day.map((day, i) => (
                  <div
                    key={day.date}
                    className="flex-1 flex flex-col items-center group"
                  >
                    <div className="relative w-full">
                      <div
                        className="w-full bg-red-500 rounded-t transition-all hover:bg-red-600"
                        style={{ height: `${(day.count / maxRuns) * 150}px`, minHeight: day.count > 0 ? '4px' : '0' }}
                      ></div>
                      <div className="absolute -top-8 left-1/2 transform -translate-x-1/2 bg-gray-800 text-white text-xs px-2 py-1 rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap">
                        {day.count} runs
                      </div>
                    </div>
                    {(i === 0 || i === analytics.runs_by_day.length - 1 || analytics.runs_by_day.length <= 7) && (
                      <span className="text-xs text-gray-400 mt-2 transform -rotate-45 origin-left">
                        {new Date(day.date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                      </span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="h-48 flex items-center justify-center text-gray-400">
              No data for this period
            </div>
          )}
        </div>

        {/* Status Breakdown */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h3 className="font-semibold text-gray-900 mb-4">Status Breakdown</h3>
          {Object.keys(analytics?.status_breakdown || {}).length > 0 ? (
            <div className="space-y-3">
              {Object.entries(analytics.status_breakdown).map(([status, count]) => {
                const total = analytics?.summary?.total_runs || 1;
                const percentage = ((count / total) * 100).toFixed(1);
                return (
                  <div key={status}>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="capitalize text-gray-600">{status}</span>
                      <span className="text-gray-900 font-medium">{count} ({percentage}%)</span>
                    </div>
                    <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className={`h-full ${getStatusColor(status)} rounded-full transition-all`}
                        style={{ width: `${percentage}%` }}
                      ></div>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="h-32 flex items-center justify-center text-gray-400">
              No runs yet
            </div>
          )}
        </div>
      </div>

      {/* Recent Errors */}
      {analytics?.recent_errors?.length > 0 && (
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h3 className="font-semibold text-gray-900 mb-4">Recent Errors</h3>
          <div className="space-y-3">
            {analytics.recent_errors.map((error) => (
              <div key={error.id} className="flex items-start space-x-3 p-3 bg-red-50 rounded-lg">
                <svg className="w-5 h-5 text-red-500 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-red-700">{error.error || 'Unknown error'}</p>
                  <p className="text-xs text-red-500 mt-1">
                    {new Date(error.created_at).toLocaleString()}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Quick Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500">Completed Runs</p>
          <p className="text-2xl font-bold text-gray-900">{analytics?.summary?.completed_runs || 0}</p>
        </div>
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500">Failed Runs</p>
          <p className="text-2xl font-bold text-gray-900">{analytics?.summary?.failed_runs || 0}</p>
        </div>
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500">Avg Tokens/Run</p>
          <p className="text-2xl font-bold text-gray-900">{formatNumber(analytics?.summary?.avg_tokens_per_run)}</p>
        </div>
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-500">Period</p>
          <p className="text-2xl font-bold text-gray-900">{analytics?.period_days || 30} days</p>
        </div>
      </div>
      </>)}
    </div>
  );
}

function StatCard({ title, value, icon, color }) {
  const colors = {
    rose: 'bg-red-100 text-red-600',
    green: 'bg-green-100 text-green-600',
    blue: 'bg-blue-100 text-blue-600',
    purple: 'bg-purple-100 text-purple-600'
  };

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-gray-500">{title}</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{value}</p>
        </div>
        <div className={`p-3 rounded-lg ${colors[color]}`}>
          {icon}
        </div>
      </div>
    </div>
  );
}
