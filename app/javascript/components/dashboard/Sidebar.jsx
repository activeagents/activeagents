import React from 'react';
import AgentAvatar from '../AgentAvatar';

export default function Sidebar({ currentView, onNavigate, agentCount }) {
  const menuItems = [
    { id: 'list', label: 'Agents', icon: '🤖', badge: agentCount },
    { id: 'analytics', label: 'Analytics', icon: '📊' },
    { id: 'builder', label: 'New Agent', icon: '✨' },
  ];

  return (
    <aside className="w-64 bg-white border-r border-gray-200 flex flex-col">
      {/* Logo - uses the same mascot SVG as the lander */}
      <div className="h-16 flex items-center px-6 border-b border-gray-200">
        <div className="flex items-center space-x-2">
          <AgentAvatar size={28} />
          <span className="font-bold text-xl text-gray-900">Active Agent</span>
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-4 py-4 space-y-1">
        {menuItems.map((item) => (
          <button
            key={item.id}
            onClick={() => onNavigate(item.id)}
            className={`w-full flex items-center justify-between px-4 py-3 rounded-lg text-left transition-colors ${
              currentView === item.id
                ? 'bg-red-50 text-red-600'
                : 'text-gray-700 hover:bg-gray-100'
            }`}
          >
            <div className="flex items-center space-x-3">
              <span className="text-lg">{item.icon}</span>
              <span className="font-medium">{item.label}</span>
            </div>
            {item.badge !== undefined && (
              <span className={`px-2 py-0.5 text-xs rounded-full ${
                currentView === item.id
                  ? 'bg-red-100 text-red-600'
                  : 'bg-gray-100 text-gray-600'
              }`}>
                {item.badge}
              </span>
            )}
          </button>
        ))}
      </nav>

      {/* Quick Links */}
      <div className="px-4 py-4 border-t border-gray-200">
        <div className="text-xs font-semibold text-gray-400 uppercase mb-3">Resources</div>
        <div className="space-y-2">
          <a
            href="https://docs.activeagents.ai"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center space-x-2 text-sm text-gray-600 hover:text-red-600 transition-colors"
          >
            <span>📚</span>
            <span>Documentation</span>
          </a>
          <a
            href="https://github.com/activeagents/activeagent"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center space-x-2 text-sm text-gray-600 hover:text-red-600 transition-colors"
          >
            <span>💻</span>
            <span>GitHub</span>
          </a>
        </div>
      </div>

      {/* Version */}
      <div className="px-6 py-4 border-t border-gray-200">
        <div className="text-xs text-gray-400">
          Active Agent v1.0.1
        </div>
      </div>
    </aside>
  );
}
