import { Controller } from "@hotwired/stimulus"

// Agent Builder Controller
// Interactive agent preview for the hero section with CLI tools and MCP services
export default class extends Controller {
  static targets = [
    "instructions", "toolsLeft", "toolsRight",
    "speechLeft", "speechRight",
    "configInstructions", "configCli", "configMcp",
    "instructionChips", "cliChips", "mcpChips"
  ]

  // Instructions - system/developer message types (displayed as badge on hat)
  static instructions = {
    github: { icon: '@', label: 'GitHub' },
    ruby: { icon: '*', label: 'Ruby' },
    rails: { icon: '#', label: 'Rails' },
    aws: { icon: '~', label: 'AWS' },
    gcp: { icon: '~', label: 'GCP' },
    python: { icon: '>', label: 'Python' },
    typescript: { icon: '<>', label: 'TypeScript' },
    docker: { icon: '[]', label: 'Docker' },
    kubernetes: { icon: '{}', label: 'Kubernetes' },
  }

  // CLI Tools (left hand) - command line and code tools
  static cliTools = {
    bash: { logo: 'bash', label: 'Bash', icon: '$' },
    git: { logo: 'git', label: 'Git', icon: '+' },
    ruby: { logo: 'ruby', label: 'Ruby', icon: '*' },
    gh: { logo: 'github', label: 'gh CLI', icon: '@' },
  }

  // MCP Services (right hand) - Model Context Protocol integrations
  static mcpServices = {
    playwright: { logo: 'playwright', label: 'Playwright', icon: '>' },
    slack: { logo: 'slack', label: 'Slack', icon: '@' },
    github: { logo: 'github', label: 'GitHub', icon: '@' },
    linear: { logo: 'linear', label: 'Linear', icon: '+' },
    sentry: { logo: 'sentry', label: 'Sentry', icon: '!' },
    postgres: { logo: 'postgresql', label: 'Postgres', icon: '#' },
    notion: { logo: 'notion', label: 'Notion', icon: '*' },
    figma: { logo: 'figma', label: 'Figma', icon: '+' },
    huggingface: { logo: 'huggingface', label: 'HuggingFace', icon: '~' },
  }

  // Presets - example agent configurations
  static presets = {
    'claude-code': {
      instructions: ['github'],
      cli: ['bash', 'git'],
      mcp: []
    },
    'web-scraper': {
      instructions: ['typescript'],
      cli: ['bash'],
      mcp: ['playwright']
    },
    'data-analyst': {
      instructions: ['python'],
      cli: ['ruby'],
      mcp: ['postgres']
    },
    'devops': {
      instructions: ['github', 'aws'],
      cli: ['bash', 'git', 'gh'],
      mcp: ['slack', 'sentry']
    },
    'polyglot': {
      instructions: ['ruby', 'python', 'typescript'],
      cli: ['ruby'],
      mcp: []
    },
    'research': {
      instructions: ['github'],
      cli: ['git'],
      mcp: ['github', 'notion']
    },
  }

  connect() {
    // Track selected items
    this.selectedInstructions = new Set(['github'])
    this.selectedCli = new Set(['bash', 'git'])
    this.selectedMcp = new Set()

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
    this.selectedCli = new Set(preset.cli)
    this.selectedMcp = new Set(preset.mcp)

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

    this.clearPresetActive()
    this.renderFromSelections()
  }

  toggleCli(event) {
    const cli = event.currentTarget.dataset.cli

    if (this.selectedCli.has(cli)) {
      this.selectedCli.delete(cli)
      event.currentTarget.classList.remove('selected')
    } else {
      this.selectedCli.add(cli)
      event.currentTarget.classList.add('selected')
    }

    this.clearPresetActive()
    this.renderFromSelections()
  }

