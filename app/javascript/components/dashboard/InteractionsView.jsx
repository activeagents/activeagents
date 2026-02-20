import React, { useState, useEffect } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

// Mock data matching the lander preview design
const MOCK_SESSIONS = [
  {
    id: 'user_8f2a_chat',
    user_id: 'user_8f2a',
    created_at: new Date(Date.now() - 300000).toISOString(),
    fragments: [
      {
        id: 'frag_a8c2',
        type: 'message',
        cache_status: 'hit',
        messages: [
          { role: 'user', content: 'How do I reset my password?' },
          { role: 'assistant', content: 'I can help with that. Let me look up...' },
        ],
      },
      {
        id: 'frag_b3d1',
        type: 'tool',
        cache_status: 'deterministic',
        hash: '7f2e8a',
        duration_ms: 234,
        messages: [
          { role: 'assistant', tool_call: { name: 'lookup_user', args: { email: 'user@...' } } },
          { role: 'tool', content: { found: true, user_id: 1847 } },
        ],
      },
      {
        id: 'frag_c9e4',
        type: 'message',
        cache_status: 'generated',
        messages: [
          { role: 'assistant', content: "I found your account. I've sent a password reset link to your email.", citation: 'user.email' },
        ],
      },
    ],
  },
  {
    id: 'user_3b7c_code',
    user_id: 'user_3b7c',
    created_at: new Date(Date.now() - 600000).toISOString(),
    fragments: [
      {
        id: 'frag_d4e5',
        type: 'message',
        cache_status: 'hit',
        messages: [
          { role: 'user', content: 'Review this function for security issues' },
          { role: 'assistant', content: "I'll analyze the code for potential security vulnerabilities..." },
        ],
      },
      {
        id: 'frag_e5f6',
        type: 'tool',
        cache_status: 'deterministic',
        hash: 'a3b4c5',
        duration_ms: 156,
        messages: [
          { role: 'assistant', tool_call: { name: 'analyze_code', args: { file: 'auth.rb', checks: ['sql_injection', 'xss'] } } },
          { role: 'tool', content: { issues: 2, severity: 'medium' } },
        ],
      },
    ],
  },
];

