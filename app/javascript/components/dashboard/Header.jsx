import React from 'react';
import { useTheme } from '../../contexts/ThemeContext';

const VIEW_TITLES = {
  list: 'Your Agents',
  builder: 'Create New Agent',
  editor: 'Edit Agent',
  runner: 'Run Agent'
};

export default function Header({ user, currentView, selectedAgent }) {
  const { darkMode, toggleDarkMode } = useTheme();

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
    : `${user?.name ? `Welcome back, ${user.name}` : 'Manage your AI agents'}`;

  return (
    <header
      className="h-16 border-b flex items-center justify-between px-6"
      style={{
        backgroundColor: darkMode ? '#1a1a1a' : '#ffffff',
        borderColor: darkMode ? '#2a2a2a' : '#e5e7eb'
      }}
    >
      <div>
        <h1 className={`text-xl font-semibold ${darkMode ? 'text-white' : 'text-gray-900'}`}>{title}</h1>
        <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>{subtitle}</p>
      </div>

      <div className="flex items-center space-x-4">
        {/* Dark mode toggle */}
        <button
          onClick={toggleDarkMode}
          className="p-2 rounded-lg transition-colors"
          style={{
            backgroundColor: darkMode ? '#252525' : '#f3f4f6',
            color: darkMode ? '#fbbf24' : '#4b5563'
          }}
          title={darkMode ? 'Switch to light mode' : 'Switch to dark mode'}
        >
          {darkMode ? (
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
            </svg>
          ) : (
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
              <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
            </svg>
          )}
        </button>

        {/* Status indicator */}
        <div className={`flex items-center space-x-2 text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
          <span className="w-2 h-2 bg-green-400 rounded-full"></span>
          <span>Connected</span>
        </div>

        {/* User avatar */}
        <div className="w-8 h-8 bg-red-100 rounded-full flex items-center justify-center">
          <span className="text-red-600 font-medium text-sm">
            {user?.name?.charAt(0).toUpperCase() || 'D'}
          </span>
        </div>
      </div>
    </header>
  );
}
