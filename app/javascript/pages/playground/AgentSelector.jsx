const ICONS = {
  search: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z" />
    </svg>
  ),
  pencil: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
    </svg>
  ),
  document: (
    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
    </svg>
  )
}

const COLOR_MAP = {
  blue: { bg: "bg-blue-50", border: "border-blue-200", text: "text-blue-700", icon: "text-blue-500", activeBg: "bg-blue-100" },
  green: { bg: "bg-green-50", border: "border-green-200", text: "text-green-700", icon: "text-green-500", activeBg: "bg-green-100" },
  purple: { bg: "bg-purple-50", border: "border-purple-200", text: "text-purple-700", icon: "text-purple-500", activeBg: "bg-purple-100" }
}

export default function AgentSelector({ agents, selected, onSelect }) {
  return (
    <div className="w-64 flex-shrink-0 bg-gray-50 border-r border-gray-200 flex flex-col">
      <div className="p-4 border-b border-gray-200">
        <h2 className="text-xs font-semibold text-gray-500 uppercase tracking-wider">Agents</h2>
      </div>
      <div className="p-3 space-y-2 flex-1 overflow-y-auto">
        {Object.entries(agents).map(([key, agent]) => {
          const isSelected = selected === key
          const colors = COLOR_MAP[agent.color] || COLOR_MAP.blue

          return (
            <button
              key={key}
              onClick={() => onSelect(key)}
              className={`w-full text-left p-3 rounded-lg transition-all duration-150 ${
                isSelected
                  ? `${colors.activeBg} ${colors.border} border-2 shadow-sm`
                  : `bg-white border border-gray-200 hover:border-gray-300 hover:shadow-sm`
              }`}
            >
              <div className="flex items-center gap-2">
                <span className={isSelected ? colors.icon : "text-gray-400"}>
                  {ICONS[agent.icon] || ICONS.document}
                </span>
                <span className={`font-medium text-sm ${isSelected ? colors.text : "text-gray-900"}`}>
                  {agent.name}
                </span>
              </div>
              <p className="text-xs text-gray-500 mt-1.5 ml-7">{agent.description}</p>
            </button>
          )
        })}
      </div>

      <div className="p-3 border-t border-gray-200">
        <div className="text-xs text-gray-400 px-1">
          <p className="font-medium text-gray-500 mb-1">Workflow</p>
          <p>1. Research Agent gathers sources</p>
          <p>2. Writing Agent drafts content</p>
          <p>3. Report Builder compiles output</p>
        </div>
      </div>
    </div>
  )
}
