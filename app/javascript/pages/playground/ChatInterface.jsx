import { useState, useRef, useEffect } from "react"

const AGENT_COLORS = {
  research: { badge: "bg-blue-100 text-blue-700", dot: "bg-blue-400" },
  writing: { badge: "bg-green-100 text-green-700", dot: "bg-green-400" },
  report_builder: { badge: "bg-purple-100 text-purple-700", dot: "bg-purple-400" }
}

function MessageBubble({ message, agents }) {
  const isUser = message.role === "user"
  const isSystem = message.role === "system"
  const isError = message.metadata?.error
  const agentInfo = message.agent_name ? agents[message.agent_name] : null
  const colors = AGENT_COLORS[message.agent_name] || { badge: "bg-gray-100 text-gray-700", dot: "bg-gray-400" }

  if (isSystem) {
    return (
      <div className={`mx-auto max-w-lg text-center py-2 px-4 rounded-lg text-xs ${
        isError ? "bg-red-50 text-red-600" : "bg-gray-50 text-gray-500"
      }`}>
        {message.content}
      </div>
    )
  }

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div className={`max-w-[80%] ${isUser ? "order-1" : ""}`}>
        {!isUser && agentInfo && (
          <div className="flex items-center gap-1.5 mb-1 ml-1">
            <span className={`w-2 h-2 rounded-full ${colors.dot}`} />
            <span className={`text-xs font-medium px-1.5 py-0.5 rounded ${colors.badge}`}>
              {agentInfo.name}
            </span>
          </div>
        )}
        <div className={`rounded-2xl px-4 py-2.5 text-sm ${
          isUser
            ? "bg-indigo-600 text-white"
            : "bg-white border border-gray-200 text-gray-800"
        }`}>
          <div className="whitespace-pre-wrap break-words">{message.content}</div>
        </div>
        {message.metadata?.usage && (
          <div className="text-[10px] text-gray-400 mt-1 ml-2">
            {message.metadata.model && `${message.metadata.model}`}
            {message.metadata.usage.input_tokens && ` | ${message.metadata.usage.input_tokens + (message.metadata.usage.output_tokens || 0)} tokens`}
          </div>
        )}
      </div>
    </div>
  )
}

export default function ChatInterface({ messages, agents, selectedAgent, isLoading, hasApiKey, onSend }) {
  const [input, setInput] = useState("")
  const messagesEndRef = useRef(null)
  const inputRef = useRef(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages])

  useEffect(() => {
    inputRef.current?.focus()
  }, [selectedAgent])

  const handleSubmit = (e) => {
    e.preventDefault()
    const text = input.trim()
    if (!text || isLoading) return
    onSend(text)
    setInput("")
  }

  const handleKeyDown = (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      handleSubmit(e)
    }
  }

  const agentInfo = agents[selectedAgent]

  return (
    <div className="flex-1 flex flex-col min-h-0">
      {/* Mock provider banner */}
      {!hasApiKey && (
        <div className="bg-amber-50 border-b border-amber-200 px-4 py-2 text-xs text-amber-700 flex items-center gap-2">
          <svg className="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
          </svg>
          <span>
            <strong>Mock Mode</strong> — Responses are simulated (pig latin). Configure an API key in Settings to use real LLM providers.
          </span>
        </div>
      )}

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 && (
          <div className="flex-1 flex items-center justify-center h-full">
            <div className="text-center text-gray-400 max-w-md">
              <div className="text-4xl mb-4">
                {selectedAgent === "research" ? "🔍" : selectedAgent === "writing" ? "✍️" : "📋"}
              </div>
              <p className="text-lg font-medium text-gray-500 mb-2">
                {agentInfo?.name || "Agent"} Ready
              </p>
              <p className="text-sm">
                {selectedAgent === "research" && "Ask me to research any topic. I'll gather sources and citations for the team."}
                {selectedAgent === "writing" && "I can draft content based on research findings. Try researching a topic first!"}
                {selectedAgent === "report_builder" && "I'll compile research and drafts into a formatted report with citations."}
              </p>
            </div>
          </div>
        )}
        {messages.map((msg, i) => (
          <MessageBubble key={msg.id || i} message={msg} agents={agents} />
        ))}
        {isLoading && (
          <div className="flex justify-start">
            <div className="bg-white border border-gray-200 rounded-2xl px-4 py-3">
              <div className="flex items-center gap-1.5">
                <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
                <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
                <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
              </div>
            </div>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div className="border-t border-gray-200 p-4 bg-white">
        <form onSubmit={handleSubmit} className="flex items-end gap-2">
          <div className="flex-1 relative">
            <textarea
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={`Message ${agentInfo?.name || "agent"}...`}
              rows={1}
              className="w-full resize-none rounded-xl border border-gray-300 px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
              style={{ minHeight: "42px", maxHeight: "120px" }}
              disabled={isLoading}
            />
          </div>
          <button
            type="submit"
            disabled={isLoading || !input.trim()}
            className="flex-shrink-0 bg-indigo-600 text-white rounded-xl px-4 py-2.5 text-sm font-medium hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Send
          </button>
        </form>
        <p className="text-[10px] text-gray-400 mt-1.5 ml-1">
          Enter to send, Shift+Enter for new line
        </p>
      </div>
    </div>
  )
}
