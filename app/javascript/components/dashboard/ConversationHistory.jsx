import React, { useState, useEffect, useRef } from 'react';
import AgentAvatar from '../AgentAvatar';

export default function ConversationHistory({ agent, onBack }) {
  const [runs, setRuns] = useState([]);
  const [selectedRun, setSelectedRun] = useState(null);
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
        {selectedRun ? (
          <>
            {/* Conversation Header */}
            <div className="p-4 bg-white border-b border-gray-200">
              <div className="flex items-center justify-between">
                <div className="flex items-center space-x-3">
                  <AgentAvatar size={40} />
                  <div>
                    <h3 className="font-medium text-gray-900">Run #{selectedRun.id}</h3>
                    <p className="text-xs text-gray-500">
                      {new Date(selectedRun.created_at).toLocaleString()}
                    </p>
                  </div>
                </div>
                <div className="flex items-center space-x-4">
                  <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor(selectedRun.status)}`}>
                    {selectedRun.status}
                  </span>
                </div>
              </div>
            </div>

            {/* Messages */}
            <div ref={conversationRef} className="flex-1 overflow-auto p-6 space-y-6">
              {/* User Message */}
              <div className="flex justify-end">
                <div className="max-w-2xl">
                  <div className="flex items-center justify-end space-x-2 mb-2">
                    <span className="text-sm font-medium text-gray-700">You</span>
                    <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center">
                      <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                      </svg>
                    </div>
                  </div>
                  <div className="bg-red-500 text-white rounded-2xl rounded-tr-sm px-4 py-3">
                    <p className="whitespace-pre-wrap">{selectedRun.input_prompt || selectedRun.input_preview}</p>
                  </div>
                </div>
              </div>

              {/* Agent Response */}
              <div className="flex justify-start">
                <div className="max-w-2xl">
                  <div className="flex items-center space-x-2 mb-2">
                    <AgentAvatar size={32} />
                    <span className="text-sm font-medium text-gray-700">{agent.name}</span>
                  </div>
                  <div className="bg-white rounded-2xl rounded-tl-sm px-4 py-3 shadow-sm border border-gray-200">
                    {selectedRun.status === 'running' ? (
                      <div className="flex items-center space-x-2 text-gray-500">
                        <span className="animate-pulse">...</span>
                        <span>Thinking</span>
                      </div>
                    ) : selectedRun.error_message ? (
                      <div className="text-red-600">
                        <div className="flex items-center space-x-2 mb-2">
                          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                          </svg>
                          <span className="font-medium">Error</span>
                        </div>
                        <p className="text-sm">{selectedRun.error_message}</p>
                      </div>
                    ) : (
                      <p className="whitespace-pre-wrap text-gray-800">
                        {selectedRun.output || selectedRun.output_preview || 'No response'}
                      </p>
                    )}
                  </div>
                </div>
              </div>
            </div>

            {/* Run Stats */}
            <div className="p-4 bg-white border-t border-gray-200">
              <div className="flex items-center justify-center space-x-8 text-sm text-gray-500">
                <div className="flex items-center space-x-2">
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <span>Duration: {formatDuration(selectedRun.duration_ms)}</span>
                </div>
                {selectedRun.total_tokens && (
                  <div className="flex items-center space-x-2">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01" />
                    </svg>
                    <span>Tokens: {selectedRun.total_tokens}</span>
                  </div>
                )}
                {selectedRun.input_tokens && selectedRun.output_tokens && (
                  <div className="flex items-center space-x-2">
                    <span>Input: {selectedRun.input_tokens} / Output: {selectedRun.output_tokens}</span>
                  </div>
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
