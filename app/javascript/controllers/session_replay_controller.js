import { Controller } from "@hotwired/stimulus"

// Session Replay Controller
// Handles agent typing animation for the checkout form preview
// Now with handoff support - users can take over from the agent
export default class extends Controller {
  static targets = [
    "viewport", "cursor", "card", "expiry", "cvc", "pay",
    "actionList", "timeline", "timelineProgress", "playhead",
    "traceLog", "handoffOverlay", "stepCounter", "cassetteBadge"
  ]

  static values = {
    recordingId: Number,
    handoffEnabled: { type: Boolean, default: true },
    handoffStep: { type: Number, default: 4 } // Pause after expiry field
  }

  connect() {
    this.isPaused = false
    this.userHasTakenOver = false
    this.animationTimer = null
    this.currentStep = 0
    this.traceEntries = []

    this.fields = [
      { target: 'card', position: 'at-card', text: '4242 4242 4242 4242' },
      { target: 'expiry', position: 'at-expiry', text: '12/25' },
      { target: 'cvc', position: 'at-cvc', text: '123' },
    ]

    this.actions = [
      { type: 'navigate', text: 'navigate', status: 'completed' },
      { type: 'snapshot', text: 'snapshot', status: 'completed' },
      { type: 'type', text: 'type card', status: 'pending' },
      { type: 'type', text: 'type expiry', status: 'pending' },
      { type: 'type', text: 'type cvc', status: 'pending' },
      { type: 'click', text: 'click Pay', status: 'pending' },
      { type: 'snapshot', text: 'snapshot', status: 'pending' },
    ]

    // Update action list UI
    this.updateActionList()

    // Start animation after a brief delay
    setTimeout(() => this.runAnimation(), 800)
  }

  disconnect() {
    if (this.animationTimer) clearTimeout(this.animationTimer)
  }

  // Mouse events for pausing
  pauseOnHover() {
    if (!this.userHasTakenOver) {
      this.isPaused = true
    }
  }

  resumeOnLeave() {
    if (!this.userHasTakenOver) {
      this.isPaused = false
    }
  }

  // User takes over from the agent
  takeOver() {
    this.userHasTakenOver = true
    this.isPaused = true

    // Hide handoff overlay
    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Hide cursor
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.add('hidden')
    }

