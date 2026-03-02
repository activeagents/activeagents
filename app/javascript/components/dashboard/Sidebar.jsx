import React from 'react';
import AgentAvatar from '../AgentAvatar';
import { useTheme } from '../../contexts/ThemeContext';

export default function Sidebar({ currentView, onNavigate, agentCount }) {
  const { darkMode } = useTheme();

  const agentItems = [
    { id: 'list', label: 'Agents', icon: '🤖', badge: agentCount },
    { id: 'builder', label: 'New Agent', icon: '✨' },
    { id: 'sandbox', label: 'Try Demo', icon: '🎭', highlight: true },
  ];

  const observabilityItems = [
    { id: 'traces', label: 'Traces', icon: '📍' },
    { id: 'metrics', label: 'Metrics', icon: '📊' },
    { id: 'evaluations', label: 'Evaluations', icon: '⚖️' },
    { id: 'interactions', label: 'Interactions', icon: '💬' },
    { id: 'benchmarks', label: 'Benchmarks', icon: '⚡' },
  ];

  const NavButton = ({ item }) => (
    <button
      onClick={() => onNavigate(item.id)}
      className="w-full flex items-center justify-between px-4 py-3 rounded-lg text-left transition-colors"
      style={{
        backgroundColor: currentView === item.id
          ? (darkMode ? 'rgba(239, 68, 68, 0.15)' : '#fef2f2')
          : 'transparent',
        color: currentView === item.id
          ? '#ef4444'
          : (darkMode ? '#d1d5db' : '#374151')
      }}
      onMouseEnter={(e) => {
        if (currentView !== item.id) {
          e.currentTarget.style.backgroundColor = darkMode ? '#252525' : '#f3f4f6';
        }
      }}
      onMouseLeave={(e) => {
        if (currentView !== item.id) {
          e.currentTarget.style.backgroundColor = 'transparent';
        }
      }}
    >
      <div className="flex items-center space-x-3">
        <span className="text-lg">{item.icon}</span>
        <span className="font-medium">{item.label}</span>
      </div>
      {item.badge !== undefined && (
        <span
          className="px-2 py-0.5 text-xs rounded-full"
          style={{
            backgroundColor: currentView === item.id
              ? '#fee2e2'
              : (darkMode ? '#2a2a2a' : '#f3f4f6'),
            color: currentView === item.id
              ? '#ef4444'
              : (darkMode ? '#d1d5db' : '#4b5563')
          }}
        >
          {item.badge}
        </span>
      )}
    </button>
  );

  return (
    <aside
      className="w-64 border-r flex flex-col"
      style={{
        backgroundColor: darkMode ? '#1a1a1a' : '#ffffff',
        borderColor: darkMode ? '#2a2a2a' : '#e5e7eb'
      }}
    >
      {/* Logo - uses the same mascot SVG as the lander */}
      <div
        className="h-16 flex items-center px-6 border-b"
        style={{ borderColor: darkMode ? '#2a2a2a' : '#e5e7eb' }}
      >
        <div className="flex items-center space-x-2">
          <AgentAvatar size={28} />
          <span className={`font-bold text-xl ${darkMode ? 'text-white' : 'text-gray-900'}`}>Active Agent</span>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-4 py-4 space-y-1 overflow-y-auto">
        {/* Agents Section */}
        <div className="space-y-1">
          {agentItems.map((item) => (
            <NavButton key={item.id} item={item} />
          ))}
        </div>

        {/* Observability Section */}
        <div className="pt-4">
          <div className="px-4 pb-2">
            <span className={`text-xs font-semibold uppercase tracking-wide ${
              darkMode ? 'text-gray-500' : 'text-gray-400'
            }`}>Observability</span>
          </div>
          <div className="space-y-1">
            {observabilityItems.map((item) => (
              <NavButton key={item.id} item={item} />
            ))}
          </div>
        </div>
      </nav>

      {/* Quick Links */}
      <div className="px-4 py-4 border-t" style={{ borderColor: darkMode ? '#2a2a2a' : '#e5e7eb' }}>
        <div className={`text-xs font-semibold uppercase mb-3 ${
          darkMode ? 'text-gray-500' : 'text-gray-400'
        }`}>Resources</div>
        <div className="space-y-2">
          <a
            href="https://docs.activeagents.ai"
            target="_blank"
            rel="noopener noreferrer"
            className={`flex items-center space-x-2 text-sm transition-colors ${
              darkMode
                ? 'text-gray-400 hover:text-red-400'
                : 'text-gray-600 hover:text-red-600'
            }`}
          >
            <span>📚</span>
            <span>Documentation</span>
          </a>
          <a
            href="https://github.com/activeagents/activeagent"
            target="_blank"
            rel="noopener noreferrer"
            className={`flex items-center space-x-2 text-sm transition-colors ${
              darkMode
                ? 'text-gray-400 hover:text-red-400'
                : 'text-gray-600 hover:text-red-600'
            }`}
          >
            <span>💻</span>
            <span>GitHub</span>
          </a>
        </div>
      </div>

      {/* Version */}
      <div className="px-6 py-4 border-t" style={{ borderColor: darkMode ? '#2a2a2a' : '#e5e7eb' }}>
        <div className={`text-xs ${darkMode ? 'text-gray-500' : 'text-gray-400'}`}>
          Active Agent v1.0.1
        </div>
      </div>
    </aside>
  );
}
