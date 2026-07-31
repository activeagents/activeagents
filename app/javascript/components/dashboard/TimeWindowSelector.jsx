import React from 'react';
import { useTimeWindow } from '../../contexts/TimeWindowContext';

// The dashboard-wide period control. Rendered by every view that shows
// time-bounded data so the selection reads the same and stays put as you
// navigate.
export default function TimeWindowSelector({ compact = false }) {
  const { windows, windowIndex, timeWindow, setWindow, zoomTo } = useTimeWindow();

  return (
    <div className="flex items-center bg-gray-100 rounded-lg p-1">
      <button
        onClick={() => zoomTo(windowIndex - 1)}
        disabled={windowIndex <= 0}
        title="Zoom in (shorter window)"
        aria-label="Zoom in"
        className="px-2 py-1 text-sm rounded-md text-gray-600 disabled:opacity-30 disabled:cursor-not-allowed hover:bg-white"
      >
        −
      </button>
      <select
        value={timeWindow.id}
        onChange={(e) => setWindow(e.target.value)}
        aria-label="Time window"
        className={`px-2 py-1 mx-1 text-sm bg-white rounded-md shadow text-gray-900 focus:ring-2 focus:ring-red-500 ${
          compact ? '' : 'min-w-[4.5rem]'
        }`}
      >
        {windows.map((option) => (
          <option key={option.id} value={option.id}>{option.label}</option>
        ))}
      </select>
      <button
        onClick={() => zoomTo(windowIndex + 1)}
        disabled={windowIndex >= windows.length - 1}
        title="Zoom out (longer window)"
        aria-label="Zoom out"
        className="px-2 py-1 text-sm rounded-md text-gray-600 disabled:opacity-30 disabled:cursor-not-allowed hover:bg-white"
      >
        +
      </button>
    </div>
  );
}
