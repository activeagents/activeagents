import { useState } from "react"

export default function CodeViewer({ agent, visible, onToggle }) {
  const [activeTab, setActiveTab] = useState("agent")

  if (!agent) return null

  const tabs = [
    { key: "agent", label: agent.source_file.split("/").pop(), content: agent.source_code },
    ...agent.template_sources.map((t) => ({
      key: t.path,
      label: t.path.split("/").pop(),
      content: t.content
    }))
  ]

  const activeContent = tabs.find((t) => t.key === activeTab)?.content || ""

  return (
    <div className="border-b border-gray-200">
      <div className="flex items-center justify-between bg-gray-800 px-3 py-1.5">
        <div className="flex items-center gap-1">
          <button
            onClick={onToggle}
            className="text-gray-400 hover:text-white p-1 mr-2"
            title={visible ? "Collapse code" : "Expand code"}
          >
            <svg className={`w-4 h-4 transition-transform ${visible ? "rotate-90" : ""}`} fill="none" viewBox="0 0 24 24" strokeWidth={2} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
            </svg>
          </button>
          {visible && tabs.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={`px-3 py-1 text-xs rounded transition-colors ${
                activeTab === tab.key
                  ? "text-white bg-gray-700"
                  : "text-gray-400 hover:text-gray-300"
              }`}
            >
              {tab.label}
            </button>
          ))}
          {!visible && (
            <span className="text-xs text-gray-400">Source Code</span>
          )}
        </div>
      </div>
      {visible && (
        <div className="bg-gray-900 max-h-64 overflow-auto">
          <pre className="p-4 text-xs text-gray-300 font-mono leading-relaxed">
            <code>{activeContent}</code>
          </pre>
        </div>
      )}
    </div>
  )
}