  toggleMcp(event) {
    const mcp = event.currentTarget.dataset.mcp

    if (this.selectedMcp.has(mcp)) {
      this.selectedMcp.delete(mcp)
      event.currentTarget.classList.remove('selected')
    } else {
      this.selectedMcp.add(mcp)
      event.currentTarget.classList.add('selected')
    }

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

    // Update CLI chip states
    if (this.hasCliChipsTarget) {
      this.cliChipsTarget.querySelectorAll('.chip-btn').forEach(btn => {
        const cli = btn.dataset.cli
        btn.classList.toggle('selected', this.selectedCli.has(cli))
      })
    }

    // Update MCP chip states
    if (this.hasMcpChipsTarget) {
      this.mcpChipsTarget.querySelectorAll('.chip-btn').forEach(btn => {
        const mcp = btn.dataset.mcp
        btn.classList.toggle('selected', this.selectedMcp.has(mcp))
      })
    }
  }

  renderFromSelections() {
    this.renderInstructions()
    this.renderCliTools()
    this.renderMcpServices()
    this.updateConfig()
    this.handleTranslation()
  }

  renderInstructions() {
    if (!this.hasInstructionsTarget) return

    const instructionIds = Array.from(this.selectedInstructions)
    const html = instructionIds.map((id, i) => {
      const instruction = this.constructor.instructions[id]
      if (!instruction) return ''
      return `<span class="instruction-badge-item" title="${instruction.label}" style="font-family: monospace;">${instruction.icon}</span>`
    }).join('')

    this.instructionsTarget.innerHTML = html || '<span class="instruction-badge-item empty" style="font-family: monospace;">@</span>'
  }

  renderCliTools() {
    if (!this.hasToolsLeftTarget) return

    const cliIds = Array.from(this.selectedCli)
    const html = cliIds.map(id => {
      const cli = this.constructor.cliTools[id]
      if (!cli) return ''
      return `<span class="tool-item cli-tool" title="${cli.label}">
        <img src="images/mcp-logos/${cli.logo}.svg" alt="${cli.label}" class="tool-logo" style="width: 28px; height: 28px;">
      </span>`
    }).join('')

    this.toolsLeftTarget.innerHTML = html || '<span class="tool-item empty" style="font-family: monospace;">$</span>'
  }

  renderMcpServices() {
    if (!this.hasToolsRightTarget) return

    const mcpIds = Array.from(this.selectedMcp)
    const html = mcpIds.map(id => {
      const mcp = this.constructor.mcpServices[id]
      if (!mcp) return ''
      return `<span class="tool-item mcp-service" title="${mcp.label}">
        <img src="images/mcp-logos/${mcp.logo}.svg" alt="${mcp.label}" class="tool-logo" style="width: 28px; height: 28px;">
      </span>`
    }).join('')

    this.toolsRightTarget.innerHTML = html || '<span class="tool-item empty mcp-empty" style="font-family: monospace;">~</span>'
  }

  updateConfig() {
    if (this.hasConfigInstructionsTarget) {
      const labels = Array.from(this.selectedInstructions).map(id => {
        const instruction = this.constructor.instructions[id]
        return instruction ? `${instruction.emoji} ${instruction.label}` : ''
      }).filter(Boolean).join(', ')
      this.configInstructionsTarget.textContent = labels || 'None'
    }

    if (this.hasConfigCliTarget) {
      const labels = Array.from(this.selectedCli).map(id => {
        const cli = this.constructor.cliTools[id]
        return cli ? cli.label : ''
      }).filter(Boolean).join(', ')
      this.configCliTarget.textContent = labels || 'None'
    }

    if (this.hasConfigMcpTarget) {
      const labels = Array.from(this.selectedMcp).map(id => {
        const mcp = this.constructor.mcpServices[id]
        return mcp ? mcp.label : ''
      }).filter(Boolean).join(', ')
      this.configMcpTarget.textContent = labels || 'None'
    }
  }

  handleTranslation() {
    // Show speech bubbles if translator MCP is selected (placeholder for future)
    const hasTranslate = false // this.selectedMcp.has('translate')

    if (this.hasSpeechLeftTarget) {
      this.speechLeftTarget.style.display = hasTranslate ? 'block' : 'none'
    }
    if (this.hasSpeechRightTarget) {
      this.speechRightTarget.style.display = hasTranslate ? 'block' : 'none'
    }
  }
}
