import React, { useState, useEffect, useRef } from 'react';
import AgentAvatar from '../AgentAvatar';
import InteractionStream from './InteractionStream';
import InteractionsView from './InteractionsView';

export default function ConversationHistory({ agent, onBack }) {
  const [runs, setRuns] = useState([]);
  const [selectedRun, setSelectedRun] = useState(null);
  const [selectedMessages, setSelectedMessages] = useState([]);
  const [detailMode, setDetailMode] = useState('run'); // 'run' | 'all'
  const [isLoading, setIsLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [filterStatus, setFilterStatus] = useState('');
  const conversationRef = useRef(null);

  useEffect(() => {
    loadRuns();
  }, [agent.id, page, filterStatus]);

  const loadRuns = async () => {
    setIsLoading(true);
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: '20'
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

  const loadRunDetails = async (runId) => {
    try {
      const response = await fetch(`/api/runs/${runId}`);
      const data = await response.json();
      setSelectedRun(data.run);
      setSelectedMessages(data.messages || []);
    } catch (error) {
      console.error('Failed to load run details:', error);
    }
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
              <h2 className="font-semibold text-gray-900">Conversation History</h2>
              <p className="text-sm text-gray-500">{agent.name}</p>
            </div>
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
                  <div className="flex items-center space-x-3 mt-2 text-xs text-gray-400">
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
        {/* Mode toggle: one run's stream, or every session for this agent —
            both rendered by the same shared interactions components. */}
        <div className="p-3 bg-white border-b border-gray-200 flex items-center justify-between">
          <div className="flex bg-gray-100 rounded-lg p-1">
            <button
              onClick={() => setDetailMode('run')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                detailMode === 'run' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              Selected run
            </button>
            <button
              onClick={() => setDetailMode('all')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                detailMode === 'all' ? 'bg-white shadow text-gray-900' : 'text-gray-600'
              }`}
            >
              All interactions
            </button>
          </div>
          {detailMode === 'run' && selectedRun && (
            <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(selectedRun.status)}`}>
              {selectedRun.status}
            </span>
          )}
        </div>

        {detailMode === 'all' ? (
          <div className="flex-1 overflow-auto p-4">
            <InteractionsView agentId={agent.id} embedded />
          </div>
        ) : selectedRun ? (
          <>
            {/* Run Header */}
            <div className="p-4 bg-white border-b border-gray-200">
              <div className="flex items-center space-x-3">
                <AgentAvatar size={40} />
                <div>
                  <h3 className="font-medium text-gray-900">Run #{selectedRun.id}</h3>
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
                  <span className="font-mono text-xs text-gray-400" title={selectedRun.trace_id}>
                    trace:{selectedRun.trace_id.slice(0, 8)}
                  </span>
                )}
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center">
            <div className="text-center text-gray-400">
              <AgentAvatar size={100} />
              <p className="mt-4">Select a conversation to view details</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
