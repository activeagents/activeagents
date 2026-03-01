import React, { useState, useEffect, useRef } from 'react';
import AgentAvatar from '../AgentAvatar';

const SAMPLE_TASKS = {
  playwright_mcp: [
    {
      name: "Screenshot Example.com",
      task: "Take a screenshot of https://example.com",
      description: "Navigate to example.com and capture a screenshot"
    },
    {
      name: "Extract Hacker News Headlines",
      task: "Go to https://news.ycombinator.com and list the top 5 story titles with their scores",
      description: "Scrape the front page of Hacker News"
    },
    {
      name: "Check Wikipedia",
      task: "Navigate to https://en.wikipedia.org/wiki/Artificial_intelligence and extract the first paragraph",
      description: "Extract content from Wikipedia"
    },
    {
      name: "GitHub Trending",
      task: "Visit https://github.com/trending and list the top 3 trending repositories",
      description: "Check GitHub's trending repositories"
    }
  ]
};

const FREE_TIER_LIMITS = {
  max_runs: 10,
  timeout_seconds: 300,
  session_duration_minutes: 15
};

export default function SandboxRunner({ initialType = 'playwright_mcp', onClose }) {
  const [sandboxType, setSandboxType] = useState(initialType);
  const [session, setSession] = useState(null);
  const [task, setTask] = useState('');
  const [runs, setRuns] = useState([]);
  const [currentRun, setCurrentRun] = useState(null);
  const [isRunning, setIsRunning] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [error, setError] = useState(null);
  const [timeRemaining, setTimeRemaining] = useState(null);
  const outputRef = useRef(null);

  // Create session on mount
  useEffect(() => {
    createSession();
  }, [sandboxType]);

  // Countdown timer
  useEffect(() => {
    if (!session?.expires_at) return;

    const interval = setInterval(() => {
      const now = new Date();
      const expires = new Date(session.expires_at);
      const remaining = Math.max(0, Math.floor((expires - now) / 1000));
      setTimeRemaining(remaining);

      if (remaining === 0) {
        setSession(prev => ({ ...prev, status: 'expired' }));
        clearInterval(interval);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [session?.expires_at]);

  // Auto-scroll output
  useEffect(() => {
    if (outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight;
    }
  }, [currentRun?.result]);

  const createSession = async () => {
    setIsCreating(true);
    setError(null);

    try {
      const response = await fetch('/api/sandboxes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sandbox_type: sandboxType })
      });

      if (!response.ok) {
        throw new Error('Failed to create sandbox session');
      }

      const data = await response.json();
      setSession(data.sandbox);
      setRuns([]);
      setCurrentRun(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setIsCreating(false);
    }
  };

  const handleRun = async () => {
    if (!task.trim() || isRunning || !session) return;

    setIsRunning(true);
    setCurrentRun({
      status: 'running',
      task: task,
      result: '',
      started_at: new Date().toISOString()
    });

    try {
      const response = await fetch(`/api/sandboxes/${session.session_id}/run`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task: task })
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Task execution failed');
      }

      const data = await response.json();

      // Poll for completion
      pollRunStatus(data.run_id);
    } catch (err) {
      setCurrentRun(prev => ({
        ...prev,
        status: 'failed',
        error: err.message
      }));
      setIsRunning(false);
    }
  };

  const pollRunStatus = async (runId) => {
    const checkStatus = async () => {
      try {
        const response = await fetch(`/api/sandboxes/${session.session_id}`);
        const data = await response.json();

        setSession(data.sandbox);

        // Find the latest run
        const runs = data.sandbox.runs || [];
        const latestRun = runs[runs.length - 1];

        if (latestRun) {
          setCurrentRun(latestRun);
          setRuns(runs);

          if (latestRun.status === 'completed' || latestRun.status === 'failed') {
            setIsRunning(false);
            return;
          }
        }

        // Continue polling
        setTimeout(checkStatus, 1000);
      } catch (err) {
        setIsRunning(false);
      }
    };

    checkStatus();
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      handleRun();
    }
  };

  const formatTime = (seconds) => {
    if (!seconds) return '--:--';
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'completed': return 'text-green-600 bg-green-100';
      case 'failed': return 'text-red-600 bg-red-100';
      case 'running': return 'text-blue-600 bg-blue-100';
      case 'ready': return 'text-emerald-600 bg-emerald-100';
      case 'expired': return 'text-orange-600 bg-orange-100';
      default: return 'text-gray-600 bg-gray-100';
    }
  };

  const canRun = session?.status === 'ready' &&
                 session?.runs_count < session?.max_runs &&
                 !isRunning;

  return (
    <div className="h-full flex flex-col bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-6 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <AgentAvatar
              size={48}
              appearance={{ hat: 'fedora', hatAccessory: 'theaterMasks', heldItem: 'browser' }}
            />
            <div>
              <h1 className="text-xl font-semibold text-gray-900">
                PlaywrightMCP Demo
              </h1>
              <p className="text-sm text-gray-500">
                Try browser automation for free - no account required
              </p>
            </div>
          </div>

          <div className="flex items-center space-x-4">
            {/* Session Status */}
            {session && (
              <div className="flex items-center space-x-3 text-sm">
                <span className={`px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(session.status)}`}>
                  {session.status}
                </span>
                <span className="text-gray-500">
                  {session.runs_count}/{session.max_runs} runs
                </span>
                <span className={`font-mono ${timeRemaining < 60 ? 'text-red-500' : 'text-gray-500'}`}>
                  {formatTime(timeRemaining)}
                </span>
              </div>
            )}

            {onClose && (
              <button
                onClick={onClose}
                className="text-gray-400 hover:text-gray-600"
              >
                <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="flex-1 p-6 overflow-hidden">
        <div className="grid grid-cols-3 gap-6 h-full">
          {/* Main Runner */}
          <div className="col-span-2 flex flex-col space-y-4">
            {/* Input */}
            <div className="bg-white rounded-xl border border-gray-200 p-4">
              <textarea
                value={task}
                onChange={(e) => setTask(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Describe what you want the browser agent to do..."
                rows={3}
                disabled={!canRun}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-rose-500 focus:border-transparent resize-none disabled:bg-gray-100"
              />
              <div className="flex items-center justify-between mt-3">
                <span className="text-xs text-gray-400">
                  Press <kbd className="px-1.5 py-0.5 bg-gray-100 rounded text-gray-600">Cmd</kbd> + <kbd className="px-1.5 py-0.5 bg-gray-100 rounded text-gray-600">Enter</kbd> to run
                </span>
                <button
                  onClick={handleRun}
                  disabled={!task.trim() || !canRun}
                  className={`flex items-center space-x-2 px-6 py-2 rounded-lg transition-colors ${
                    task.trim() && canRun
                      ? 'bg-rose-500 text-white hover:bg-rose-600'
                      : 'bg-gray-200 text-gray-400 cursor-not-allowed'
                  }`}
                >
                  {isRunning ? (
                    <>
                      <span className="animate-spin">&#9696;</span>
                      <span>Running...</span>
                    </>
                  ) : (
                    <>
                      <span>&#9654;</span>
                      <span>Run</span>
                    </>
                  )}
                </button>
              </div>
            </div>

            {/* Output */}
            <div className="flex-1 bg-white rounded-xl border border-gray-200 flex flex-col overflow-hidden">
              <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
                <h3 className="font-medium text-gray-900">Output</h3>
                {currentRun && (
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${getStatusColor(currentRun.status)}`}>
                    {currentRun.status}
                  </span>
                )}
              </div>

              <div
                ref={outputRef}
                className="flex-1 p-4 overflow-auto bg-gray-50 font-mono text-sm"
              >
                {isCreating ? (
                  <div className="flex items-center justify-center h-full text-gray-500">
                    <span className="animate-pulse">Starting sandbox...</span>
                  </div>
                ) : error ? (
                  <div className="text-red-600">{error}</div>
                ) : currentRun ? (
                  currentRun.status === 'running' ? (
                    <div className="flex items-center space-x-2 text-gray-500">
                      <span className="animate-pulse">&#9679;</span>
                      <span>Executing browser automation...</span>
                    </div>
                  ) : currentRun.error ? (
                    <div className="text-red-600">
                      <div className="font-semibold mb-2">Error:</div>
                      <pre className="whitespace-pre-wrap">{currentRun.error}</pre>
                    </div>
                  ) : (
                    <pre className="whitespace-pre-wrap text-gray-800">
                      {currentRun.result || 'Processing...'}
                    </pre>
                  )
                ) : (
                  <div className="text-gray-400 text-center py-12">
                    <p className="mb-2">Select a sample task or enter your own</p>
                    <p className="text-xs">Browser automation will execute in an isolated container</p>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Sidebar */}
          <div className="space-y-4 overflow-auto">
            {/* Sample Tasks */}
            <div className="bg-white rounded-xl border border-gray-200 p-4">
              <h4 className="font-medium text-gray-900 mb-3">Sample Tasks</h4>
              <div className="space-y-2">
                {SAMPLE_TASKS[sandboxType]?.map((sample, i) => (
                  <button
                    key={i}
                    onClick={() => setTask(sample.task)}
                    disabled={!canRun}
                    className="w-full text-left px-3 py-2 rounded-lg transition-colors border border-gray-200 hover:bg-gray-50 disabled:opacity-50"
                  >
                    <div className="font-medium text-sm text-gray-900">{sample.name}</div>
                    <div className="text-xs text-gray-500 mt-0.5">{sample.description}</div>
                  </button>
                ))}
              </div>
            </div>

            {/* Free Tier Info */}
            <div className="bg-gradient-to-br from-rose-50 to-purple-50 rounded-xl border border-rose-200 p-4">
              <h4 className="font-medium text-gray-900 mb-3">Free Tier Limits</h4>
              <dl className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Max Runs</dt>
                  <dd className="text-gray-900">{FREE_TIER_LIMITS.max_runs}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Timeout</dt>
                  <dd className="text-gray-900">{FREE_TIER_LIMITS.timeout_seconds}s per task</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Session</dt>
                  <dd className="text-gray-900">{FREE_TIER_LIMITS.session_duration_minutes} min</dd>
                </div>
              </dl>
              <div className="mt-4 pt-4 border-t border-rose-200">
                <a
                  href="/pricing"
                  className="block text-center text-sm text-rose-600 hover:text-rose-700 font-medium"
                >
                  Upgrade for unlimited access &#8594;
                </a>
              </div>
            </div>

            {/* Run History */}
            {runs.length > 0 && (
              <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className="px-4 py-3 border-b border-gray-100">
                  <h4 className="font-medium text-gray-900">Run History</h4>
                </div>
                <div className="max-h-48 overflow-auto divide-y divide-gray-100">
                  {runs.slice().reverse().map((run, i) => (
                    <div
                      key={run.id || i}
                      className="px-4 py-3 hover:bg-gray-50 cursor-pointer"
                      onClick={() => setCurrentRun(run)}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${getStatusColor(run.status || 'completed')}`}>
                          {run.status || 'completed'}
                        </span>
                        <span className="text-xs text-gray-400">
                          {run.tokens || 0} tokens
                        </span>
                      </div>
                      <p className="text-sm text-gray-600 truncate">
                        {run.task}
                      </p>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* New Session */}
            {session?.status === 'expired' && (
              <button
                onClick={createSession}
                className="w-full px-4 py-3 bg-rose-500 text-white rounded-lg hover:bg-rose-600 transition-colors"
              >
                Start New Session
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
