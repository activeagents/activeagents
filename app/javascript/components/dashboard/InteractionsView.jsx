import React, { useState, useEffect, useCallback } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

const REFRESH_INTERVAL_MS = 30000;

const formatNumber = (num) => {
  if (num == null) return '0';
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

export default function InteractionsView() {
  const { darkMode } = useTheme();
  const [sessions, setSessions] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [expandedSession, setExpandedSession] = useState(null);
  const [details, setDetails] = useState({}); // interaction id -> detail payload

  const fetchSessions = useCallback(async () => {
    try {
      const response = await fetch('/api/interactions');
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      const data = await response.json();
      setSessions(data.interactions || []);
      setLoadError(null);
    } catch (error) {
      setLoadError(error.message);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSessions();
    const interval = setInterval(fetchSessions, REFRESH_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [fetchSessions]);

  const toggleSession = async (id) => {
    if (expandedSession === id) {
      setExpandedSession(null);
      return;
    }
    setExpandedSession(id);
    if (!details[id]) {
      try {
        const response = await fetch(`/api/interactions/${id}`);
        if (response.ok) {
          const data = await response.json();
          setDetails((prev) => ({ ...prev, [id]: data.interaction }));
        }
      } catch {
        // leave detail empty; the card shows a loading state
      }
    }
  };

  const colors = {
    cardBg: darkMode ? '#1f1f1f' : '#ffffff',
    cardBorder: darkMode ? '#2a2a2a' : '#e5e7eb',
    innerBg: darkMode ? 'rgba(255,255,255,0.04)' : '#f9fafb',
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
  };

  const roleBubble = (role) => {
    switch (role) {
      case 'user':
        return darkMode
          ? { background: 'rgba(59,130,246,0.15)', color: '#93c5fd', label: 'User' }
          : { background: '#eff6ff', color: '#1d4ed8', label: 'User' };
      case 'assistant':
        return darkMode
          ? { background: 'rgba(239,68,68,0.12)', color: '#fca5a5', label: 'Assistant' }
          : { background: '#fef2f2', color: '#b91c1c', label: 'Assistant' };
      case 'tool':
        return darkMode
          ? { background: 'rgba(245,158,11,0.12)', color: '#fcd34d', label: 'Tool' }
          : { background: '#fffbeb', color: '#b45309', label: 'Tool' };
      default:
        return darkMode
          ? { background: 'rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.7)', label: role }
          : { background: '#f3f4f6', color: '#374151', label: role };
    }
  };

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
        <h1 className="text-2xl font-bold" style={{ color: colors.textPrimary }}>Interactions</h1>
        <p className="text-sm mt-1" style={{ color: colors.textSecondary }}>
          Persisted conversation streams per agent — messages, generations and provenance
        </p>
      </div>

      {loadError && (
        <div className="p-3 rounded-lg text-sm" style={{ background: darkMode ? 'rgba(239,68,68,0.1)' : '#fef2f2', color: '#ef4444' }}>
          Failed to load interactions: {loadError}
        </div>
      )}

      {/* Sessions List */}
      {sessions.length === 0 ? (
        <div className="text-center py-12">
          <div className="text-lg" style={{ color: colors.textMuted }}>No interactions yet</div>
          <p className="text-sm mt-2" style={{ color: colors.textSecondary }}>
            Run an agent to start recording its conversation stream
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {sessions.map((session) => {
            const detail = details[session.id];
            const isExpanded = expandedSession === session.id;
            return (
              <div
                key={session.id}
                className="rounded-xl border shadow-sm overflow-hidden"
                style={{ backgroundColor: colors.cardBg, borderColor: colors.cardBorder }}
              >
                {/* Session header */}
                <div
                  className="flex items-center justify-between p-4 cursor-pointer"
                  onClick={() => toggleSession(session.id)}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <span className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-700 rounded flex-shrink-0">SESSION</span>
                    <span className="font-mono text-sm truncate" style={{ color: colors.textPrimary }}>
                      {session.display_name}
                    </span>
                    {session.agent && (
                      <span className="text-sm truncate" style={{ color: colors.textSecondary }}>
                        {session.agent.name}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-4 flex-shrink-0 text-sm" style={{ color: colors.textSecondary }}>
                    <span>{session.message_count} messages</span>
                    <span>{formatNumber(session.tokens?.total)} tokens</span>
                    <span style={{ color: colors.textMuted }}>{timeAgo(session.last_activity_at)}</span>
                    <svg
                      className={`w-4 h-4 transition-transform ${isExpanded ? 'rotate-180' : ''}`}
                      fill="none" stroke="currentColor" viewBox="0 0 24 24"
                    >
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                    </svg>
                  </div>
                </div>

                {/* Expanded conversation */}
                {isExpanded && (
                  <div className="border-t p-4 space-y-3" style={{ borderColor: colors.cardBorder, background: colors.innerBg }}>
                    {!detail ? (
                      <div className="flex justify-center py-6">
                        <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-red-500"></div>
                      </div>
                    ) : (
                      <>
                        {detail.messages.map((message) => {
                          const bubble = roleBubble(message.role);
                          return (
                            <div key={message.id} className="flex gap-3 items-start">
                              <span
                                className="px-2 py-0.5 rounded text-xs font-medium flex-shrink-0 mt-0.5"
                                style={{ background: bubble.background, color: bubble.color, minWidth: '72px', textAlign: 'center' }}
                              >
                                {bubble.label}
                              </span>
                              <div className="min-w-0 flex-1">
                                <div className="text-sm whitespace-pre-wrap break-words" style={{ color: colors.textPrimary }}>
                                  {message.content || (message.tool_name ? `→ ${message.tool_name}(${JSON.stringify(message.tool_calls || {})})` : '—')}
                                </div>
                                <div className="text-xs mt-0.5 font-mono" style={{ color: colors.textMuted }}>
                                  {new Date(message.created_at).toLocaleTimeString()}
                                  {message.content_checksum && (
                                    <span title="Content fingerprint"> · 🔒 {message.content_checksum.slice(0, 8)}</span>
                                  )}
                                </div>
                              </div>
                            </div>
                          );
                        })}

                        {/* Generation metadata */}
                        {detail.generations.length > 0 && (
                          <div className="pt-3 mt-2 border-t" style={{ borderColor: colors.cardBorder }}>
                            <div className="text-xs uppercase tracking-wide mb-2" style={{ color: colors.textMuted }}>
                              Generations
                            </div>
                            <div className="space-y-1">
                              {detail.generations.map((generation) => (
                                <div key={generation.id} className="flex flex-wrap items-center gap-3 text-xs font-mono" style={{ color: colors.textSecondary }}>
                                  <span
                                    title={generation.cache_hit ? `${formatNumber(generation.tokens.cached)} cached prompt tokens` : 'No prompt cache hit'}
                                    className={generation.cache_hit ? 'text-green-600' : ''}
                                    style={generation.cache_hit ? {} : { color: colors.textMuted }}
                                  >
                                    {generation.cache_hit ? '⚡ cache hit' : '● generated'}
                                  </span>
                                  {generation.thinking && (
                                    <span className="text-amber-600" title={`${formatNumber(generation.tokens.thinking)} thinking tokens`}>
                                      🧠 {formatNumber(generation.tokens.thinking)}
                                    </span>
                                  )}
                                  <span>{generation.model || 'unknown-model'}</span>
                                  {generation.provider && <span>{generation.provider}</span>}
                                  <span className="text-blue-500">in:{formatNumber(generation.tokens.input)}</span>
                                  <span className="text-green-600">out:{formatNumber(generation.tokens.output)}</span>
                                  {generation.finish_reason && <span>{generation.finish_reason}</span>}
                                  {generation.duration_seconds != null && <span>{(generation.duration_seconds * 1000).toFixed(0)}ms</span>}
                                  {generation.trace_id && (
                                    <span title={generation.trace_id} style={{ color: colors.textMuted }}>
                                      trace:{generation.trace_id.slice(0, 8)}
                                    </span>
                                  )}
                                </div>
                              ))}
                            </div>
                          </div>
                        )}
                      </>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
