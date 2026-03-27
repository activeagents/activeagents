import React, { useState } from 'react';
import { useTheme } from '../../contexts/ThemeContext';

export default function PromptsView() {
  const { darkMode } = useTheme();
  const [prompts, setPrompts] = useState([
    {
      id: 1,
      name: 'Translation System Prompt',
      content: 'You are a professional translator. Translate the following text accurately while preserving tone and context.',
      agent: 'TranslationAgent',
      type: 'system',
      createdAt: '2024-03-20',
    },
    {
      id: 2,
      name: 'Code Review Instructions',
      content: 'Review the following code for bugs, security issues, and best practices. Provide specific suggestions for improvement.',
      agent: 'CodeReviewAgent',
      type: 'system',
      createdAt: '2024-03-19',
    },
  ]);

  const cardStyle = {
    backgroundColor: darkMode ? '#1f1f1f' : '#ffffff',
    borderColor: darkMode ? '#2a2a2a' : '#e5e7eb',
  };

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className={`text-2xl font-bold ${darkMode ? 'text-white' : 'text-gray-900'}`}>
            Prompts
          </h2>
          <p className={`mt-1 ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
            Manage and version your agent prompts
          </p>
        </div>
        <button className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-colors flex items-center space-x-2">
          <span>+</span>
          <span>New Prompt</span>
        </button>
      </div>

      {/* Prompt Categories */}
      <div className="flex space-x-4">
        <button className="px-4 py-2 bg-red-100 text-red-700 rounded-lg font-medium">
          All Prompts
        </button>
        <button className={`px-4 py-2 rounded-lg ${darkMode ? 'text-gray-400 hover:bg-gray-800' : 'text-gray-600 hover:bg-gray-100'}`}>
          System
        </button>
        <button className={`px-4 py-2 rounded-lg ${darkMode ? 'text-gray-400 hover:bg-gray-800' : 'text-gray-600 hover:bg-gray-100'}`}>
          User Templates
        </button>
        <button className={`px-4 py-2 rounded-lg ${darkMode ? 'text-gray-400 hover:bg-gray-800' : 'text-gray-600 hover:bg-gray-100'}`}>
          Few-shot Examples
        </button>
      </div>

      {/* Prompts Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {prompts.map((prompt) => (
          <div key={prompt.id} className="border rounded-lg p-5" style={cardStyle}>
            <div className="flex items-start justify-between mb-3">
              <div>
                <h3 className={`font-semibold ${darkMode ? 'text-white' : 'text-gray-900'}`}>
                  {prompt.name}
                </h3>
                <p className={`text-sm ${darkMode ? 'text-gray-400' : 'text-gray-500'}`}>
                  Used by: {prompt.agent}
                </p>
              </div>
              <span className={`px-2 py-1 text-xs rounded ${
                prompt.type === 'system'
                  ? 'bg-blue-100 text-blue-700'
                  : 'bg-green-100 text-green-700'
              }`}>
                {prompt.type}
              </span>
            </div>

            <div className={`p-3 rounded-lg text-sm font-mono mb-3 ${
              darkMode ? 'bg-gray-800 text-gray-300' : 'bg-gray-50 text-gray-700'
            }`}>
              <p className="line-clamp-3">{prompt.content}</p>
            </div>

            <div className="flex items-center justify-between">
              <span className={`text-xs ${darkMode ? 'text-gray-500' : 'text-gray-400'}`}>
                Created {prompt.createdAt}
              </span>
              <div className="flex space-x-2">
                <button className={`px-3 py-1 text-sm rounded ${
                  darkMode ? 'bg-gray-700 text-gray-300 hover:bg-gray-600' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}>
                  Edit
                </button>
                <button className={`px-3 py-1 text-sm rounded ${
                  darkMode ? 'bg-gray-700 text-gray-300 hover:bg-gray-600' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}>
                  Versions
                </button>
              </div>
            </div>
          </div>
        ))}

        {/* Empty State / Add New */}
        <div
          className="border-2 border-dashed rounded-lg p-8 flex flex-col items-center justify-center cursor-pointer hover:border-red-400 transition-colors"
          style={{ borderColor: darkMode ? '#3a3a3a' : '#d1d5db' }}
        >
          <div className={`w-12 h-12 rounded-full flex items-center justify-center mb-3 ${
            darkMode ? 'bg-gray-800' : 'bg-gray-100'
          }`}>
            <span className="text-2xl">+</span>
          </div>
          <p className={`font-medium ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>
            Create New Prompt
          </p>
          <p className={`text-sm ${darkMode ? 'text-gray-500' : 'text-gray-500'}`}>
            Version-controlled prompt templates
          </p>
        </div>
      </div>

      {/* Info Banner */}
      <div className={`rounded-lg p-4 ${darkMode ? 'bg-blue-900/20 border border-blue-800' : 'bg-blue-50 border border-blue-200'}`}>
        <div className="flex items-start space-x-3">
          <span className="text-blue-500 text-xl">💡</span>
          <div>
            <p className={`font-medium ${darkMode ? 'text-blue-300' : 'text-blue-800'}`}>
              Pro Tip: Version Your Prompts
            </p>
            <p className={`text-sm mt-1 ${darkMode ? 'text-blue-400' : 'text-blue-600'}`}>
              Keep track of prompt changes with version history. Compare performance between versions using evaluations.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
