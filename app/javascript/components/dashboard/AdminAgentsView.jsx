import React, { useState, useEffect, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

const REFRESH_INTERVAL_MS = 30000;

const formatNumber = (num) => {
  if (num == null) return '—';
  if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
  if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
  return num.toString();
};

const timeAgo = (iso) => {
  if (!iso) return '';
  const seconds = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
};

// Admin Agents: the resources connected apps reported (POST /v1/resources)
// and the rails_admin-style scaffolding that turns each into an admin
// agent. onSelectAgent opens a generated agent in the editor;
// onAgentsChanged lets the dashboard refresh its agents list after
// generation; onNotify raises the shared toast.
export default function AdminAgentsView({ onSelectAgent = null, onAgentsChanged = null, onNotify = null }) {
  const { darkMode } = useTheme();
  const [resources, setResources] = useState([]);
  const [services, setServices] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [generating, setGenerating] = useState({}); // resource id or `service:<name>` -> true
  const [exportFiles, setExportFiles] = useState({}); // agent id -> {url, filename}

  const fetchResources = useCallback(async () => {
    try {
      const response = await fetch('/api/admin_resources');
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setResources(data.resources || []);
      setServices(data.meta?.services || []);
      setLoadError(null);
    } catch (error) {
      setLoadError(error.message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchResources();
    const interval = setInterval(fetchResources, REFRESH_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [fetchResources]);

  const generateOne = async (resource) => {
    setGenerating((prev) => ({ ...prev, [resource.id]: true }));
    try {
      const response = await fetch(`/api/admin_resources/${resource.id}/generate`, { method: 'POST' });
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setResources((prev) => prev.map((r) => (r.id === resource.id ? data.resource : r)));
      onNotify?.(`${resource.name} admin agent ${resource.agent ? 'regenerated' : 'generated'}`, 'success');
      onAgentsChanged?.();
    } catch (error) {
      onNotify?.(`Failed to generate agent: ${error.message}`, 'error');
    } finally {
      setGenerating((prev) => ({ ...prev, [resource.id]: false }));
    }
  };

  const generateAll = async (service) => {
    setGenerating((prev) => ({ ...prev, [`service:${service}`]: true }));
    try {
      const response = await fetch('/api/admin_resources/generate_all', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ service_name: service }),
      });
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setResources((prev) => {
        const updated = new Map(data.resources.map((r) => [r.id, r]));
        return prev.map((r) => updated.get(r.id) || r);
      });
      onNotify?.(`Generated ${data.generated} admin agents for ${service}`, 'success');
      onAgentsChanged?.();
    } catch (error) {
      onNotify?.(`Failed to generate agents: ${error.message}`, 'error');
    } finally {
      setGenerating((prev) => ({ ...prev, [`service:${service}`]: false }));
    }
  };

  const saveAgentToFile = async (resource) => {
    if (!resource.agent) return;
    try {
      const response = await fetch(`/api/agents/${resource.agent.id}/export_file`, { method: 'POST' });
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setExportFiles((prev) => ({ ...prev, [resource.agent.id]: data.export_file }));
      onNotify?.(`Saved ${data.export_file.filename}`, 'success');
    } catch (error) {
      onNotify?.(`Failed to save agent file: ${error.message}`, 'error');
    }
  };

  const colors = {
    cardBg: darkMode ? '#1f1f1f' : '#ffffff',
    cardBorder: darkMode ? '#2a2a2a' : '#e5e7eb',
    innerBg: darkMode ? 'rgba(255,255,255,0.04)' : '#f9fafb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
    codeBg: darkMode ? 'rgba(255,255,255,0.06)' : '#f3f4f6',
  };

  const byService = services.map((service) => ({
    service,
    rows: resources.filter((resource) => resource.service_name === service),
  })).filter((group) => group.rows.length > 0);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold" style={{ color: colors.textPrimary }}>Admin Agents</h1>
        <p className="text-sm mt-1" style={{ color: colors.textSecondary }}>
          Auto-generated admin agents scaffolded from your app's resources — rails_admin, but agent-driven
        </p>
      </div>

      {loadError && (
        <div className="p-3 rounded-lg text-sm" style={{ background: darkMode ? 'rgba(239,68,68,0.1)' : '#fef2f2', color: '#ef4444' }}>
          Failed to load resources: {loadError}
        </div>
      )}

      {byService.length === 0 ? (
        <div
          className="rounded-xl border shadow-sm p-8"
          style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}
        >
          <div className="text-center mb-6">
            <div className="text-lg" style={{ color: colors.textMuted }}>No resources reported yet</div>
            <p className="text-sm mt-2 max-w-xl mx-auto" style={{ color: colors.textSecondary }}>
              Report your app's ActiveRecord models and the platform scaffolds one admin agent per
              resource — CRUD actions become named prompts, with a human in the loop for anything
              destructive. No admin dashboard required.
            </p>
          </div>
          <div className="max-w-2xl mx-auto space-y-3">
            <div className="text-xs uppercase tracking-wide" style={{ color: colors.textMuted }}>
              From a Rails app running the activeagent gem
            </div>
            <pre
              className="p-4 rounded-lg text-xs overflow-x-auto"
              style={{ background: colors.codeBg, color: colors.textPrimary, fontFamily: 'JetBrains Mono, monospace' }}
            >
{`# Copy lib/tasks/report_resources.rake from the gem repo's
# examples/support_inbox app into your app, then:
ACTIVEAGENTS_API_KEY=<your api key> bin/rails active_agent:report_resources`}
            </pre>
            <div className="text-xs uppercase tracking-wide pt-2" style={{ color: colors.textMuted }}>
              Or POST the manifest directly
            </div>
            <pre
              className="p-4 rounded-lg text-xs overflow-x-auto"
              style={{ background: colors.codeBg, color: colors.textPrimary, fontFamily: 'JetBrains Mono, monospace' }}
            >
{`curl -X POST https://api.activeagents.ai/v1/resources \\
  -H "Authorization: Bearer <your api key>" \\
  -H "Content-Type: application/json" \\
  -d '{
    "service_name": "my_app",
    "resources": [
      { "name": "Ticket", "table_name": "tickets",
        "columns": [{ "name": "subject", "type": "string", "null": false }],
        "record_count": 1042 }
    ]
  }'`}
            </pre>
            <p className="text-xs" style={{ color: colors.textMuted }}>
              API keys live in Settings → API Keys. Resources appear here as soon as they're reported.
            </p>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          {byService.map(({ service, rows }) => (
            <div
              key={service}
              className="rounded-xl border shadow-sm overflow-hidden"
              style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}
            >
              {/* Service header */}
              <div className="flex items-center justify-between p-4 border-b" style={{ borderColor: colors.cardBorder }}>
                <div className="flex items-center gap-3 min-w-0">
                  <span className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-700 rounded flex-shrink-0">APP</span>
                  <span className="text-sm font-semibold truncate" style={{ color: colors.textPrimary }}>{service}</span>
                  {rows[0]?.environment && (
                    <span className="px-1.5 py-0.5 rounded bg-purple-50 text-purple-700 font-mono text-xs flex-shrink-0">
                      {rows[0].environment}
                    </span>
                  )}
                  <span className="text-sm flex-shrink-0" style={{ color: colors.textSecondary }}>
                    {rows.length} {rows.length === 1 ? 'resource' : 'resources'}
                  </span>
                </div>
                <button
                  onClick={() => generateAll(service)}
                  disabled={generating[`service:${service}`]}
                  className="px-3 py-1.5 text-sm font-medium rounded-lg text-white bg-red-500 hover:bg-red-600 transition-colors disabled:opacity-50"
                >
                  {generating[`service:${service}`] ? 'Generating…' : 'Generate all agents'}
                </button>
              </div>

              {/* Resources table */}
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs uppercase tracking-wide" style={{ color: colors.textMuted }}>
                      <th className="px-4 py-2 font-medium">Resource</th>
                      <th className="px-4 py-2 font-medium">Table</th>
                      <th className="px-4 py-2 font-medium">Columns</th>
                      <th className="px-4 py-2 font-medium">Records</th>
                      <th className="px-4 py-2 font-medium">Admin UI</th>
                      <th className="px-4 py-2 font-medium">Reported</th>
                      <th className="px-4 py-2 font-medium">Admin Agent</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((resource) => (
                      <tr key={resource.id} className="border-t" style={{ borderColor: colors.cardBorder }}>
                        <td className="px-4 py-3 font-medium" style={{ color: colors.textPrimary }}>{resource.name}</td>
                        <td className="px-4 py-3 font-mono text-xs" style={{ color: colors.textSecondary }}>{resource.table_name || '—'}</td>
                        <td className="px-4 py-3" style={{ color: colors.textSecondary }}>{resource.column_count}</td>
                        <td className="px-4 py-3" style={{ color: colors.textSecondary }}>{formatNumber(resource.record_count)}</td>
                        <td className="px-4 py-3">
                          {resource.admin_ui ? (
                            <span className="font-mono text-xs" style={{ color: colors.textSecondary }} title={resource.admin_route}>
                              {resource.admin_route}
                            </span>
                          ) : (
                            <span className="px-1.5 py-0.5 text-xs rounded bg-amber-50 text-amber-700" title="No admin dashboard — the agent is the admin surface">
                              agent-driven
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-xs" style={{ color: colors.textMuted }}>{timeAgo(resource.last_reported_at)}</td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-2">
                            {resource.agent && !resource.agent.owned ? (
                              <span
                                className="px-2 py-1 text-xs rounded"
                                style={{ background: colors.innerBg, color: colors.textMuted }}
                                title="Generated by another workspace member — only they can open or regenerate it"
                              >
                                {resource.agent.name} (teammate's)
                              </span>
                            ) : resource.agent ? (
                              <>
                                <button
                                  onClick={() => onSelectAgent?.(resource.agent)}
                                  className="px-2 py-1 text-xs font-medium rounded bg-green-100 text-green-800 hover:bg-green-200 transition-colors"
                                  title={`Open ${resource.agent.name} (v${resource.agent.version_count})`}
                                >
                                  {resource.agent.name}
                                </button>
                                <button
                                  onClick={() => generateOne(resource)}
                                  disabled={generating[resource.id]}
                                  className="px-2 py-1 text-xs rounded transition-colors disabled:opacity-50"
                                  style={{ background: colors.innerBg, color: colors.textSecondary }}
                                  title="Re-scaffold from the latest reported schema (versioned)"
                                >
                                  {generating[resource.id] ? '…' : 'Regenerate'}
                                </button>
                                {exportFiles[resource.agent.id] ? (
                                  <a
                                    href={exportFiles[resource.agent.id].url}
                                    className="px-2 py-1 text-xs rounded bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
                                    title={exportFiles[resource.agent.id].filename}
                                  >
                                    Download
                                  </a>
                                ) : (
                                  <button
                                    onClick={() => saveAgentToFile(resource)}
                                    className="px-2 py-1 text-xs rounded transition-colors"
                                    style={{ background: colors.innerBg, color: colors.textSecondary }}
                                    title="Save the agent to a file (Active Storage)"
                                  >
                                    Save to file
                                  </button>
                                )}
                              </>
                            ) : (
                              <button
                                onClick={() => generateOne(resource)}
                                disabled={generating[resource.id]}
                                className="px-3 py-1 text-xs font-medium rounded-lg text-white bg-red-500 hover:bg-red-600 transition-colors disabled:opacity-50"
                              >
                                {generating[resource.id] ? 'Generating…' : 'Generate agent'}
                              </button>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
