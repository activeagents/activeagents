import React, { useState, useEffect, useRef } from 'react';
import AgentAvatar from '../AgentAvatar';
import { useTimeWindow } from '../../contexts/TimeWindowContext';
import TimeWindowSelector from './TimeWindowSelector';
import InteractionStream from './InteractionStream';
import InteractionsView from './InteractionsView';

export default function AgentInteractions({ agent, onBack }) {
  const { timeWindow } = useTimeWindow();
  const [runs, setRuns] = useState([]);
  const [sessions, setSessions] = useState([]);
  const [selectedRun, setSelectedRun] = useState(null);
  const [selectedSession, setSelectedSession] = useState(null); // {id, name}
  const [selectedMessages, setSelectedMessages] = useState([]);
  const [detailMode, setDetailMode] = useState('run'); // 'run' | 'all'
  const [reportSort, setReportSort] = useState('recent'); // 'recent' | 'longest'
  const [expandedCohorts, setExpandedCohorts] = useState({});
  const [isLoading, setIsLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [filterStatus, setFilterStatus] = useState('');
  const conversationRef = useRef(null);

  const basePath = `/dashboard/agents/${agent.id}/interactions`;

  useEffect(() => {
    loadRuns();
  }, [agent.id, page, filterStatus, timeWindow.minutes]);

  // The shared window is a different result set, not more of the same one.
  useEffect(() => {
    setPage(1);
  }, [timeWindow.minutes]);

  // Sessions are solid_agent conversation contexts — one persisted stream
  // per agent action (e.g. DocsNavigatorAgent#ask) that every run appends
  // to. Loaded up front so the report lists them as a drill-down entry.
  useEffect(() => {
    fetch(`/api/interactions?agent_id=${agent.id}`)
      .then((response) => response.json())
      .then((data) => setSessions(data.interactions || []))
      .catch(() => {});
  }, [agent.id]);

  // Sync drill-down state with the URL: deep links like
  // /interactions/runs/:id or /interactions/sessions/:id restore the
  // drilled-in level on mount, and back/forward navigation re-applies
  // whatever level the URL points at.
  useEffect(() => {
    const applyLocation = () => {
      const path = window.location.pathname;
      const runMatch = path.match(/\/interactions\/runs\/(\d+)/);
      const sessionMatch = path.match(/\/interactions\/sessions\/(\d+)/);
      if (runMatch) {
        setDetailMode('run');
        setSelectedSession(null);
        loadRunDetails(parseInt(runMatch[1], 10), { updateUrl: false });
      } else if (sessionMatch) {
        setDetailMode('all');
        setSelectedSession({ id: parseInt(sessionMatch[1], 10) });
      } else if (path.endsWith('/interactions/sessions') || path.endsWith('/interactions/all')) {
        // /all is the legacy spelling of the sessions list
        if (path.endsWith('/all')) {
          window.history.replaceState({}, '', path.replace(/\/all$/, '/sessions'));
        }
        setDetailMode('all');
        setSelectedSession(null);
      } else {
        setDetailMode('run');
        setSelectedRun(null);
        setSelectedSession(null);
        setSelectedMessages([]);
      }
    };
    applyLocation();
    window.addEventListener('popstate', applyLocation);
    return () => window.removeEventListener('popstate', applyLocation);
  }, [agent.id]);

  const loadRuns = async () => {
    setIsLoading(true);
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: '20',
        minutes: String(timeWindow.minutes)
      });
      if (filterStatus) params.append('status', filterStatus);

      const response = await fetch(`/api/agents/${agent.id}/runs?${params}`);
      const data = await response.json();

      if (page === 1) {
        setRuns(data.runs);
      } else {
        setRuns(prev => [...prev, ...data.runs]);
      }

      setHasMore(data.runs.length === 20);
    } catch (error) {
      console.error('Failed to load runs:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const pushPath = (path) => {
    if (window.location.pathname !== path) window.history.pushState({}, '', path);
  };

  const loadRunDetails = async (runId, { updateUrl = true } = {}) => {
    try {
      const response = await fetch(`/api/runs/${runId}`);
      const data = await response.json();
      setSelectedRun(data.run);
      setSelectedMessages(data.messages || []);
      setDetailMode('run');
      setSelectedSession(null);
      if (updateUrl) pushPath(`${basePath}/runs/${runId}`);
    } catch (error) {
      console.error('Failed to load run details:', error);
    }
  };

  const clearRunSelection = () => {
    setSelectedRun(null);
    setSelectedSession(null);
    setSelectedMessages([]);
    setDetailMode('run');
    pushPath(basePath);
  };

  // Drill into one session (or back to the sessions list with null)
  const selectSession = (session) => {
    setDetailMode('all');
    if (session) {
      setSelectedSession({ id: session.id, name: session.display_name });
      pushPath(`${basePath}/sessions/${session.id}`);
    } else {
      setSelectedSession(null);
      pushPath(`${basePath}/sessions`);
    }
  };

  const switchMode = (mode) => {
    setDetailMode(mode);
    if (mode === 'all') {
      pushPath(selectedSession ? `${basePath}/sessions/${selectedSession.id}` : `${basePath}/sessions`);
    } else {
      pushPath(selectedRun ? `${basePath}/runs/${selectedRun.id}` : basePath);
    }
  };

  const selectedSessionName = selectedSession
    ? selectedSession.name
      || sessions.find((session) => session.id === selectedSession.id)?.display_name
      || `Session #${selectedSession.id}`
    : null;

  // Agent report: history × analytics for evaluating config changes.
  // Groups the loaded runs into configuration cohorts — each unique
  // (system instructions, model) combination the agent has run under —
  // with comparable stats, shown when no run is selected.
  const buildReport = () => {
    const groups = new Map();
    runs.forEach(run => {
      const key = `${run.model || 'unknown'}|${run.instructions_digest || 'none'}`;
      if (!groups.has(key)) {
        groups.set(key, {
          key,
          model: run.model,
          instructionsDigest: run.instructions_digest,
          instructionsVersion: run.instructions_version,
          instructionsCodename: run.instructions_codename,
          instructionsPreview: run.instructions_preview,
          runs: [],
        });
      }
      groups.get(key).runs.push(run);
    });
    const cohorts = [...groups.values()].map(group => ({
      ...group,
      count: group.runs.length,
      completed: group.runs.filter(r => r.status === 'complete').length,
      failed: group.runs.filter(r => r.status === 'failed').length,
      totalTokens: group.runs.reduce((sum, r) => sum + (r.tokens || 0), 0),
      avgTokens: group.runs.reduce((sum, r) => sum + (r.tokens || 0), 0) / group.runs.length,
      avgDuration: group.runs.reduce((sum, r) => sum + (r.duration_ms || 0), 0) / group.runs.length,
      latest: group.runs[0],
      // Runs within a cohort sorted by longest interaction first
      sortedRuns: [...group.runs].sort((a, b) => (b.duration_ms || 0) - (a.duration_ms || 0)),
    }));
    cohorts.sort((a, b) =>
      reportSort === 'longest'
        ? b.avgDuration - a.avgDuration
        : new Date(b.latest.created_at) - new Date(a.latest.created_at)
    );
    const totals = {
      runs: runs.length,
      completed: runs.filter(r => r.status === 'complete').length,
      tokens: runs.reduce((sum, r) => sum + (r.tokens || 0), 0),
      avgDuration: runs.length ? runs.reduce((sum, r) => sum + (r.duration_ms || 0), 0) / runs.length : 0,
      models: [...new Set(runs.map(r => r.model).filter(Boolean))],
    };
    return { cohorts, totals };
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'complete': return 'bg-green-100 text-green-700';
      case 'failed': return 'bg-red-100 text-red-700';
      case 'running': return 'bg-blue-100 text-blue-700';
      case 'pending': return 'bg-yellow-100 text-yellow-700';
      case 'cancelled': return 'bg-gray-100 text-gray-500';
      default: return 'bg-gray-100 text-gray-500';
    }
  };

  const formatDuration = (ms) => {
    if (!ms) return '-';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`;
  };

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now - date;
    const minutes = Math.floor(diff / 60000);
    const hours = Math.floor(diff / 3600000);
    const days = Math.floor(diff / 86400000);

    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    if (days < 7) return `${days}d ago`;
    return date.toLocaleDateString();
  };

  return (
    <div className="flex h-full">
      {/* Conversation List */}
      <div className="w-80 border-r border-gray-200 flex flex-col bg-white">
        {/* Header */}
        <div className="p-4 border-b border-gray-200">
          <div className="flex items-center space-x-3 mb-4">
            <button
              onClick={onBack}
              className="p-1 text-gray-400 hover:text-gray-600 transition-colors"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <div>
              <h2 className="font-semibold text-gray-900">Agent Interactions</h2>
              <p className="text-sm text-gray-500">{agent.name}</p>
            </div>
          </div>

          {/* Shared dashboard time window */}
          <div className="mb-2">
            <TimeWindowSelector compact />
          </div>

          {/* Filter */}
          <select
            value={filterStatus}
            onChange={(e) => {
              setFilterStatus(e.target.value);
              setPage(1);
            }}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-red-500"
          >
            <option value="">All Runs</option>
            <option value="complete">Completed</option>
            <option value="failed">Failed</option>
            <option value="running">Running</option>
            <option value="cancelled">Cancelled</option>
          </select>
        </div>

        {/* Run List */}
        <div className="flex-1 overflow-auto">
          {isLoading && runs.length === 0 ? (
            <div className="flex items-center justify-center h-32">
              <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-red-500"></div>
            </div>
          ) : runs.length > 0 ? (
            <>
              {runs.map(run => (
                <div
                  key={run.id}
                  onClick={() => loadRunDetails(run.id)}
                  className={`p-4 border-b border-gray-100 cursor-pointer transition-colors ${
                    selectedRun?.id === run.id
                      ? 'bg-red-50 border-l-4 border-l-red-500'
                      : 'hover:bg-gray-50'
                  }`}
                >
                  <div className="flex items-center justify-between mb-2">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${getStatusColor(run.status)}`}>
                      {run.status}
                    </span>
                    <span className="text-xs text-gray-400">{formatDate(run.created_at)}</span>
                  </div>
                  <p className="text-sm text-gray-700 truncate">
                    {run.input_preview || run.input_prompt?.substring(0, 60) || 'No input'}
                  </p>
                  <div className="flex items-center space-x-3 mt-2 text-xs text-gray-400 flex-wrap gap-y-1">
                    {run.model && (
                      <span className="px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 font-mono">{run.model}</span>
                    )}
                    <span>{formatDuration(run.duration_ms)}</span>
                    {run.tokens && <span>{run.tokens} tokens</span>}
                  </div>
                </div>
              ))}

              {hasMore && (
                <button
                  onClick={() => setPage(prev => prev + 1)}
                  disabled={isLoading}
                  className="w-full py-3 text-sm text-red-600 hover:bg-gray-50 transition-colors"
                >
                  {isLoading ? 'Loading...' : 'Load More'}
                </button>
              )}
            </>
          ) : (
            <div className="p-8 text-center text-gray-400">
              <svg className="w-12 h-12 mx-auto mb-3 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
              </svg>
              <p>No conversations yet</p>
            </div>
          )}
        </div>
      </div>

      {/* Conversation Detail */}
      <div className="flex-1 flex flex-col bg-gray-50">
        {/* Breadcrumbs — each level links back up, mirroring the URL
            (/interactions, /interactions/runs/:id, /interactions/sessions,
            /interactions/sessions/:id). */}
        <div className="px-4 py-2 bg-white border-b border-gray-100 flex items-center gap-1.5 text-xs text-gray-500">
          <button onClick={onBack} className="hover:text-gray-900 hover:underline transition-colors">
            {agent.name}
          </button>
          <span className="text-gray-300">/</span>
          {detailMode === 'all' || selectedRun ? (
            <>
              <button onClick={clearRunSelection} className="hover:text-gray-900 hover:underline transition-colors">
                Interactions
              </button>
              <span className="text-gray-300">/</span>
              {detailMode === 'all' ? (
                selectedSession ? (
                  <>
                    <button onClick={() => selectSession(null)} className="hover:text-gray-900 hover:underline transition-colors">
                      Sessions
                    </button>
                    <span className="text-gray-300">/</span>
                    <span className="text-gray-900 font-medium">{selectedSessionName}</span>
                  </>
                ) : (
                  <span className="text-gray-900 font-medium">Sessions</span>
                )
              ) : (
                <span className="text-gray-900 font-medium">Run #{selectedRun.id}</span>
              )}
            </>
          ) : (
            <span className="text-gray-900 font-medium">Interactions</span>
          )}
        </div>

        {/* Mode toggle: one run's stream, or every session for this agent —
            both rendered by the same shared interactions components. */}
        <div className="p-3 bg-white border-b border-gray-200 flex items-center justify-between">
          <div className="flex bg-gray-100 rounded-lg p-1">
            <button
              onClick={() => switchMode('run')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                detailMode === 'run' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              Selected run
            </button>
            <button
              onClick={() => switchMode('all')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                detailMode === 'all' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              Sessions
            </button>
          </div>
          {detailMode === 'run' && selectedRun && (
            <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(selectedRun.status)}`}>
              {selectedRun.status}
            </span>
          )}
        </div>

        {detailMode === 'all' ? (
          <div className="flex-1 overflow-auto p-4 space-y-4">
            {/* Agent scorecard — sessions are a subset of this agent's
                interactions, so keep its identity and stats in view. */}
            {(() => {
              const { totals } = buildReport();
              return (
                <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
                  <div className="flex items-center gap-3">
                    <AgentAvatar size={40} />
                    <div>
                      <h3 className="font-semibold text-gray-900">{agent.name}</h3>
                      <p className="text-xs text-gray-500">
                        {selectedSession
                          ? `${selectedSessionName} — one persisted interaction stream`
                          : 'Sessions group this agent’s runs into persisted interaction streams'}
                      </p>
                    </div>
                  </div>
                  <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                    <div className="bg-gray-50 rounded-lg p-3">
                      <p className="text-xs text-gray-500">Runs</p>
                      <p className="text-lg font-bold text-gray-900">{totals.runs}</p>
                    </div>
                    <div className="bg-gray-50 rounded-lg p-3">
                      <p className="text-xs text-gray-500">Success</p>
                      <p className="text-lg font-bold text-gray-900">{totals.runs ? Math.round((totals.completed / totals.runs) * 100) : 0}%</p>
                    </div>
                    <div className="bg-gray-50 rounded-lg p-3">
                      <p className="text-xs text-gray-500">Avg Duration</p>
                      <p className="text-lg font-bold text-gray-900">{formatDuration(Math.round(totals.avgDuration))}</p>
                    </div>
                    <div className="bg-gray-50 rounded-lg p-3">
                      <p className="text-xs text-gray-500">Tokens</p>
                      <p className="text-lg font-bold text-gray-900">{totals.tokens.toLocaleString()}</p>
                    </div>
                  </div>
                </div>
              );
            })()}
            <InteractionsView
              agentId={agent.id}
              embedded
              selectedSessionId={selectedSession?.id ?? null}
              onSelectSession={selectSession}
            />
          </div>
        ) : selectedRun ? (
          <>
            {/* Run Header */}
            <div className="p-4 bg-white border-b border-gray-200">
              <div className="flex items-center space-x-3">
                <AgentAvatar size={40} />
                <div>
                  <h3 className="font-medium text-gray-900">{agent.name} — Run #{selectedRun.id}</h3>
                  <p className="text-xs text-gray-500">
                    {new Date(selectedRun.created_at).toLocaleString()}
                  </p>
                </div>
              </div>
            </div>

            {/* Run interaction stream — same design as the Interactions view */}
            <div ref={conversationRef} className="flex-1 overflow-auto p-6">
              <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
                {selectedMessages.length > 0 ? (
                  <InteractionStream messages={selectedMessages} darkMode={false} />
                ) : (
                  <InteractionStream
                    darkMode={false}
                    messages={[
                      {
                        id: `run-${selectedRun.id}-input`,
                        role: 'user',
                        content: selectedRun.input_prompt || selectedRun.input_preview,
                        created_at: selectedRun.created_at
                      },
                      {
                        id: `run-${selectedRun.id}-output`,
                        role: 'assistant',
                        content: selectedRun.error_message || selectedRun.output || selectedRun.output_preview || 'No response',
                        created_at: selectedRun.completed_at || selectedRun.created_at
                      }
                    ]}
                  />
                )}
              </div>
            </div>

            {/* Run Stats */}
            <div className="p-4 bg-white border-t border-gray-200">
              <div className="flex items-center justify-center space-x-8 text-sm text-gray-500">
                <span>Duration: {formatDuration(selectedRun.duration_ms)}</span>
                {selectedRun.total_tokens && <span>Tokens: {selectedRun.total_tokens}</span>}
                {selectedRun.input_tokens && selectedRun.output_tokens && (
                  <span>Input: {selectedRun.input_tokens} / Output: {selectedRun.output_tokens}</span>
                )}
                {selectedRun.trace_id && (
                  <a
                    href={`/dashboard/traces?trace=${selectedRun.trace_id}`}
                    className="font-mono text-xs text-blue-500 hover:underline"
                    title={`${selectedRun.trace_id} — open in Traces`}
                  >
                    trace:{selectedRun.trace_id.slice(0, 8)} →
                  </a>
                )}
              </div>
            </div>
          </>
        ) : (
          (() => {
            const { cohorts, totals } = buildReport();
            if (cohorts.length === 0) {
              return (
                <div className="flex-1 flex items-center justify-center">
                  <div className="text-center text-gray-400">
                    <AgentAvatar size={100} />
                    <p className="mt-4">No runs yet — run the agent to build its report</p>
                  </div>
                </div>
              );
            }
            return (
              <div className="flex-1 overflow-auto p-6 space-y-5">
                <div className="flex items-center gap-3">
                  <AgentAvatar size={40} />
                  <div>
                    <h3 className="font-semibold text-gray-900">Agent Report</h3>
                    <p className="text-xs text-gray-500">Recent activity for {agent.name} — select a run for its full interaction</p>
                  </div>
                </div>

                {/* Overview stats */}
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                  <div className="bg-white rounded-xl border border-gray-200 p-3">
                    <p className="text-xs text-gray-500">Runs</p>
                    <p className="text-xl font-bold text-gray-900">{totals.runs}</p>
                  </div>
                  <div className="bg-white rounded-xl border border-gray-200 p-3">
                    <p className="text-xs text-gray-500">Success</p>
                    <p className="text-xl font-bold text-gray-900">{totals.runs ? Math.round((totals.completed / totals.runs) * 100) : 0}%</p>
                  </div>
                  <div className="bg-white rounded-xl border border-gray-200 p-3">
                    <p className="text-xs text-gray-500">Avg Duration</p>
                    <p className="text-xl font-bold text-gray-900">{formatDuration(Math.round(totals.avgDuration))}</p>
                  </div>
                  <div className="bg-white rounded-xl border border-gray-200 p-3">
                    <p className="text-xs text-gray-500">Tokens</p>
                    <p className="text-xl font-bold text-gray-900">{totals.tokens.toLocaleString()}</p>
                  </div>
                </div>

                {totals.models.length > 0 && (
                  <div className="flex items-center gap-2 flex-wrap text-xs">
                    <span className="text-gray-500">Models used:</span>
                    {totals.models.map(model => (
                      <span key={model} className="px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 font-mono">{model}</span>
                    ))}
                  </div>
                )}

                {/* Sessions — persisted conversation contexts (one stream
                    per agent action, appended to by every run). Top-level
                    drill-down into /interactions/sessions/:id. */}
                {sessions.length > 0 && (
                  <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                    <div className="px-4 py-3 border-b border-gray-100">
                      <span className="text-xs uppercase tracking-wide text-gray-400">
                        Sessions — grouped interaction streams
                      </span>
                    </div>
                    <div className="divide-y divide-gray-100">
                      {sessions.map(session => (
                        <div
                          key={session.id}
                          className="px-4 py-3 hover:bg-gray-50 cursor-pointer flex items-center justify-between gap-3"
                          onClick={() => selectSession(session)}
                          title="Open this session's interaction stream"
                        >
                          <div className="flex items-center gap-2 min-w-0" title={session.display_name}>
                            <span className="px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-700 rounded flex-shrink-0">SESSION</span>
                            <span className="text-sm text-gray-900 truncate">{session.agent?.name || session.agent_name}</span>
                            {session.action_name && (
                              <span className="px-1.5 py-0.5 rounded bg-purple-50 text-purple-700 font-mono text-xs flex-shrink-0">
                                #{session.action_name}
                              </span>
                            )}
                          </div>
                          <div className="flex items-center gap-3 text-xs text-gray-400 flex-shrink-0">
                            <span>{session.message_count} messages</span>
                            <span>{(session.tokens?.total || 0).toLocaleString()} tokens</span>
                            <span>{formatDate(session.last_activity_at)}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Configuration cohorts — every (instructions, model)
                    combination this agent has run under, for comparing the
                    effect of config changes side by side. */}
                <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                  <div className="px-4 py-3 border-b border-gray-100 flex items-center justify-between">
                    <span className="text-xs uppercase tracking-wide text-gray-400">
                      Interactions by instructions × model
                    </span>
                    <select
                      value={reportSort}
                      onChange={(e) => setReportSort(e.target.value)}
                      className="text-xs border border-gray-200 rounded px-2 py-1 text-gray-600"
                    >
                      <option value="recent">Most recent</option>
                      <option value="longest">Longest interactions</option>
                    </select>
                  </div>
                  <div className="divide-y divide-gray-100">
                    {cohorts.map(cohort => (
                      <div key={cohort.key}>
                        <div
                          className="px-4 py-3 hover:bg-gray-50 cursor-pointer"
                          onClick={() => setExpandedCohorts(prev => ({ ...prev, [cohort.key]: !prev[cohort.key] }))}
                          title="Show this configuration's runs"
                        >
                          <div className="flex items-center gap-2 flex-wrap">
                            <span className="px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-700 font-mono text-xs">
                              {cohort.model || 'unknown model'}
                            </span>
                            <span
                              className="text-xs text-gray-400 font-mono"
                              title={cohort.instructionsDigest ? `sha:${cohort.instructionsDigest}` : undefined}
                            >
                              instructions{' '}
                              {cohort.instructionsDigest
                                ? [cohort.instructionsVersion, cohort.instructionsCodename || cohort.instructionsDigest]
                                    .filter(Boolean)
                                    .join(' · ')
                                : 'n/a'}
                            </span>
                          </div>
                          {cohort.instructionsPreview && (
                            <p className="text-xs text-gray-500 mt-1 truncate">{cohort.instructionsPreview}</p>
                          )}
                          <div className="flex items-center gap-3 mt-1.5 text-xs text-gray-400 flex-wrap gap-y-1">
                            <span>{cohort.count} run{cohort.count > 1 ? 's' : ''}</span>
                            <span className={cohort.failed > 0 ? 'text-red-500' : 'text-green-600'}>
                              {cohort.count ? Math.round((cohort.completed / cohort.count) * 100) : 0}% success
                            </span>
                            <span>avg {formatDuration(Math.round(cohort.avgDuration))}</span>
                            <span>avg {Math.round(cohort.avgTokens).toLocaleString()} tokens</span>
                            <span>last {formatDate(cohort.latest.created_at)}</span>
                          </div>
                        </div>

                        {expandedCohorts[cohort.key] && (
                          <div className="bg-gray-50 divide-y divide-gray-100 border-t border-gray-100">
                            {cohort.sortedRuns.map(run => (
                              <div
                                key={run.id}
                                className="px-6 py-2 hover:bg-gray-100 cursor-pointer"
                                onClick={() => loadRunDetails(run.id)}
                                title="Open this run's interaction"
                              >
                                <p className="text-xs text-gray-700 truncate">{run.input_preview || 'No input'}</p>
                                <div className="flex items-center gap-3 mt-0.5 text-[11px] text-gray-400">
                                  <span className={run.status === 'failed' ? 'text-red-500' : ''}>{run.status}</span>
                                  <span>{formatDuration(run.duration_ms)}</span>
                                  {run.tokens && <span>{run.tokens.toLocaleString()} tokens</span>}
                                  <span>{formatDate(run.created_at)}</span>
                                </div>
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            );
          })()
        )}
      </div>
    </div>
  );
}
