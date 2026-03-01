import React, { useState, useEffect } from 'react';
import { router } from '@inertiajs/react';

const StatusBadge = ({ status }) => {
  const colors = {
    pending: 'bg-gray-100 text-gray-700',
    provisioning: 'bg-blue-100 text-blue-700',
    ready: 'bg-green-100 text-green-700',
    running: 'bg-yellow-100 text-yellow-700',
    completed: 'bg-gray-100 text-gray-700',
    expired: 'bg-red-100 text-red-700',
    failed: 'bg-red-100 text-red-700',
  };

  return (
    <span className={`px-2 py-1 text-xs font-medium rounded-full ${colors[status] || 'bg-gray-100'}`}>
      {status}
    </span>
  );
};

const LogEntry = ({ log }) => {
  const severityColors = {
    ERROR: 'text-red-600',
    WARNING: 'text-yellow-600',
    INFO: 'text-blue-600',
    DEBUG: 'text-gray-400',
  };

  return (
    <div className="flex gap-2 text-sm font-mono py-1 border-b border-gray-100">
      <span className="text-gray-400 text-xs whitespace-nowrap">
        {log.timestamp ? new Date(log.timestamp).toLocaleTimeString() : '--'}
      </span>
      <span className={`font-medium ${severityColors[log.severity] || 'text-gray-600'}`}>
        [{log.severity}]
      </span>
      <span className="text-gray-700 break-all">{log.message}</span>
    </div>
  );
};

const RunEntry = ({ run }) => (
  <div className="border border-gray-200 rounded-lg p-4 mb-3">
    <div className="flex items-center justify-between mb-2">
      <div className="flex items-center gap-2">
        <StatusBadge status={run.status || 'completed'} />
        <span className="text-sm text-gray-500">
          {run.duration_ms ? `${(run.duration_ms / 1000).toFixed(1)}s` : '--'}
        </span>
        {run.tokens && (
          <span className="text-sm text-gray-500">{run.tokens} tokens</span>
        )}
      </div>
      <span className="text-xs text-gray-400">{run.created_at}</span>
    </div>
    <div className="text-sm font-medium text-gray-900 mb-2">{run.task}</div>
    {run.result && (
      <div className="text-sm text-gray-600 bg-gray-50 rounded p-2 overflow-auto max-h-40">
        <pre className="whitespace-pre-wrap">{run.result}</pre>
      </div>
    )}
    {run.screenshots && run.screenshots.length > 0 && (
      <div className="mt-2 flex gap-2">
        {run.screenshots.map((ss, i) => (
          <img
            key={i}
            src={ss.url || ss}
            alt={`Screenshot ${i + 1}`}
            className="w-24 h-16 object-cover rounded border"
          />
        ))}
      </div>
    )}
  </div>
);

