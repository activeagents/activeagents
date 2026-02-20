import { Controller } from "@hotwired/stimulus"

// Agent Builder Controller
// Interactive agent preview for the hero section with multi-select capabilities
export default class extends Controller {
  static targets = ["instructions", "tools", "speechLeft", "speechRight", "configInstructions", "configTools", "instructionChips", "toolChips"]

  // Instructions - system/developer message types (displayed as head/hat)
  static instructions = {
    github: { emoji: '🐙', label: 'GitHub' },
    ruby: { emoji: '💎', label: 'Ruby' },
    rails: { emoji: '🛤️', label: 'Rails' },
    aws: { emoji: '☁️', label: 'AWS' },
    gcp: { emoji: '🌐', label: 'GCP' },
    python: { emoji: '🐍', label: 'Python' },
    typescript: { emoji: '📘', label: 'TypeScript' },
    docker: { emoji: '🐳', label: 'Docker' },
    kubernetes: { emoji: '☸️', label: 'Kubernetes' },
  }

  // Tools/MCPs - actions and integrations the agent can use (displayed as hands)
  static tools = {
    terminal: { emoji: '💻', label: 'Terminal' },
    playwright: { emoji: '🎭', label: 'Playwright' },
    filesystem: { emoji: '📁', label: 'Filesystem' },
    code: { emoji: '👨‍💻', label: 'Code' },
    database: { emoji: '🗄️', label: 'Database' },
    slack: { emoji: '💬', label: 'Slack' },
    fetch: { emoji: '🌐', label: 'Fetch' },
    search: { emoji: '🔍', label: 'Search' },
    edit: { emoji: '✏️', label: 'Edit' },
    translate: { emoji: '🌍', label: 'Translate' },
    memory: { emoji: '🧠', label: 'Memory' },
  }

  // Presets - example agent configurations
  static presets = {
    'claude-code': {
      instructions: ['github'],
      tools: ['terminal', 'code']
    },
    'web-scraper': {
      instructions: ['typescript'],
      tools: ['playwright', 'fetch']
    },
    'data-analyst': {
      instructions: ['python'],
      tools: ['database', 'search', 'code']
    },
    'devops': {
      instructions: ['github', 'aws'],
      tools: ['terminal', 'slack', 'code']
    },
    'polyglot': {
      instructions: ['ruby', 'python', 'typescript'],
      tools: ['translate', 'code']
    },
    'research': {
      instructions: ['github'],
      tools: ['fetch', 'search', 'memory']
    },
  }

  connect() {
    // Track selected items
    this.selectedInstructions = new Set(['github'])
    this.selectedTools = new Set(['terminal', 'code'])

    // Default to Claude Code preset
    this.currentPreset = 'claude-code'
    this.renderFromSelections()
  }

  selectPreset(event) {
    const preset = event.currentTarget.dataset.preset

    // Update active button state
    this.element.querySelectorAll('.preset-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.preset === preset)
    })

    this.currentPreset = preset
    this.applyPreset(preset)
  }

  applyPreset(presetName) {
    const preset = this.constructor.presets[presetName]
    if (!preset) return

    // Update selections from preset
    this.selectedInstructions = new Set(preset.instructions)
    this.selectedTools = new Set(preset.tools)

    // Update chip button states
    this.updateChipStates()

    // Re-render
    this.renderFromSelections()
  }

  toggleInstruction(event) {
    const instruction = event.currentTarget.dataset.instruction

    if (this.selectedInstructions.has(instruction)) {
      this.selectedInstructions.delete(instruction)
      event.currentTarget.classList.remove('selected')
    } else {
      this.selectedInstructions.add(instruction)
      event.currentTarget.classList.add('selected')
    }

    // Clear preset active state since user is customizing
    this.clearPresetActive()
    this.renderFromSelections()
  }

  toggleTool(event) {
    const tool = event.currentTarget.dataset.tool

    if (this.selectedTools.has(tool)) {
      this.selectedTools.delete(tool)
      event.currentTarget.classList.remove('selected')
    } else {
      this.selectedTools.add(tool)
      event.currentTarget.classList.add('selected')
    }

    // Clear preset active state since user is customizing
    this.clearPresetActive()
    this.renderFromSelections()
  }

  clearPresetActive() {
    this.element.querySelectorAll('.preset-btn').forEach(btn => {
      btn.classList.remove('active')
    })
    this.currentPreset = null
  }

  updateChipStates() {
    // Update instruction chip states
    if (this.hasInstructionChipsTarget) {
      this.instructionChipsTarget.querySelectorAll('.chip-btn').forEach(btn => {
        const instruction = btn.dataset.instruction
        btn.classList.toggle('selected', this.selectedInstructions.has(instruction))
      })
    }

    // Update tool chip states
    if (this.hasToolChipsTarget) {
      this.toolChipsTarget.querySelectorAll('.chip-btn').forEach(btn => {
        const tool = btn.dataset.tool
        btn.classList.toggle('selected', this.selectedTools.has(tool))
      })
    }
  }

  renderFromSelections() {
    this.renderInstructions()
    this.renderTools()
    this.updateConfig()
    this.handleTranslation()
  }

  renderInstructions() {
    if (!this.hasInstructionsTarget) return

    const instructionIds = Array.from(this.selectedInstructions)
    const html = instructionIds.map((id, i) => {
      const instruction = this.constructor.instructions[id]
      if (!instruction) return ''
      return `<span class="instruction-item" style="animation-delay: ${i * 0.1}s" title="${instruction.label}">${instruction.emoji}</span>`
    }).join('')

    this.instructionsTarget.innerHTML = html || '<span class="instruction-item empty">💬</span>'
  }

  renderTools() {
    if (!this.hasToolsTarget) return

    // Filter out translate for display (shown as speech bubbles instead)
    const toolIds = Array.from(this.selectedTools).filter(id => id !== 'translate')

    const html = toolIds.map(id => {
      const tool = this.constructor.tools[id]
      if (!tool) return ''
      return `<span class="tool-item" title="${tool.label}">${tool.emoji}</span>`
    }).join('')

    this.toolsTarget.innerHTML = html || '<span class="tool-item empty">🔧</span>'
  }

  updateConfig() {
    if (this.hasConfigInstructionsTarget) {
      const labels = Array.from(this.selectedInstructions).map(id => {
        const instruction = this.constructor.instructions[id]
        return instruction ? `${instruction.emoji} ${instruction.label}` : ''
      }).filter(Boolean).join(', ')
      this.configInstructionsTarget.textContent = labels || 'None selected'
    }

    if (this.hasConfigToolsTarget) {
      const labels = Array.from(this.selectedTools).map(id => {
        const tool = this.constructor.tools[id]
        return tool ? `${tool.emoji} ${tool.label}` : ''
      }).filter(Boolean).join(', ')
      this.configToolsTarget.textContent = labels || 'None selected'
    }
  }

  handleTranslation() {
    const hasTranslate = this.selectedTools.has('translate')

    if (this.hasSpeechLeftTarget) {
      this.speechLeftTarget.style.display = hasTranslate ? 'block' : 'none'
    }
    if (this.hasSpeechRightTarget) {
      this.speechRightTarget.style.display = hasTranslate ? 'block' : 'none'
    }
  }
}