    // Update cassette badge to LIVE
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle"></i> <span>LIVE</span>'
      this.cassetteBadgeTarget.classList.add('live')
    }

    // Enable form inputs
    this.enableInputs()

    // Log handoff event
    this.addTraceEntry('handoff', 'User took over session')

    // Show trace log
    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'block'
    }
  }

  // Enable inputs for user interaction
  enableInputs() {
    const inputs = [this.cardTarget, this.expiryTarget, this.cvcTarget]
    inputs.forEach(input => {
      if (input) {
        input.disabled = false
        input.classList.add('user-editable')
      }
    })

    if (this.hasPayTarget) {
      this.payTarget.disabled = false
      this.payTarget.classList.add('user-clickable')
    }
  }

  // Track user input after handoff
  trackUserInput(event) {
    if (!this.userHasTakenOver) return

    const field = event.target.closest('[data-session-replay-target]')
    const fieldName = field?.dataset.sessionReplayTarget || 'unknown'
    const maskedValue = event.target.value.replace(/\d/g, '*')

    this.addTraceEntry('user_input', `${fieldName}: ${maskedValue}`)
  }

  // Handle user payment
  userPay(event) {
    event.preventDefault()

    if (!this.hasPayTarget) return

    // If not taken over, just show the animation
    if (!this.userHasTakenOver) {
      return
    }

    this.addTraceEntry('user_action', 'click: Pay button')

    const btn = this.payTarget
    btn.textContent = 'Processing...'
    btn.style.opacity = '0.7'
    btn.disabled = true

    setTimeout(() => {
      btn.textContent = 'Payment Successful!'
      btn.style.background = 'linear-gradient(135deg, #10b981, #059669)'
      btn.style.opacity = '1'

      this.addTraceEntry('completion', 'Payment successful')

      // Update final action
      this.actions[5].status = 'completed'
      this.actions[6].status = 'completed'
      this.updateActionList()
      this.updateTimeline(100)
    }, 1500)
  }

  // Add entry to trace log
  addTraceEntry(type, message) {
    const entry = { type, message, timestamp: new Date().toISOString() }
    this.traceEntries.push(entry)

    if (this.hasTraceLogTarget) {
      const entryEl = document.createElement('div')
      entryEl.className = `trace-entry ${type}`
      entryEl.innerHTML = `
        <span class="trace-type">${type}</span>
        <span class="trace-message">${message}</span>
      `
      this.traceLogTarget.querySelector('.trace-entries')?.appendChild(entryEl)

      // Scroll to bottom
      const container = this.traceLogTarget.querySelector('.trace-entries')
      if (container) {
        container.scrollTop = container.scrollHeight
      }
    }
  }

  // Type text into a field with animation
  typeText(input, text, callback) {
    let i = input.value.length
    const parent = input.closest('.form-input')
    if (parent) parent.classList.add('typing')

    const typeChar = () => {
      if (this.isPaused || this.userHasTakenOver) {
        this.animationTimer = setTimeout(typeChar, 100)
        return
      }
      if (i < text.length) {
        input.value = text.substring(0, i + 1)
        i++
        this.animationTimer = setTimeout(typeChar, 60 + Math.random() * 40)
      } else {
        if (parent) parent.classList.remove('typing')
        this.animationTimer = setTimeout(callback, 300)
      }
    }
    typeChar()
  }

  // Update action list UI
  updateActionList() {
    if (!this.hasActionListTarget) return

    this.actionListTarget.innerHTML = this.actions.map((action, idx) => `
      <div class="action-item ${action.status}">
        <span class="action-icon">
          <i class="fa-solid ${this.getActionIcon(action.type)}"></i>
        </span>
        <span class="action-text">${action.text}</span>
        <span class="action-status">
          ${action.status === 'completed' ? '<i class="fa-solid fa-check"></i>' : ''}
          ${action.status === 'active' ? '<i class="fa-solid fa-play"></i>' : ''}
        </span>
      </div>
    `).join('')
  }

  getActionIcon(type) {
    const icons = {
      navigate: 'fa-globe',
      snapshot: 'fa-camera',
      type: 'fa-keyboard',
      click: 'fa-hand-pointer'
    }
    return icons[type] || 'fa-circle'
  }

  // Update timeline progress
  updateTimeline(percent) {
    if (this.hasTimelineProgressTarget) {
      this.timelineProgressTarget.style.width = `${percent}%`
    }
    if (this.hasPlayheadTarget) {
      this.playheadTarget.style.left = `${percent}%`
    }
  }

  // Update step counter
  updateStepCounter() {
    if (this.hasStepCounterTarget) {
      if (this.userHasTakenOver) {
        this.stepCounterTarget.textContent = 'Your session'
      } else {
        this.stepCounterTarget.textContent = `Step ${this.currentStep + 1}/${this.actions.length}`
      }
    }
  }

  // Show handoff prompt
  showHandoffPrompt() {
    if (!this.handoffEnabledValue) return

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'flex'
    }
  }

  // Main animation loop
  runAnimation() {
    // Reset all fields
    this.fields.forEach(f => {
      const input = this[`${f.target}Target`]
      if (input) {
        input.value = ''
        input.closest('.form-input')?.classList.remove('typing')
        input.disabled = true
      }
    })

    // Reset actions
    this.actions.forEach((action, idx) => {
      action.status = idx < 2 ? 'completed' : 'pending'
    })

    this.currentStep = 2 // Start at first type action
    this.updateActionList()
    this.updateTimeline(20)
    this.updateStepCounter()

    if (this.hasPayTarget) {
      this.payTarget.textContent = 'Pay $99.00'
      this.payTarget.style.background = ''
      this.payTarget.style.opacity = ''
      this.payTarget.disabled = true
    }

    // Reset cassette badge
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }

    let fieldIndex = 0

    const nextField = () => {
      if (this.isPaused || this.userHasTakenOver) {
        this.animationTimer = setTimeout(nextField, 100)
        return
      }

      // Check for handoff point
      if (this.handoffEnabledValue && this.currentStep === this.handoffStepValue) {
        this.showHandoffPrompt()
        return
      }

      if (fieldIndex < this.fields.length) {
        const field = this.fields[fieldIndex]
        const input = this[`${field.target}Target`]

        // Update cursor position
        if (this.hasCursorTarget) {
          this.cursorTarget.className = 'agent-cursor ' + field.position
        }

        // Update action status
        this.actions[this.currentStep].status = 'active'
        this.updateActionList()
        this.updateTimeline(20 + (fieldIndex / this.fields.length) * 50)
        this.updateStepCounter()

        this.animationTimer = setTimeout(() => {
          if (input) {
            this.typeText(input, field.text, () => {
              this.actions[this.currentStep].status = 'completed'
              this.currentStep++
              fieldIndex++
              this.updateActionList()
              nextField()
            })
          }
        }, 400)
      } else {
        // Move to pay button
        if (this.hasCursorTarget) {
          this.cursorTarget.className = 'agent-cursor at-pay'
        }

        this.actions[this.currentStep].status = 'active'
        this.updateActionList()
        this.updateTimeline(75)
        this.updateStepCounter()

        this.animationTimer = setTimeout(() => {
          if (this.hasPayTarget) {
            this.payTarget.textContent = 'Processing...'
            this.payTarget.style.opacity = '0.7'

            this.animationTimer = setTimeout(() => {
              this.payTarget.textContent = 'Payment Successful!'
              this.payTarget.style.background = 'linear-gradient(135deg, #10b981, #059669)'
              this.payTarget.style.opacity = '1'

              this.actions[5].status = 'completed'
              this.actions[6].status = 'completed'
              this.currentStep = 7
              this.updateActionList()
              this.updateTimeline(100)
              this.updateStepCounter()

              if (this.hasCursorTarget) {
                this.cursorTarget.classList.add('hidden')
              }

              // Wait then restart
              this.animationTimer = setTimeout(() => {
                if (this.hasCursorTarget) {
                  this.cursorTarget.classList.remove('hidden')
                }
                if (!this.userHasTakenOver) {
                  this.runAnimation()
                }
              }, 2500)
            }, 1000)
          }
        }, 500)
      }
    }

    // Start with cursor at card field
    if (this.hasCursorTarget) {
      this.cursorTarget.className = 'agent-cursor at-card'
      this.cursorTarget.classList.remove('hidden')
    }
    this.animationTimer = setTimeout(nextField, 600)
  }
}
