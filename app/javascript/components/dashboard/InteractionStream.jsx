import React, { useState } from 'react';
import Markdown from './Markdown';

// Shared conversation stream renderer: role-labeled messages with
// click-to-expand details (tool name/arguments/results, durations,
// checksums). Used by the Interactions view and the agent Conversation
// History run detail — same component, different UX context.

const formatMs = (ms) => {
  if (ms == null) return null;
  if (ms < 1000) return `${Math.round(ms)}ms`;
  return `${(ms / 1000).toFixed(2)}s`;
};

// Pretty-print a value that may be a JSON string, object, or plain text.
const prettyJson = (value) => {
  if (value == null) return null;
  if (typeof value === 'object') return JSON.stringify(value, null, 2);
  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return null;
  }
};

const hasDetails = (message) =>
  Boolean(
    message.tool_name || message.tool_call_id || message.tool_arguments ||
    message.tool_result || (message.tool_calls || []).length > 0 ||
    message.duration_ms != null || prettyJson(message.content)
  );

const roleBubble = (role, darkMode) => {
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
    case 'system':
      return darkMode
        ? { background: 'rgba(139,92,246,0.15)', color: '#c4b5fd', label: 'System' }
        : { background: '#f5f3ff', color: '#6d28d9', label: 'System' };
    case 'developer':
      return darkMode
        ? { background: 'rgba(20,184,166,0.15)', color: '#5eead4', label: 'Dev' }
        : { background: '#f0fdfa', color: '#0f766e', label: 'Dev' };
    default:
      return darkMode
        ? { background: 'rgba(255,255,255,0.08)', color: 'rgba(255,255,255,0.7)', label: role }
        : { background: '#f3f4f6', color: '#374151', label: role };
  }
};

export default function InteractionStream({ messages, darkMode }) {
  const [expandedMessages, setExpandedMessages] = useState({});

  const toggleMessage = (id) =>
    setExpandedMessages((prev) => ({ ...prev, [id]: !prev[id] }));

  const colors = {
    textPrimary: darkMode ? '#ffffff' : '#111827',
    textSecondary: darkMode ? 'rgba(255,255,255,0.6)' : '#6b7280',
    textMuted: darkMode ? 'rgba(255,255,255,0.4)' : '#9ca3af',
  };

  return (
    <div className="space-y-3">
      {(messages || []).map((message) => {
        const bubble = roleBubble(message.role, darkMode);
        const isExpanded = !!expandedMessages[message.id];
        const expandable = hasDetails(message);
        const argsJson = prettyJson(message.tool_arguments);
        const resultJson = prettyJson(message.tool_result) || prettyJson(message.content);
        const toolCallsJson = (message.tool_calls || []).length > 0 ? prettyJson(message.tool_calls) : null;
        const preStyle = {
          background: darkMode ? 'rgba(0,0,0,0.35)' : '#f3f4f6',
          color: colors.textPrimary,
          borderRadius: '6px',
          padding: '8px 10px',
          fontSize: '12px',
          overflowX: 'auto',
          margin: 0,
        };
        return (
          <div key={message.id}>
            <div
              className={`flex gap-3 items-start rounded-lg -mx-2 px-2 py-1 ${expandable ? 'cursor-pointer' : ''}`}
              onClick={expandable ? () => toggleMessage(message.id) : undefined}
              style={isExpanded ? { background: darkMode ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)' } : {}}
            >
              <span
                className="px-2 py-0.5 rounded text-xs font-medium flex-shrink-0 mt-0.5"
                style={{ background: bubble.background, color: bubble.color, minWidth: '72px', textAlign: 'center' }}
              >
                {bubble.label}
              </span>
              <div className="min-w-0 flex-1">
                <div className="text-sm break-words" style={{ color: colors.textPrimary }}>
                  {message.role === 'tool' ? (
                    <span className="whitespace-pre-wrap">
                      {message.content || (message.tool_name ? `→ ${message.tool_name}(...)` : '—')}
                    </span>
                  ) : (
                    <Markdown text={message.content || '—'} />
                  )}
                </div>
                <div className="text-xs mt-0.5 font-mono flex items-center gap-2 flex-wrap" style={{ color: colors.textMuted }}>
                  <span>{new Date(message.created_at).toLocaleTimeString()}</span>
                  {message.tool_name && (
                    <span
                      className="px-1.5 py-0.5 rounded"
                      style={{ background: bubble.background, color: bubble.color }}
                    >
                      ⚙ {message.tool_name}
                    </span>
                  )}
                  {message.duration_ms != null && <span>{formatMs(message.duration_ms)}</span>}
                  {(message.tool_calls || []).length > 0 && (
                    <span>{message.tool_calls.length} tool call{message.tool_calls.length > 1 ? 's' : ''}</span>
                  )}
                  {message.content_checksum && (
                    <span title="Content fingerprint">🔒 {message.content_checksum.slice(0, 8)}</span>
                  )}
                </div>
              </div>
              {expandable && (
                <svg
                  className={`w-3.5 h-3.5 mt-1 flex-shrink-0 transition-transform ${isExpanded ? 'rotate-180' : ''}`}
                  fill="none" stroke="currentColor" viewBox="0 0 24 24"
                  style={{ color: colors.textMuted }}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              )}
            </div>

            {isExpanded && (
              <div
                className="ml-3 mt-1 mb-2 pl-4 space-y-2 border-l-2"
                style={{ borderColor: bubble.color + '55' }}
              >
                <div className="flex flex-wrap gap-x-5 gap-y-1 text-xs font-mono" style={{ color: colors.textSecondary }}>
                  <span>{new Date(message.created_at).toLocaleString()}</span>
                  {message.tool_call_id && <span>call: {message.tool_call_id}</span>}
                  {message.duration_ms != null && <span>took {formatMs(message.duration_ms)}</span>}
                  {message.content_checksum && <span>🔒 {message.content_checksum}</span>}
                </div>
                {argsJson && (
                  <div>
                    <div className="text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>Arguments</div>
                    <pre style={preStyle}>{argsJson}</pre>
                  </div>
                )}
                {resultJson && (
                  <div>
                    <div className="text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>
                      {message.role === 'tool' ? 'Result' : 'Content (parsed)'}
                    </div>
                    <pre style={preStyle}>{resultJson}</pre>
                  </div>
                )}
                {toolCallsJson && (
                  <div>
                    <div className="text-xs uppercase tracking-wide mb-1" style={{ color: colors.textMuted }}>Requested tool calls</div>
                    <pre style={preStyle}>{toolCallsJson}</pre>
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
