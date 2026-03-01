import React, { useState } from 'react';
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

const SpaceRow = ({ space, onTerminate }) => {
  const [terminating, setTerminating] = useState(false);

  const handleTerminate = async () => {
    if (!confirm(`Terminate space ${space.session_id}?`)) return;

    setTerminating(true);
    router.post(`/admin/spaces/${space.id}/terminate`, {}, {
      onFinish: () => setTerminating(false),
    });
  };

  const isActive = ['pending', 'provisioning', 'ready', 'running'].includes(space.status);

  return (
    <tr className="border-b border-gray-200 hover:bg-gray-50">
      <td className="px-4 py-3">
        <div className="font-mono text-sm">{space.session_id.slice(0, 8)}...</div>
        <div className="text-xs text-gray-500">{space.sandbox_type}</div>
      </td>
      <td className="px-4 py-3">
        <StatusBadge status={space.status} />
        {space.cloud_run_status && (
          <span className="ml-2 text-xs text-gray-500">
            CR: {space.cloud_run_status.status}
          </span>
        )}
      </td>
      <td className="px-4 py-3">
        {space.user ? (
          <div>
            <div className="text-sm">{space.user.email}</div>
            <div className="text-xs text-gray-500">ID: {space.user.id}</div>
          </div>
        ) : (
          <span className="text-gray-400 text-sm">Anonymous</span>
        )}
      </td>
      <td className="px-4 py-3 text-center">
        <span className="font-medium">{space.runs_count}</span>
        <span className="text-gray-400">/{space.max_runs}</span>
      </td>
      <td className="px-4 py-3 text-sm text-gray-600">
        {space.total_tokens.toLocaleString()}
      </td>
      <td className="px-4 py-3 text-sm text-gray-600">
        {new Date(space.created_at).toLocaleString()}
      </td>
      <td className="px-4 py-3">
        <div className="flex gap-2">
          <a
            href={`/admin/spaces/${space.id}`}
            className="text-blue-600 hover:text-blue-800 text-sm"
          >
            View
          </a>
          {isActive && (
            <button
              onClick={handleTerminate}
              disabled={terminating}
              className="text-red-600 hover:text-red-800 text-sm disabled:opacity-50"
            >
              {terminating ? 'Terminating...' : 'Terminate'}
            </button>
          )}
        </div>
      </td>
    </tr>
  );
};

const StatsCard = ({ label, value, color = 'blue' }) => (
  <div className="bg-white rounded-lg border border-gray-200 p-4">
    <div className="text-sm text-gray-500">{label}</div>
    <div className={`text-2xl font-bold text-${color}-600`}>{value}</div>
  </div>
);

const Pagination = ({ pagination, onPageChange }) => {
  if (pagination.total_pages <= 1) return null;

  return (
    <div className="flex items-center justify-between mt-4">
      <div className="text-sm text-gray-600">
        Page {pagination.current_page} of {pagination.total_pages} ({pagination.total_count} total)
      </div>
      <div className="flex gap-2">
        <button
          onClick={() => onPageChange(pagination.current_page - 1)}
          disabled={pagination.current_page === 1}
          className="px-3 py-1 border rounded disabled:opacity-50"
        >
          Previous
        </button>
        <button
          onClick={() => onPageChange(pagination.current_page + 1)}
          disabled={pagination.current_page === pagination.total_pages}
          className="px-3 py-1 border rounded disabled:opacity-50"
        >
          Next
        </button>
      </div>
    </div>
  );
};

export default function Index({ spaces, pagination, stats }) {
  const handlePageChange = (page) => {
    router.get('/admin/spaces', { page }, { preserveState: true });
  };

  return (
    <div className="min-h-screen bg-gray-50 p-6">
      <div className="max-w-7xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold text-gray-900">Sandbox Spaces</h1>
          <a href="/dashboard" className="text-gray-600 hover:text-gray-900">
            Back to Dashboard
          </a>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <StatsCard label="Total Spaces" value={stats.total} />
          <StatsCard label="Active" value={stats.active} color="green" />
          <StatsCard label="Expired" value={stats.expired} color="gray" />
          <StatsCard label="Runs Today" value={stats.runs_today} color="purple" />
        </div>

        {/* Type breakdown */}
        <div className="bg-white rounded-lg border border-gray-200 p-4 mb-6">
          <h3 className="text-sm font-medium text-gray-700 mb-2">Spaces by Type</h3>
          <div className="flex gap-4">
            {Object.entries(stats.by_type).map(([type, count]) => (
              <div key={type} className="text-sm">
                <span className="font-medium">{type}:</span> {count}
              </div>
            ))}
          </div>
        </div>

        {/* Spaces table */}
        <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Session
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Status
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  User
                </th>
                <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                  Runs
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Tokens
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Created
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody>
              {spaces.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-8 text-center text-gray-500">
                    No sandbox spaces found
                  </td>
                </tr>
              ) : (
                spaces.map((space) => (
                  <SpaceRow key={space.id} space={space} />
                ))
              )}
            </tbody>
          </table>

          <Pagination pagination={pagination} onPageChange={handlePageChange} />
        </div>
      </div>
    </div>
  );
}
