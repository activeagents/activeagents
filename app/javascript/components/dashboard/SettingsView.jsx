import React, { useState } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

export default function SettingsView({ user, account }) {
  const { darkMode, toggleDarkMode } = useTheme();
  const [activeTab, setActiveTab] = useState('profile');

  const cardStyle = {
    backgroundColor: darkMode ? '#1f1f1f' : '#ffffff',
    borderColor: darkMode ? '#2a2a2a' : '#e5e7eb',
  };

  const tabs = [
    { id: 'profile', label: 'Profile' },
    { id: 'api-keys', label: 'API Keys' },
    { id: 'notifications', label: 'Notifications' },
    { id: 'billing', label: 'Billing' },
  ];

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div>
        <h2 className={`text-2xl font-bold ${darkMode ? 'text-white' : 'text-gray-900'}`}>
          Settings
        </h2>
        <p className={`mt-1 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
          Manage your account and preferences
        </p>
      </div>

      {/* Tabs */}
      <div className="border-b" style={{ borderColor: darkMode ? '#2a2a2a' : '#e5e7eb' }}>
        <nav className="flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors ${
                activeTab === tab.id
                  ? 'border-red-500 text-red-500'
                  : `border-transparent ${darkMode ? 'text-gray-400 hover:text-gray-300' : 'text-gray-500 hover:text-gray-700'}`
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>
      </div>

      {/* Profile Tab */}
      {activeTab === 'profile' && (
        <div className="space-y-6">
          <div className="border rounded-lg p-6" style={cardStyle}>
            <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
              Profile Information
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className={`block text-sm font-medium mb-1 ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>
                  First Name
                </label>
                <input
                  type="text"
                  defaultValue={user?.name?.split(' ')[0] || ''}
                  className={`w-full px-3 py-2 border rounded-lg ${
                    darkMode
                      ? 'bg-gray-800 border-gray-700 text-white'
                      : 'bg-white border-gray-300 text-gray-900'
                  }`}
                />
              </div>
              <div>
                <label className={`block text-sm font-medium mb-1 ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>
                  Last Name
                </label>
                <input
                  type="text"
                  defaultValue={user?.name?.split(' ')[1] || ''}
                  className={`w-full px-3 py-2 border rounded-lg ${
                    darkMode
                      ? 'bg-gray-800 border-gray-700 text-white'
                      : 'bg-white border-gray-300 text-gray-900'
                  }`}
                />
              </div>
              <div className="md:col-span-2">
                <label className={`block text-sm font-medium mb-1 ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>
                  Email
                </label>
                <input
                  type="email"
                  defaultValue={user?.email || ''}
                  disabled
                  className={`w-full px-3 py-2 border rounded-lg cursor-not-allowed ${
                    darkMode
                      ? 'bg-gray-900 border-gray-700 text-gray-500'
                      : 'bg-gray-100 border-gray-300 text-gray-500'
                  }`}
                />
              </div>
            </div>
            <button className="mt-4 px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600">
              Save Changes
            </button>
          </div>

          {/* Appearance */}
          <div className="border rounded-lg p-6" style={cardStyle}>
            <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
              Appearance
            </h3>
            <div className="flex items-center justify-between">
              <div>
                <p className={`font-medium ${darkMode ? 'text-white' : 'text-gray-900'}`}>
                  Dark Mode
                </p>
                <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
                  Use dark theme across the dashboard
                </p>
              </div>
              <button
                onClick={toggleDarkMode}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  darkMode ? 'bg-red-500' : 'bg-gray-300'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    darkMode ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* API Keys Tab */}
      {activeTab === 'api-keys' && (
        <div className="space-y-6">
          <div className="border rounded-lg p-6" style={cardStyle}>
            <div className="flex items-center justify-between mb-4">
              <h3 className={`text-lg font-semibold ${darkMode ? 'text-white' : 'text-gray-900'}`}>
                API Keys
              </h3>
              <button className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600">
                + Create New Key
              </button>
            </div>

            <div className={`p-4 rounded-lg mb-4 ${darkMode ? 'bg-yellow-900/20 border border-yellow-800' : 'bg-yellow-50 border border-yellow-200'}`}>
              <p className={`text-sm ${darkMode ? 'text-yellow-300' : 'text-yellow-800'}`}>
                ⚠️ API keys are secrets. Never share them or commit them to version control.
              </p>
            </div>

            <div className={`text-center py-8 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
              <p>No API keys yet</p>
              <p className="text-sm">Create your first API key to authenticate requests</p>
            </div>
          </div>

          <div className="border rounded-lg p-6" style={cardStyle}>
            <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
              Provider API Keys
            </h3>
            <p className={`text-sm mb-4 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
              Configure API keys for LLM providers (OpenAI, Anthropic, etc.)
            </p>
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 rounded-lg" style={{ backgroundColor: darkMode ? '#252525' : '#f9fafb' }}>
                <div className="flex items-center space-x-3">
                  <span className="text-xl">🤖</span>
                  <div>
                    <p className={`font-medium ${darkMode ? 'text-white' : 'text-gray-900'}`}>OpenAI</p>
                    <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Not configured</p>
                  </div>
                </div>
                <button className={`px-3 py-1 text-sm rounded ${
                  darkMode ? 'bg-gray-700 text-gray-300' : 'bg-gray-200 text-gray-700'
                }`}>
                  Configure
                </button>
              </div>
              <div className="flex items-center justify-between p-4 rounded-lg" style={{ backgroundColor: darkMode ? '#252525' : '#f9fafb' }}>
                <div className="flex items-center space-x-3">
                  <span className="text-xl">🧠</span>
                  <div>
                    <p className={`font-medium ${darkMode ? 'text-white' : 'text-gray-900'}`}>Anthropic</p>
                    <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Not configured</p>
                  </div>
                </div>
                <button className={`px-3 py-1 text-sm rounded ${
                  darkMode ? 'bg-gray-700 text-gray-300' : 'bg-gray-200 text-gray-700'
                }`}>
                  Configure
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Notifications Tab */}
      {activeTab === 'notifications' && (
        <div className="border rounded-lg p-6" style={cardStyle}>
          <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
            Email Notifications
          </h3>
          <div className="space-y-4">
            {[
              { label: 'Agent execution alerts', desc: 'Get notified when agents fail or complete', enabled: true },
              { label: 'Weekly usage reports', desc: 'Summary of traces, costs, and performance', enabled: true },
              { label: 'Security alerts', desc: 'Important security notifications', enabled: true },
              { label: 'Product updates', desc: 'New features and improvements', enabled: false },
            ].map((item, i) => (
              <div key={i} className="flex items-center justify-between py-3 border-b" style={{ borderColor: darkMode ? '#2a2a2a' : '#e5e7eb' }}>
                <div>
                  <p className={`font-medium ${darkMode ? 'text-white' : 'text-gray-900'}`}>{item.label}</p>
                  <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>{item.desc}</p>
                </div>
                <button className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  item.enabled ? 'bg-red-500' : (darkMode ? 'bg-gray-700' : 'bg-gray-300')
                }`}>
                  <span className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    item.enabled ? 'translate-x-6' : 'translate-x-1'
                  }`} />
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Billing Tab */}
      {activeTab === 'billing' && (
        <div className="space-y-6">
          <div className="border rounded-lg p-6" style={cardStyle}>
            <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
              Subscription
            </h3>
            <div className="flex items-center justify-between p-4 rounded-lg" style={{ backgroundColor: darkMode ? '#252525' : '#f9fafb' }}>
              <div>
                <p className={`font-medium ${darkMode ? 'text-white' : 'text-gray-900'}`}>Free Plan</p>
                <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>Current plan</p>
              </div>
              <button className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600">
                Upgrade to Pro
              </button>
            </div>
          </div>

          <div className="border rounded-lg p-6" style={cardStyle}>
            <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
              Payment Method
            </h3>
            <p className={`${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
              No payment method on file
            </p>
            <button className={`mt-4 px-4 py-2 rounded-lg ${
              darkMode ? 'bg-gray-700 text-gray-300' : 'bg-gray-200 text-gray-700'
            }`}>
              Add Payment Method
            </button>
          </div>

          <div className="border rounded-lg p-6" style={cardStyle}>
            <h3 className={`text-lg font-semibold mb-4 ${darkMode ? 'text-white' : 'text-gray-900'}`}>
              Invoices
            </h3>
            <p className={`${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
              No invoices yet
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
