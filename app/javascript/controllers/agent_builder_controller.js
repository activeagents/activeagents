import { Controller } from "@hotwired/stimulus"

// Agent Builder Controller
// Interactive agent preview for the hero section
export default class extends Controller {
  static targets = ["mcps", "tools", "speechLeft", "speechRight", "configMcps", "configTools"]

  // MCPs - capabilities that extend the agent
  static mcps = {
    playwright: { emoji: '🎭', label: 'Playwright' },
    filesystem: { emoji: '📁', label: 'Filesystem' },
    github: { emoji: '🐙', label: 'GitHub' },
    database: { emoji: '🗄️', label: 'Database' },
    slack: { emoji: '💬', label: 'Slack' },
    memory: { emoji: '🧠', label: 'Memory' },
    fetch: { emoji: '🌐', label: 'Fetch' },
    huggingface: { emoji: '🤗', label: 'Hugging Face' },
  }

  // Tools - actions the agent can perform
  static tools = {
    terminal: { emoji: '💻', label: 'Terminal' },
    browser: { emoji: '🌐', label: 'Browser' },
    document: { emoji: '📄', label: 'Read' },
    edit: { emoji: '✏️', label: 'Edit' },
    search: { emoji: '🔍', label: 'Search' },
    code: { emoji: '👨‍💻', label: 'Code' },
    translate: { emoji: '🌍', label: 'Translate' },
    vision: { emoji: '👁️', label: 'Vision' },
    voice: { emoji: '🗣️', label: 'Voice' },
  }

  // Presets - example agent configurations
  static presets = {
    'claude-code': { mcps: ['filesystem', 'github'], tools: ['terminal', 'edit', 'search'] },
    'web-scraper': { mcps: ['playwright', 'fetch'], tools: ['browser', 'document'] },
    'data-analyst': { mcps: ['database', 'filesystem'], tools: ['search', 'code'] },
    'devops': { mcps: ['github', 'slack'], tools: ['terminal', 'code'] },
    'polyglot': { mcps: ['memory'], tools: ['translate', 'document'] },
    'research': { mcps: ['fetch', 'memory'], tools: ['browser', 'search', 'document'] },
  }

  connect() {
    // Default to Claude Code preset
    this.currentPreset = 'claude-code'
    this.renderPreset('claude-code')
  }

  selectPreset(event) {
    const preset = event.currentTarget.dataset.preset

    // Update active button state
    this.element.querySelectorAll('.preset-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.preset === preset)
    })

    this.currentPreset = preset
    this.renderPreset(preset)
  }

  renderPreset(presetName) {
    const preset = this.constructor.presets[presetName]
    if (!preset) return

    this.renderMcps(preset.mcps)
    this.renderTools(preset.tools)
    this.updateConfig(preset.mcps, preset.tools)
    this.handleTranslation(preset.tools)
  }

  renderMcps(mcpIds) {
    if (!this.hasMcpsTarget) return

    const html = mcpIds.map((id, i) => {
      const mcp = this.constructor.mcps[id]
      if (!mcp) return ''
      return `<span class="mcp-item" style="animation-delay: ${i * 0.5}s" title="${mcp.label}">${mcp.emoji}</span>`
    }).join('')

    this.mcpsTarget.innerHTML = html
  }

  renderTools(toolIds) {
    if (!this.hasToolsTarget) return

    // Filter out translate for display (shown as speech bubbles instead)
    const displayTools = toolIds.filter(id => id !== 'translate')

    const html = displayTools.map(id => {
      const tool = this.constructor.tools[id]
      if (!tool) return ''
      return `<span class="tool-item" title="${tool.label}">${tool.emoji}</span>`
    }).join('')

    this.toolsTarget.innerHTML = html
  }

  updateConfig(mcpIds, toolIds) {
    if (this.hasConfigMcpsTarget) {
      const mcpLabels = mcpIds.map(id => {
        const mcp = this.constructor.mcps[id]
        return mcp ? `${mcp.emoji} ${mcp.label}` : ''
      }).filter(Boolean).join(', ')
      this.configMcpsTarget.textContent = mcpLabels || 'None'
    }

    if (this.hasConfigToolsTarget) {
      const toolLabels = toolIds.map(id => {
        const tool = this.constructor.tools[id]
        return tool ? `${tool.emoji} ${tool.label}` : ''
      }).filter(Boolean).join(', ')
      this.configToolsTarget.textContent = toolLabels || 'None'
    }
  }

  handleTranslation(toolIds) {
    const hasTranslate = toolIds.includes('translate')

    if (this.hasSpeechLeftTarget) {
      this.speechLeftTarget.style.display = hasTranslate ? 'block' : 'none'
    }
    if (this.hasSpeechRightTarget) {
      this.speechRightTarget.style.display = hasTranslate ? 'block' : 'none'
    }
  }
}
