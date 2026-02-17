import React, { useState } from 'react';
import AgentAvatar, { AGENT_PRESETS } from '../AgentAvatar';

export default function AgentList({
  agents,
  meta,
  onSelect,
  onNew,
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

  const getPresetConfig = (agent) => {
    if (agent.presetType && AGENT_PRESETS[agent.presetType]) {
      return AGENT_PRESETS[agent.presetType];
    }
    // Default based on provider
    if (agent.provider === 'anthropic') return { hat: 'safari', heldItem: 'terminal' };
    return { hat: 'fedora', heldItem: 'terminal' };
  };

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
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500 focus:border-transparent"
            />
            <svg className="absolute left-3 top-2.5 h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </div>

          {/* Filters */}
          <select
            value={filterProvider}
            onChange={(e) => setFilterProvider(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
          >
            <option value="">All Providers</option>
            {meta.providers?.map(p => (
              <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
            ))}
          </select>

          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500"
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
            onClick={onNew}
            className="flex items-center space-x-2 px-4 py-2 bg-rose-500 text-white rounded-lg hover:bg-rose-600 transition-colors"
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
            const presetConfig = getPresetConfig(agent);
            const appearanceConfig = {
              ...presetConfig,
              ...(agent.appearance || {})
            };

            return (
              <div
                key={agent.id}
                className="bg-white rounded-xl border border-gray-200 overflow-hidden hover:shadow-lg transition-all cursor-pointer group"
                onClick={() => onSelect(agent)}
              >
                {/* Avatar Preview */}
                <div className="h-40 bg-gradient-to-br from-gray-50 to-gray-100 flex items-center justify-center relative overflow-hidden">
                  <div className="transform group-hover:scale-110 transition-transform">
                    <AgentAvatar
                      hat={appearanceConfig.hat}
                      hatAccessory={appearanceConfig.hatAccessory}
                      heldItem={appearanceConfig.heldItem}
                      size={120}
                    />
                  </div>
                  <span className={`absolute top-3 right-3 px-2 py-1 text-xs font-medium rounded-full ${getStatusColor(agent.status)}`}>
                    {agent.status}
                  </span>
                </div>

                {/* Content */}
                <div className="p-4">
                  <h3 className="font-semibold text-gray-900 group-hover:text-rose-600 transition-colors">
                    {agent.name}
                  </h3>
                  <p className="text-sm text-gray-500 mt-1 line-clamp-2">
                    {agent.description || 'No description'}
                  </p>

                  <div className="mt-4 flex items-center justify-between text-xs text-gray-400">
                    <div className="flex items-center space-x-2">
                      <span className="px-2 py-1 bg-gray-100 rounded">{agent.provider}</span>
                      <span>{agent.model}</span>
                    </div>
                    <span>{formatDate(agent.updatedAt || agent.updated_at)}</span>
                  </div>
                </div>

                {/* Actions */}
                <div className="px-4 py-3 bg-gray-50 border-t border-gray-100 flex justify-between opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    onClick={(e) => { e.stopPropagation(); onDuplicate(agent.id); }}
                    className="text-sm text-gray-600 hover:text-rose-600 transition-colors"
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
            <AgentAvatar hat="fedora" heldItem="terminal" size={100} />
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
            <button
              onClick={onNew}
              className="inline-flex items-center space-x-2 px-6 py-3 bg-rose-500 text-white rounded-lg hover:bg-rose-600 transition-colors"
            >
              <svg className="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
              </svg>
              <span>Create Your First Agent</span>
            </button>
          )}
        </div>
      )}
    </div>
  );
}
