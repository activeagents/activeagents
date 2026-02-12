import { useState } from "react"

const PROVIDERS = [
  { value: "openai", label: "OpenAI", models: ["gpt-4o-mini", "gpt-4o", "gpt-4-turbo"] },
  { value: "anthropic", label: "Anthropic", models: ["claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001"] },
  { value: "ollama", label: "Ollama (Local)", models: ["llama3.2", "mistral", "codellama"] },
  { value: "open_router", label: "OpenRouter", models: ["anthropic/claude-3.5-sonnet", "openai/gpt-4o"] }
]

export default function SettingsPanel({ visible, onClose, settings, onSave }) {
  const [apiKey, setApiKey] = useState(settings.api_key || "")
  const [provider, setProvider] = useState(settings.provider || "openai")
  const [model, setModel] = useState(settings.model || "")

  const selectedProvider = PROVIDERS.find((p) => p.value === provider)

  const handleSave = async () => {
    await onSave({ api_key: apiKey, provider, model: model || selectedProvider?.models[0] || "" })
    onClose()
  }

  const handleClear = async () => {
    setApiKey("")
    setProvider("openai")
    setModel("")
    await onSave({ api_key: "", provider: "", model: "" })
    onClose()
  }

  if (!visible) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/30" onClick={onClose} />

      {/* Modal */}
      <div className="relative bg-white rounded-2xl shadow-xl w-full max-w-md mx-4 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900">Provider Settings</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="px-6 py-4 space-y-4">
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-3 text-xs text-blue-700">
            <strong>Optional:</strong> Without an API key, the playground uses the Mock provider (responses in pig latin).
            Add your own key to connect to a real LLM provider.
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Provider</label>
            <select
              value={provider}
              onChange={(e) => {
                setProvider(e.target.value)
                setModel("")
              }}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              {PROVIDERS.map((p) => (
                <option key={p.value} value={p.value}>{p.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">API Key</label>
            <input
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder={provider === "ollama" ? "Not required for Ollama" : "sk-..."}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Model</label>
            <select
              value={model}
              onChange={(e) => setModel(e.target.value)}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <option value="">Default</option>
              {selectedProvider?.models.map((m) => (
                <option key={m} value={m}>{m}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-between">
          <button
            onClick={handleClear}
            className="text-sm text-gray-500 hover:text-gray-700"
          >
            Reset to Mock
          </button>
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-lg"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              className="px-4 py-2 text-sm text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg font-medium"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