export default function Show({ space, cloud_run, runs, logs: initialLogs }) {
  const [logs, setLogs] = useState(initialLogs || []);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [terminating, setTerminating] = useState(false);

  const isActive = ['pending', 'provisioning', 'ready', 'running'].includes(space.status);

  const refreshLogs = async () => {
    setLoadingLogs(true);
    try {
      const response = await fetch(`/admin/spaces/${space.id}/logs`);
      const data = await response.json();
      setLogs(data.logs || []);
    } catch (error) {
      console.error('Failed to fetch logs:', error);
    }
    setLoadingLogs(false);
  };

  const handleTerminate = () => {
    if (!confirm(`Terminate space ${space.session_id}? This will stop the container.`)) return;

    setTerminating(true);
    router.post(`/admin/spaces/${space.id}/terminate`, {}, {
      onFinish: () => setTerminating(false),
    });
  };

  // Auto-refresh logs for active spaces
  useEffect(() => {
    if (!isActive) return;

    const interval = setInterval(refreshLogs, 5000);
    return () => clearInterval(interval);
  }, [isActive, space.id]);

  return (
    <div className="min-h-screen bg-gray-50 p-6">
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <a
              href="/admin/spaces"
              className="text-sm text-gray-500 hover:text-gray-700 mb-1 block"
            >
              Back to Spaces
            </a>
            <h1 className="text-2xl font-bold text-gray-900">
              Space: {space.session_id.slice(0, 8)}...
            </h1>
          </div>
          {isActive && (
            <button
              onClick={handleTerminate}
              disabled={terminating}
              className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
            >
              {terminating ? 'Terminating...' : 'Terminate Space'}
            </button>
          )}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Space Info */}
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <h2 className="text-lg font-semibold mb-4">Space Details</h2>
            <dl className="space-y-3">
              <div className="flex justify-between">
                <dt className="text-gray-500">Session ID</dt>
                <dd className="font-mono text-sm">{space.session_id}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Status</dt>
                <dd><StatusBadge status={space.status} /></dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Type</dt>
                <dd>{space.sandbox_type}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">User</dt>
                <dd>{space.user ? space.user.email : 'Anonymous'}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Runs</dt>
                <dd>{space.runs_count} / {space.max_runs}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Tokens Used</dt>
                <dd>{(space.total_tokens || 0).toLocaleString()}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Created</dt>
                <dd className="text-sm">{new Date(space.created_at).toLocaleString()}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Expires</dt>
                <dd className="text-sm">{space.expires_at ? new Date(space.expires_at).toLocaleString() : '--'}</dd>
              </div>
              {space.cloud_run_url && (
                <div className="flex justify-between">
                  <dt className="text-gray-500">Cloud Run URL</dt>
                  <dd className="text-sm font-mono truncate max-w-xs">{space.cloud_run_url}</dd>
                </div>
              )}
            </dl>
          </div>

          {/* Cloud Run Info */}
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <h2 className="text-lg font-semibold mb-4">Cloud Run Container</h2>
            {cloud_run ? (
              cloud_run.error ? (
                <div className="text-red-600">{cloud_run.error}</div>
              ) : (
                <dl className="space-y-3">
                  <div className="flex justify-between">
                    <dt className="text-gray-500">Job ID</dt>
                    <dd className="font-mono text-sm">{cloud_run.job_id}</dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-gray-500">Status</dt>
                    <dd><StatusBadge status={cloud_run.status} /></dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-gray-500">Image</dt>
                    <dd className="font-mono text-xs truncate max-w-xs">{cloud_run.image}</dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-gray-500">Resources</dt>
                    <dd>{cloud_run.cpu} CPU / {cloud_run.memory}</dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-gray-500">Timeout</dt>
                    <dd>{cloud_run.timeout}</dd>
                  </div>
                  {cloud_run.execution && (
                    <>
                      <div className="flex justify-between">
                        <dt className="text-gray-500">Started</dt>
                        <dd className="text-sm">
                          {cloud_run.execution.started_at
                            ? new Date(cloud_run.execution.started_at).toLocaleString()
                            : '--'}
                        </dd>
                      </div>
                    </>
                  )}
                </dl>
              )
            ) : (
              <div className="text-gray-500">No Cloud Run job associated</div>
            )}
          </div>
        </div>

        {/* Runs */}
        <div className="bg-white rounded-lg border border-gray-200 p-6 mt-6">
          <h2 className="text-lg font-semibold mb-4">Run History ({runs?.length || 0})</h2>
          {runs && runs.length > 0 ? (
            runs.map((run, index) => <RunEntry key={run.id || index} run={run} />)
          ) : (
            <div className="text-gray-500 text-center py-8">No runs recorded</div>
          )}
        </div>

        {/* Logs */}
        <div className="bg-white rounded-lg border border-gray-200 p-6 mt-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold">Container Logs</h2>
            <button
              onClick={refreshLogs}
              disabled={loadingLogs}
              className="text-sm text-blue-600 hover:text-blue-800 disabled:opacity-50"
            >
              {loadingLogs ? 'Loading...' : 'Refresh'}
            </button>
          </div>
          <div className="bg-gray-900 rounded-lg p-4 max-h-96 overflow-y-auto">
            {logs.length > 0 ? (
              logs.map((log, index) => (
                <LogEntry key={index} log={log} />
              ))
            ) : (
              <div className="text-gray-500 text-center py-4">No logs available</div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
