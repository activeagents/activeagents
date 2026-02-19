import React from 'react';

const VIEW_TITLES = {
  list: 'Your Agents',
  builder: 'Create New Agent',
  editor: 'Edit Agent',
  runner: 'Run Agent'
};

export default function Header({ user, currentView, selectedAgent }) {
  const title = currentView === 'editor' && selectedAgent
    ? selectedAgent.name
    : currentView === 'runner' && selectedAgent
    ? `Run: ${selectedAgent.name}`
    : VIEW_TITLES[currentView] || 'Dashboard';

  const subtitle = currentView === 'editor' && selectedAgent
    ? `${selectedAgent.provider} / ${selectedAgent.model}`
    : currentView === 'runner' && selectedAgent
    ? 'Test and execute your agent'
    : currentView === 'builder'
    ? 'Configure your AI agent step by step'
    : `${user?.display_name ? `Welcome back, ${user.display_name}` : 'Manage your AI agents'}`;

  return (
    <header className="h-16 bg-white border-b border-gray-200 flex items-center justify-between px-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">{title}</h1>
        <p className="text-sm text-gray-500">{subtitle}</p>
      </div>

      <div className="flex items-center space-x-4">
        {/* Status indicator */}
        <div className="flex items-center space-x-2 text-sm text-gray-500">
          <span className="w-2 h-2 bg-green-400 rounded-full"></span>
          <span>Connected</span>
        </div>

        {/* User avatar */}
        <div className="w-8 h-8 bg-rose-100 rounded-full flex items-center justify-center">
          <span className="text-rose-600 font-medium text-sm">
            {user?.display_name?.charAt(0).toUpperCase() || user?.email_address?.charAt(0).toUpperCase() || 'U'}
          </span>
        </div>
      </div>
    </header>
  );
}
