import React, { useState, useEffect, useRef } from 'react';
import AgentAvatar from '../AgentAvatar';
import { TYPOGRAPHY } from '../../utils/designTokens';

export default function AgentRunner({ agent, onBack }) {
  const [prompt, setPrompt] = useState('');
  const [runs, setRuns] = useState([]);
  const [isRunning, setIsRunning] = useState(false);
  const [currentRun, setCurrentRun] = useState(null);
  const outputRef = useRef(null);

  useEffect(() => {
    loadRuns();
  }, [agent.id]);

  useEffect(() => {
    // Auto-scroll to bottom when new output arrives
    if (outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight;
    }
  }, [currentRun?.output]);

  const loadRuns = async () => {
    try {
      const response = await fetch(`/api/agents/${agent.id}/runs?per_page=10`);
      const data = await response.json();
      setRuns(data.runs);
    } catch (error) {
      console.error('Failed to load runs:', error);
    }
  };

  const handleRun = async () => {
    if (!prompt.trim() || isRunning) return;

    setIsRunning(true);
    setCurrentRun({
      status: 'running',
      input_prompt: prompt,
      output: '',
      started_at: new Date().toISOString()
    });

    try {
      const response = await fetch(`/api/agents/${agent.id}/test`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt: prompt })
      });

      const data = await response.json();

      setCurrentRun({
        ...data.run,
        output: data.output
      });

      // Refresh runs list
      loadRuns();
    } catch (error) {
      setCurrentRun(prev => ({
        ...prev,
        status: 'failed',
        error_message: error.message
      }));
    } finally {
      setIsRunning(false);
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      handleRun();
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'complete': return 'text-green-600 bg-green-100';
      case 'failed': return 'text-red-600 bg-red-100';
      case 'running': return 'text-blue-600 bg-blue-100';
      case 'pending': return 'text-yellow-600 bg-yellow-100';
      default: return 'text-gray-600 bg-gray-100';
    }
  };

  const formatDuration = (ms) => {
    if (!ms) return '-';
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
  };

  return (
    <div className="grid grid-cols-3 gap-6 h-full">
      {/* Main Runner Interface */}
      <div className="col-span-2 flex flex-col space-y-4">
        {/* Input */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <div className="flex items-start space-x-4">
            <div className="flex-shrink-0">
              <AgentAvatar size={50} />
            </div>
            <div className="flex-1">
              <textarea
                value={prompt}
                onChange={(e) => setPrompt(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Enter your prompt here... (Cmd+Enter to run)"
                rows={4}
                disabled={isRunning}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent resize-none"
              />
              <div className="flex items-center justify-between mt-3">
                <span className="text-xs text-gray-400">
                  Press <kbd className="px-1.5 py-0.5 bg-gray-100 rounded text-gray-600">⌘</kbd> + <kbd className="px-1.5 py-0.5 bg-gray-100 rounded text-gray-600">Enter</kbd> to run
                </span>
                <button
                  onClick={handleRun}
                  disabled={!prompt.trim() || isRunning}
                  className={`flex items-center space-x-2 px-6 py-2 rounded-lg transition-colors ${
                    prompt.trim() && !isRunning
                      ? 'bg-emerald-500 text-white hover:bg-emerald-600'
                      : 'bg-gray-200 text-gray-400 cursor-not-allowed'
                  }`}
                >
                  {isRunning ? (
                    <>
                      <span className="animate-spin" style={{ fontFamily: TYPOGRAPHY.mono }}>{'[~]'}</span>
                      <span>Running...</span>
                    </>
                  ) : (
                    <>
                      <span style={{ fontFamily: TYPOGRAPHY.mono }}>{'[>]'}</span>
                      <span>Run</span>
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Output */}
        <div className="flex-1 bg-white rounded-xl border border-gray-200 flex flex-col overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
            <h3 className="font-medium text-gray-900">Output</h3>
            {currentRun && (
              <div className="flex items-center space-x-3 text-sm">
                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${getStatusColor(currentRun.status)}`}>
                  {currentRun.status}
                </span>
                {currentRun.duration_ms && (
                  <span className="text-gray-400">{formatDuration(currentRun.duration_ms)}</span>
                )}
                {currentRun.total_tokens && (
                  <span className="text-gray-400">{currentRun.total_tokens} tokens</span>
                )}
              </div>
            )}
          </div>

          <div
            ref={outputRef}
            className="flex-1 p-4 overflow-auto bg-gray-50 font-mono text-sm"
          >
            {currentRun ? (
              currentRun.status === 'running' ? (
                <div className="flex items-center space-x-2 text-gray-500">
                  <span className="animate-pulse">●</span>
                  <span>Generating response...</span>
                </div>
              ) : currentRun.error_message ? (
                <div className="text-red-600">
                  <div className="font-semibold mb-2">Error:</div>
                  <pre className="whitespace-pre-wrap">{currentRun.error_message}</pre>
                </div>
              ) : (
                <pre className="whitespace-pre-wrap text-gray-800">{currentRun.output || 'No output'}</pre>
              )
            ) : (
              <div className="text-gray-400 text-center py-12">
                Enter a prompt and click Run to test your agent
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Sidebar */}
      <div className="space-y-4">
        {/* Agent Info */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <div className="flex items-center space-x-3 mb-4">
            <AgentAvatar size={60} />
            <div>
              <h3 className="font-semibold text-gray-900">{agent.name}</h3>
              <p className="text-sm text-gray-500">{agent.provider} / {agent.model}</p>
            </div>
          </div>

          <button
            onClick={onBack}
            className="w-full px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50 transition-colors"
          >
            ← Back to Editor
          </button>
        </div>

        {/* Configuration Preview */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <h4 className="font-medium text-gray-900 mb-3">Configuration</h4>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between">
              <dt className="text-gray-500">Temperature</dt>
              <dd className="text-gray-900">{agent.modelConfig?.temperature || agent.model_config?.temperature || 0.7}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-gray-500">Tools</dt>
              <dd className="text-gray-900">{agent.tools?.length || 0}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-gray-500">Status</dt>
              <dd className={`px-2 py-0.5 rounded text-xs ${
                agent.status === 'active' ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
              }`}>
                {agent.status}
              </dd>
            </div>
          </dl>
        </div>

        {/* Recent Runs */}
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <div className="px-4 py-3 border-b border-gray-100">
            <h4 className="font-medium text-gray-900">Recent Runs</h4>
          </div>

          <div className="max-h-64 overflow-auto">
            {runs.length > 0 ? (
              <div className="divide-y divide-gray-100">
                {runs.map(run => (
                  <div
                    key={run.id}
                    className="px-4 py-3 hover:bg-gray-50 cursor-pointer"
                    onClick={() => setCurrentRun(run)}
                  >
                    <div className="flex items-center justify-between mb-1">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${getStatusColor(run.status)}`}>
                        {run.status}
                      </span>
                      <span className="text-xs text-gray-400">
                        {formatDuration(run.duration_ms)}
                      </span>
                    </div>
                    <p className="text-sm text-gray-600 truncate">
                      {run.input_preview || run.input_prompt?.substring(0, 50)}
                    </p>
                    <p className="text-xs text-gray-400 mt-1">
                      {new Date(run.created_at).toLocaleString()}
                    </p>
                  </div>
                ))}
              </div>
            ) : (
              <div className="px-4 py-8 text-center text-gray-400 text-sm">
                No runs yet
              </div>
            )}
          </div>
        </div>

        {/* Example Prompts */}
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <h4 className="font-medium text-gray-900 mb-3">Example Prompts</h4>
          <div className="space-y-2">
            {[
              "Hello, what can you help me with?",
              "List the files in the current directory",
              "Explain how this code works"
            ].map((example, i) => (
              <button
                key={i}
                onClick={() => setPrompt(example)}
                className="w-full text-left px-3 py-2 text-sm text-gray-600 hover:bg-gray-50 rounded-lg transition-colors border border-gray-200"
              >
                {example}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
