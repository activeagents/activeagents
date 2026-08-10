import React, { useState } from 'react';
import AgentAvatar from '../AgentAvatar';

export default function AgentList({
  agents,
  meta,
  onSelect,
  onNew,
  onBrowseTemplates,
  onDuplicate,
  onDelete,
  onRefresh,
  isLoading
}) {
  const [searchQuery, setSearchQuery] = useState('');
  const [filterProvider, setFilterProvider] = useState('');
  const [filterStatus, setFilterStatus] = useState('');

  const filteredAgents = agents.filter(agent => {
    const matchesSearch = !searchQuery ||
      agent.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      agent.description?.toLowerCase().includes(searchQuery.toLowerCase());

    const matchesProvider = !filterProvider || agent.provider === filterProvider;
    const matchesStatus = !filterStatus || agent.status === filterStatus;

    return matchesSearch && matchesProvider && matchesStatus;
  });

  const formatDate = (dateString) => {
    const date = new Date(dateString);
    const now = new Date();
    const diff = now - date;
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) return 'Today';
    if (days === 1) return 'Yesterday';
    if (days < 7) return `${days} days ago`;
    return date.toLocaleDateString();
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'active': return 'bg-green-100 text-green-700';
      case 'draft': return 'bg-yellow-100 text-yellow-700';
      case 'archived': return 'bg-gray-100 text-gray-500';
      default: return 'bg-gray-100 text-gray-500';
    }
  };

  const formatDuration = (ms) => {
    if (ms == null) return '—';
    if (ms < 1000) return `${Math.round(ms)}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };

  const formatTokens = (tokens) => {
    if (tokens == null) return '—';
    if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
    if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}k`;
    return `${tokens}`;
  };

  const formatLastRun = (dateString) => {
    if (!dateString) return '—';
    const days = Math.floor((new Date() - new Date(dateString)) / (1000 * 60 * 60 * 24));
    if (days <= 0) return 'Today';
    if (days < 30) return `${days}d ago`;
    return new Date(dateString).toLocaleDateString();
  };

  // Green/yellow/red thresholds matching the Evaluations view.
  const rateColor = (fraction) => {
    if (fraction == null) return 'text-gray-400';
    if (fraction >= 0.85) return 'text-green-600';
    if (fraction >= 0.7) return 'text-yellow-600';
    return 'text-red-600';
  };

  const StatCell = ({ label, value, valueClass = 'text-gray-900', title }) => (
    <div className="rounded-lg bg-gray-50 px-2 py-1.5" title={title}>
      <div className={`text-sm font-semibold leading-tight ${valueClass}`}>{value}</div>
      <div className="text-[10px] uppercase tracking-wide text-gray-400">{label}</div>
    </div>
  );

  return (
    <div className="space-y-6">
      {/* Header Actions */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div className="flex-1 flex items-center space-x-4">
          {/* Search */}
          <div className="relative flex-1 max-w-md">
            <input
              type="text"
              placeholder="Search agents..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent"
            />
            <svg className="absolute left-3 top-2.5 h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>

          {/* Filters */}
          <select
            value={filterProvider}
            onChange={(e) => setFilterProvider(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500"
          >
            <option value="">All Providers</option>
            {meta.providers?.map(p => (
              <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
            ))}
          </select>

          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500"
          >
            <option value="">All Status</option>
            <option value="active">Active</option>
            <option value="draft">Draft</option>
            <option value="archived">Archived</option>
          </select>
        </div>

        <div className="flex items-center space-x-3">
          <button
            onClick={onRefresh}
            disabled={isLoading}
            className="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
          >
            <svg className={`h-5 w-5 ${isLoading ? 'animate-spin' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </button>
          <button
            onClick={onBrowseTemplates}
            className="flex items-center space-x-2 px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
            </svg>
            <span>Browse Templates</span>
          </button>
          <button
            onClick={onNew}
            className="flex items-center space-x-2 px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-colors"
          >
            <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            <span>New Agent</span>
          </button>
        </div>
      </div>

      {/* Agent Grid */}
      {filteredAgents.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {filteredAgents.map((agent) => {
            const stats = agent.stats || {};
            return (
              <div
                key={agent.id}
                className="bg-white rounded-xl border border-gray-200 overflow-hidden hover:shadow-lg transition-all cursor-pointer group"
                onClick={() => onSelect(agent)}
              >
                {/* Content */}
                <div className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="font-semibold text-gray-900 group-hover:text-red-600 transition-colors">
                      {agent.name}
                    </h3>
                    <span className={`shrink-0 px-2 py-0.5 text-xs font-medium rounded-full ${getStatusColor(agent.status)}`}>
                      {agent.status}
                    </span>
                  </div>
                  <p className="text-sm text-gray-500 mt-1 line-clamp-2">
                    {agent.description || 'No description'}
                  </p>

                  {/* Scorecard */}
                  <div className="mt-3 grid grid-cols-3 gap-1.5 text-center">
                    <StatCell label={`Runs ${stats.window_days || 30}d`} value={stats.runs ?? 0} />
                    <StatCell
                      label="Success"
                      value={stats.success_rate != null ? `${Math.round(stats.success_rate)}%` : '—'}
                      valueClass={rateColor(stats.success_rate != null ? stats.success_rate / 100 : null)}
                    />
                    <StatCell label="Avg time" value={formatDuration(stats.avg_duration_ms)} />
                    <StatCell
                      label={stats.eval_samples_evaluated ? `Eval ${stats.eval_samples_passed}/${stats.eval_samples_evaluated}` : 'Eval'}
                      title={stats.eval_samples_evaluated ? `Latest evaluation: ${stats.eval_samples_passed} of ${stats.eval_samples_evaluated} samples passed` : undefined}
                      value={stats.eval_score != null ? `${Math.round(stats.eval_score * 100)}%` : '—'}
                      valueClass={rateColor(stats.eval_score)}
                    />
                    <StatCell label="Tokens" value={formatTokens(stats.tokens)} />
                    <StatCell label="Last run" value={formatLastRun(stats.last_run_at)} />
                  </div>

                  <div className="mt-3 flex items-center justify-between text-xs text-gray-400">
                    <div className="flex items-center space-x-2">
                      <span className="px-2 py-1 bg-gray-100 rounded">{agent.provider}</span>
                      <span>{agent.model}</span>
                    </div>
                    <span>Updated {formatDate(agent.updatedAt || agent.updated_at)}</span>
                  </div>
                </div>

                {/* Actions */}
                <div className="px-4 py-3 bg-gray-50 border-t border-gray-100 flex justify-between opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    onClick={(e) => { e.stopPropagation(); onDuplicate(agent.id); }}
                    className="text-sm text-gray-600 hover:text-red-600 transition-colors"
                  >
                    Duplicate
                  </button>
                  <button
                    onClick={(e) => { e.stopPropagation(); onDelete(agent.id); }}
                    className="text-sm text-red-500 hover:text-red-700 transition-colors"
                  >
                    Delete
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="text-center py-16">
          <div className="inline-block mb-4">
            <AgentAvatar size={100} />
          </div>
          <h3 className="text-lg font-medium text-gray-900 mb-2">
            {agents.length === 0 ? 'No agents yet' : 'No matching agents'}
          </h3>
          <p className="text-gray-500 mb-6">
            {agents.length === 0
              ? 'Create your first AI agent to get started'
              : 'Try adjusting your search or filters'}
          </p>
          {agents.length === 0 && (
            <div className="flex items-center justify-center space-x-4">
              <button
                onClick={onBrowseTemplates}
                className="inline-flex items-center space-x-2 px-6 py-3 border-2 border-red-500 text-red-600 rounded-lg hover:bg-red-50 transition-colors"
              >
                <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                </svg>
                <span>Browse Templates</span>
              </button>
              <span className="text-gray-400">or</span>
              <button
                onClick={onNew}
                className="inline-flex items-center space-x-2 px-6 py-3 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-colors"
              >
                <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                </svg>
                <span>Create From Scratch</span>
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
