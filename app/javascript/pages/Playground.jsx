import { useState, useCallback } from "react"
import AgentSelector from "./playground/AgentSelector"
import CodeViewer from "./playground/CodeViewer"
import ChatInterface from "./playground/ChatInterface"
import ContextPanel from "./playground/ContextPanel"
import SettingsPanel from "./playground/SettingsPanel"

function getCsrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]')
  return meta ? meta.getAttribute("content") : ""
}

export default function Playground({ agents, default_agent, messages: initialMessages, shared_context: initialContext }) {
  const [selectedAgent, setSelectedAgent] = useState(default_agent)
  const [messages, setMessages] = useState(initialMessages || [])
  const [sharedContext, setSharedContext] = useState(initialContext || {})
  const [executionLog, setExecutionLog] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [showCode, setShowCode] = useState(true)
  const [showContext, setShowContext] = useState(true)
  const [showSettings, setShowSettings] = useState(false)
  const [settings, setSettings] = useState({})

  const addLog = useCallback((type, message) => {
    const time = new Date().toLocaleTimeString("en-US", { hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit" })
    setExecutionLog((prev) => [...prev, { type, message, time }])
  }, [])

  const handleSendMessage = useCallback(async (text) => {
    // Optimistically add user message
    const userMsg = {
      id: `temp-${Date.now()}`,
      role: "user",
      content: text,
      agent_name: selectedAgent,
      position: messages.length,
      metadata: {},
      created_at: new Date().toISOString()
    }
    setMessages((prev) => [...prev, userMsg])
    setIsLoading(true)
    addLog("request", `→ ${agents[selectedAgent]?.name}: "${text.substring(0, 60)}${text.length > 60 ? "..." : ""}"`)

    try {
      const response = await fetch("/playground/execute", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify({ agent: selectedAgent, message: text })
      })

      const data = await response.json()

      if (data.error) {
        addLog("error", data.error)
        if (data.message) {
          setMessages((prev) => [...prev, data.message])
        }
      } else {
        setMessages((prev) => [...prev, data.message])
        addLog("response", `← ${agents[selectedAgent]?.name}: ${(data.message?.content || "").substring(0, 80)}...`)

        if (data.shared_context) {
          const oldKeys = Object.keys(sharedContext)
          const newKeys = Object.keys(data.shared_context)
          const addedKeys = newKeys.filter((k) => !oldKeys.includes(k) || JSON.stringify(sharedContext[k]) !== JSON.stringify(data.shared_context[k]))
          if (addedKeys.length > 0) {
            addLog("context", `Updated: ${addedKeys.join(", ")}`)
          }
          setSharedContext(data.shared_context)
        }
      }
    } catch (err) {
      addLog("error", `Network error: ${err.message}`)
    } finally {
      setIsLoading(false)
    }
  }, [selectedAgent, messages, agents, sharedContext, addLog])

  const handleAgentChange = useCallback((key) => {
    setSelectedAgent(key)
    addLog("request", `Switched to ${agents[key]?.name}`)
  }, [agents, addLog])

  const handleReset = useCallback(async () => {
    try {
      await fetch("/playground/reset", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        }
      })
      setMessages([])
      setSharedContext({})
      setExecutionLog([])
      addLog("request", "Session reset")
    } catch (err) {
      addLog("error", `Reset failed: ${err.message}`)
    }
  }, [addLog])

  const handleSaveSettings = useCallback(async (newSettings) => {
    try {
      await fetch("/playground/settings", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCsrfToken()
        },
        body: JSON.stringify(newSettings)
      })
      setSettings(newSettings)
      addLog("request", newSettings.api_key ? `Provider set to ${newSettings.provider}` : "Reset to Mock provider")
    } catch (err) {
      addLog("error", `Settings save failed: ${err.message}`)
    }
  }, [addLog])

  const currentAgent = agents[selectedAgent]

  return (
    <div className="flex h-screen bg-white">
      {/* Left Sidebar — Agent Selector */}
      <AgentSelector agents={agents} selected={selectedAgent} onSelect={handleAgentChange} />

      {/* Center — Code Viewer + Chat */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top Nav */}
        <nav className="h-12 border-b border-gray-200 flex items-center justify-between px-4 bg-white flex-shrink-0">
          <div className="flex items-center gap-3">
            <span className="text-sm font-semibold text-indigo-600">Active Agent</span>
            <span className="text-gray-300">|</span>
            <span className="text-sm text-gray-600">Playground</span>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={handleReset}
              className="text-xs text-gray-500 hover:text-gray-700 px-2.5 py-1.5 rounded-lg hover:bg-gray-100 transition-colors"
              title="Reset session"
            >
              Reset
            </button>
            <button
              onClick={() => setShowSettings(true)}
              className="text-gray-400 hover:text-gray-600 p-1.5 rounded-lg hover:bg-gray-100 transition-colors"
              title="Settings"
            >
              <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
              </svg>
            </button>
          </div>
        </nav>

        {/* Code Viewer */}
        <CodeViewer agent={currentAgent} visible={showCode} onToggle={() => setShowCode(!showCode)} />

        {/* Chat Interface */}
        <ChatInterface
          messages={messages}
          agents={agents}
          selectedAgent={selectedAgent}
          isLoading={isLoading}
          hasApiKey={!!settings.api_key}
          onSend={handleSendMessage}
        />
      </div>

      {/* Right Panel — Context + Log */}
      <ContextPanel
        sharedContext={sharedContext}
        executionLog={executionLog}
        visible={showContext}
        onToggle={() => setShowContext(!showContext)}
      />

      {/* Settings Modal */}
      <SettingsPanel
        visible={showSettings}
        onClose={() => setShowSettings(false)}
        settings={settings}
        onSave={handleSaveSettings}
      />
    </div>
  )
}