export default function InteractionsView() {
  const { darkMode } = useTheme();
  const [sessions, setSessions] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [expandedSession, setExpandedSession] = useState(null);

  useEffect(() => {
    setTimeout(() => {
      setSessions(MOCK_SESSIONS);
      setIsLoading(false);
      setExpandedSession(MOCK_SESSIONS[0]?.id);
    }, 500);
  }, []);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-red-500"></div>
      </div>
    );
  }

  // Light mode version
  if (!darkMode) {
    return (
      <div className="space-y-6">
        {/* Header */}
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Interactions</h1>
          <p className="text-sm text-gray-500 mt-1">Message fragments cached for replay. Tool calls are deterministic.</p>
        </div>

        {/* Sessions List */}
        <div className="space-y-4">
          {sessions.map((session) => (
            <div key={session.id} className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
              <div
                className="flex items-center justify-between p-4 cursor-pointer hover:bg-gray-50"
                onClick={() => setExpandedSession(expandedSession === session.id ? null : session.id)}
              >
                <div className="flex items-center gap-3">
                  <span className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-700 rounded">SESSION</span>
                  <span className="font-mono text-sm text-gray-900">{session.id}</span>
                </div>
                <span className="text-sm text-gray-500">{session.fragments.length} fragments</span>
              </div>

              {expandedSession === session.id && (
                <div className="border-t border-gray-200 p-4 space-y-4">
                  {session.fragments.map((fragment) => (
                    <div key={fragment.id} className={`rounded-lg border ${fragment.type === 'tool' ? 'border-yellow-200 bg-yellow-50' : 'border-gray-200 bg-gray-50'} p-4`}>
                      <div className="flex items-center gap-2 mb-3">
                        <span className={`px-2 py-1 text-xs font-medium rounded ${fragment.type === 'tool' ? 'bg-yellow-200 text-yellow-800' : 'bg-gray-200 text-gray-700'}`}>
                          {fragment.type === 'tool' ? 'TOOL FRAGMENT' : 'FRAGMENT'}
                        </span>
                        <span className="font-mono text-xs text-gray-500">{fragment.id}</span>
                        {fragment.cache_status === 'hit' && (
                          <span className="text-xs text-green-600 flex items-center gap-1">
                            <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z" clipRule="evenodd" /></svg>
                            cache hit
                          </span>
                        )}
                        {fragment.cache_status === 'deterministic' && (
                          <span className="text-xs text-purple-600 flex items-center gap-1">
                            <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clipRule="evenodd" /></svg>
                            deterministic
                          </span>
                        )}
                        {fragment.cache_status === 'generated' && (
                          <span className="text-xs text-orange-600 flex items-center gap-1">
                            <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><circle cx="10" cy="10" r="5" /></svg>
                            generated
                          </span>
                        )}
                      </div>
                      <div className="space-y-2">
                        {fragment.messages.map((msg, idx) => (
                          <div key={idx} className="flex items-start gap-2 text-sm">
                            <span className={`font-medium min-w-[70px] ${msg.role === 'user' ? 'text-blue-600' : msg.role === 'assistant' ? 'text-green-600' : 'text-purple-600'}`}>
                              {msg.role}:
                            </span>
                            {msg.content && (
                              <span className="text-gray-700">
                                {typeof msg.content === 'string'
                                  ? `"${msg.content}"`
                                  : <code className="px-1 py-0.5 bg-gray-200 rounded text-xs">{JSON.stringify(msg.content)}</code>
                                }
                              </span>
                            )}
                            {msg.tool_call && (
                              <span className="text-gray-700">
                                <span className="font-mono text-purple-600">{msg.tool_call.name}</span>
                                <code className="ml-1 px-1 py-0.5 bg-gray-200 rounded text-xs">{JSON.stringify(msg.tool_call.args)}</code>
                              </span>
                            )}
                          </div>
                        ))}
                      </div>
                      {(fragment.hash || fragment.duration_ms) && (
                        <div className="flex items-center gap-4 mt-3 pt-3 border-t border-gray-200 text-xs text-gray-500">
                          {fragment.hash && (
                            <span className="flex items-center gap-1">
                              <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M6.625 2.655A9 9 0 0119 11a1 1 0 11-2 0 7 7 0 00-9.625-6.492 1 1 0 11-.75-1.853zM4.662 4.959A1 1 0 014.75 6.37 6.97 6.97 0 003 11a1 1 0 11-2 0 8.97 8.97 0 012.25-5.953 1 1 0 011.412-.088z" clipRule="evenodd" /></svg>
                              hash: {fragment.hash}
                            </span>
                          )}
                          {fragment.duration_ms && (
                            <span className="flex items-center gap-1">
                              <svg className="w-3 h-3" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clipRule="evenodd" /></svg>
                              {fragment.duration_ms}ms
                            </span>
                          )}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>

        {sessions.length === 0 && (
          <div className="text-center py-12 bg-white rounded-xl border border-gray-200">
            <div className="text-gray-500 text-lg">No sessions yet</div>
            <p className="text-gray-400 text-sm mt-2">Interactions will appear here as agents process requests</p>
          </div>
        )}
      </div>
    );
  }

  // Dark mode version
  return (
    <div className="preview-content" style={{ borderRadius: '12px', overflow: 'hidden', minHeight: 'calc(100vh - 200px)' }}>
      {/* Header inside dark container */}
      <div style={{ padding: '24px 24px 0 24px', borderBottom: '1px solid rgba(255,255,255,0.1)', marginBottom: '16px', paddingBottom: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <h1 style={{ fontSize: '24px', fontWeight: 'bold', color: 'white', margin: 0 }}>Interactions</h1>
            <p style={{ fontSize: '14px', color: 'rgba(255,255,255,0.6)', marginTop: '4px' }}>Message fragments cached for replay. Tool calls are deterministic.</p>
          </div>
        </div>
      </div>

      <div className="preview-sessions">
        {sessions.map((session) => (
          <React.Fragment key={session.id}>
            <div
              className="session-header"
              onClick={() => setExpandedSession(expandedSession === session.id ? null : session.id)}
              style={{ cursor: 'pointer' }}
            >
              <span className="session-badge">SESSION</span>
              <span className="session-id">{session.id}</span>
              <span className="session-count">{session.fragments.length} fragments</span>
            </div>

            {expandedSession === session.id && (
              <div className="session-fragments">
                {session.fragments.map((fragment) => (
                  <div key={fragment.id} className={`fragment ${fragment.type === 'tool' ? 'expanded' : ''}`}>
                    <div className="fragment-header">
                      <span className={`fragment-badge ${fragment.type === 'tool' ? 'tool' : ''}`}>
                        {fragment.type === 'tool' ? 'TOOL FRAGMENT' : 'FRAGMENT'}
                      </span>
                      <span className="fragment-hash">{fragment.id}</span>
                      {fragment.cache_status === 'hit' && (
                        <span className="fragment-cache hit">
                          <i className="fa-solid fa-bolt"></i> cache hit
                        </span>
                      )}
                      {fragment.cache_status === 'deterministic' && (
                        <span className="fragment-deterministic">
                          <i className="fa-solid fa-lock"></i> deterministic
                        </span>
                      )}
                      {fragment.cache_status === 'generated' && (
                        <span className="fragment-cache miss">
                          <i className="fa-solid fa-circle"></i> generated
                        </span>
                      )}
                    </div>
                    <div className="fragment-messages">
                      {fragment.messages.map((msg, idx) => (
                        <div key={idx} className={`msg msg-${msg.role}`}>
                          <span className="msg-role">{msg.role}</span>
                          {msg.content && (
                            <span className="msg-content">
                              {typeof msg.content === 'string'
                                ? `"${msg.content}"`
                                : <span className="tool-result">{JSON.stringify(msg.content)}</span>
                              }
                              {msg.citation && (
                                <span className="msg-citation">[<i className="fa-solid fa-quote-left"></i> {msg.citation}]</span>
                              )}
                            </span>
                          )}
                          {msg.tool_call && (
                            <span className="msg-tool-call">
                              <span className="tool-name">{msg.tool_call.name}</span>
                              <span className="tool-args">{JSON.stringify(msg.tool_call.args)}</span>
                            </span>
                          )}
                        </div>
                      ))}
                    </div>
                    {(fragment.hash || fragment.duration_ms) && (
                      <div className="fragment-meta">
                        {fragment.hash && (
                          <span className="meta-item">
                            <i className="fa-solid fa-fingerprint"></i> hash: {fragment.hash}
                          </span>
                        )}
                        {fragment.duration_ms && (
                          <span className="meta-item">
                            <i className="fa-solid fa-clock"></i> {fragment.duration_ms}ms
                          </span>
                        )}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </React.Fragment>
        ))}
      </div>

      {sessions.length === 0 && (
        <div style={{ textAlign: 'center', padding: '48px 0' }}>
          <div style={{ color: 'rgba(255,255,255,0.5)', fontSize: '18px' }}>No sessions yet</div>
          <p style={{ color: 'rgba(255,255,255,0.4)', fontSize: '14px', marginTop: '8px' }}>Interactions will appear here as agents process requests</p>
        </div>
      )}
    </div>
  );
}
