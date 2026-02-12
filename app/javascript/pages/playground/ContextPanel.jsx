import { useState } from "react"

function ContextSection({ title, data, color, icon }) {
  const [expanded, setExpanded] = useState(true)

  if (!data || (typeof data === "object" && Object.keys(data).length === 0)) {
    return (
      <div className="px-3 py-2">
        <div className="flex items-center gap-2 text-xs text-gray-400">
          <span>{icon}</span>
          <span>{title}</span>
          <span className="text-[10px]">— waiting</span>
        </div>
      </div>
    )
  }

  return (
    <div className="border-b border-gray-100 last:border-0">
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-2 px-3 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50"
      >
        <span>{icon}</span>
        <span className="flex-1 text-left">{title}</span>
        <svg className={`w-3 h-3 text-gray-400 transition-transform ${expanded ? "rotate-90" : ""}`} fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
        </svg>
      </button>
      {expanded && (
        <div className="px-3 pb-3">
          {typeof data === "string" ? (
            <div className="bg-gray-50 rounded-lg p-2.5 text-xs text-gray-600 whitespace-pre-wrap max-h-48 overflow-y-auto">
              {data}
            </div>
          ) : (
            <div className="space-y-1.5">
              {data.topic && (
                <div className="text-xs">
                  <span className="font-medium text-gray-500">Topic: </span>
                  <span className="text-gray-700">{data.topic}</span>
                </div>
              )}
              {data.sources && data.sources.length > 0 && (
                <div>
                  <div className="text-xs font-medium text-gray-500 mb-1">
                    Sources ({data.sources.length})
                  </div>
                  <div className="space-y-1">
                    {data.sources.map((source, i) => (
                      <div key={i} className="bg-gray-50 rounded p-2 text-[11px]">
                        <div className="font-medium text-gray-700">{source.title}</div>
                        <div className="text-gray-500">
                          {source.authors?.join(", ")} ({source.year})
                        </div>
                        <div className="text-gray-400">{source.journal}</div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
              {data.summary && (
                <div>
                  <div className="text-xs font-medium text-gray-500 mb-1">Summary</div>
                  <div className="bg-gray-50 rounded p-2 text-[11px] text-gray-600 max-h-32 overflow-y-auto">
                    {data.summary}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function ExecutionLogEntry({ entry }) {
  const typeColors = {
    request: "bg-blue-100 text-blue-700",
    response: "bg-green-100 text-green-700",
    error: "bg-red-100 text-red-700",
    context: "bg-purple-100 text-purple-700"
  }

  return (
    <div className="flex items-start gap-2 text-[11px]">
      <span className="text-gray-400 flex-shrink-0 font-mono">{entry.time}</span>
      <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium flex-shrink-0 ${typeColors[entry.type] || typeColors.request}`}>
        {entry.type}
      </span>
      <span className="text-gray-600 break-all">{entry.message}</span>
    </div>
  )
}

export default function ContextPanel({ sharedContext, executionLog, visible, onToggle }) {
  const [activeTab, setActiveTab] = useState("context")

  return (
    <div className={`flex-shrink-0 border-l border-gray-200 bg-white flex flex-col transition-all duration-200 ${visible ? "w-80" : "w-10"}`}>
      {/* Toggle button */}
      <div className="flex items-center border-b border-gray-200">
        <button
          onClick={onToggle}
          className="p-2.5 text-gray-400 hover:text-gray-600"
          title={visible ? "Hide panel" : "Show panel"}
        >
          <svg className={`w-4 h-4 transition-transform ${visible ? "" : "rotate-180"}`} fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15" />
          </svg>
        </button>
        {visible && (
          <div className="flex gap-1 flex-1 px-2">
            <button
              onClick={() => setActiveTab("context")}
              className={`px-2.5 py-1.5 text-xs rounded transition-colors ${
                activeTab === "context" ? "bg-gray-100 text-gray-800 font-medium" : "text-gray-500 hover:text-gray-700"
              }`}
            >
              Shared Context
            </button>
            <button
              onClick={() => setActiveTab("log")}
              className={`px-2.5 py-1.5 text-xs rounded transition-colors ${
                activeTab === "log" ? "bg-gray-100 text-gray-800 font-medium" : "text-gray-500 hover:text-gray-700"
              }`}
            >
              Log ({executionLog.length})
            </button>
          </div>
        )}
      </div>

      {visible && (
        <div className="flex-1 overflow-y-auto">
          {activeTab === "context" ? (
            <div>
              <ContextSection
                title="Research Findings"
                data={sharedContext.research}
                color="blue"
                icon="🔍"
              />
              <ContextSection
                title="Draft Content"
                data={sharedContext.draft}
                color="green"
                icon="✍️"
              />
              <ContextSection
                title="Final Report"
                data={sharedContext.report}
                color="purple"
                icon="📋"
              />
              {Object.keys(sharedContext).length === 0 && (
                <div className="p-6 text-center text-xs text-gray-400">
                  <p className="mb-2">No shared context yet</p>
                  <p>As agents work, their outputs will appear here. Start by asking the Research Agent to investigate a topic.</p>
                </div>
              )}
            </div>
          ) : (
            <div className="p-3 space-y-2">
              {executionLog.length === 0 ? (
                <div className="text-center text-xs text-gray-400 py-6">
                  No activity yet
                </div>
              ) : (
                executionLog.map((entry, i) => (
                  <ExecutionLogEntry key={i} entry={entry} />
                ))
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
