import { Controller } from "@hotwired/stimulus"

// Session Replay Controller
// Handles agent typing animation for the checkout form preview
// With full interactive timeline: play/pause, seek, step, speed control
export default class extends Controller {
  static targets = [
    "viewport", "cursor", "card", "expiry", "cvc", "pay",
    "actionList", "timeline", "timelineProgress", "playhead",
    "traceLog", "handoffOverlay", "stepCounter", "cassetteBadge",
    "playPauseBtn", "playPauseIcon", "speedBtn", "speedDisplay"
  ]

  static values = {
    recordingId: Number,
    handoffEnabled: { type: Boolean, default: true },
    handoffStep: { type: Number, default: 4 } // Pause after expiry field
  }

  connect() {
    this.isPlaying = true
    this.isPausedByUser = false
    this.isPausedByHover = false
    this.userHasTakenOver = false
    this.animationTimer = null
    this.currentStep = 0
    this.traceEntries = []
    this.playbackSpeed = 1
    this.speeds = [0.5, 1, 1.5, 2]
    this.speedIndex = 1

    this.fields = [
      { target: 'card', position: 'at-card', text: '4242 4242 4242 4242' },
      { target: 'expiry', position: 'at-expiry', text: '12/25' },
      { target: 'cvc', position: 'at-cvc', text: '123' },
    ]

    this.actions = [
      { type: 'navigate', text: 'navigate', status: 'completed' },
      { type: 'snapshot', text: 'snapshot', status: 'completed' },
      { type: 'type', text: 'type card', status: 'pending', fieldIndex: 0 },
      { type: 'type', text: 'type expiry', status: 'pending', fieldIndex: 1 },
      { type: 'type', text: 'type cvc', status: 'pending', fieldIndex: 2 },
      { type: 'click', text: 'click Pay', status: 'pending' },
      { type: 'snapshot', text: 'snapshot', status: 'pending' },
    ]

    // Update action list UI with click handlers
    this.updateActionList()
    this.updatePlayPauseIcon()

    // Start animation after a brief delay
    setTimeout(() => this.runAnimation(), 800)
  }

  disconnect() {
    this.clearTimers()
  }

  clearTimers() {
    if (this.animationTimer) {
      clearTimeout(this.animationTimer)
      this.animationTimer = null
    }
  }

  get isPaused() {
    return this.isPausedByUser || this.isPausedByHover || !this.isPlaying
  }

  // ==================== Playback Controls ====================

  togglePlayPause(event) {
    if (event) event.stopPropagation()

    if (this.userHasTakenOver) return

    this.isPlaying = !this.isPlaying
    this.isPausedByUser = !this.isPlaying
    this.updatePlayPauseIcon()

    // If resuming and we were at handoff, dismiss it
    if (this.isPlaying && this.hasHandoffOverlayTarget &&
        this.handoffOverlayTarget.style.display !== 'none') {
      // Don't auto-dismiss, let user decide
    }
  }

  updatePlayPauseIcon() {
    if (this.hasPlayPauseIconTarget) {
      if (this.isPlaying && !this.isPausedByUser) {
        this.playPauseIconTarget.className = 'fa-solid fa-pause'
      } else {
        this.playPauseIconTarget.className = 'fa-solid fa-play'
      }
    }
  }

  stepBackward(event) {
    if (event) event.stopPropagation()
    if (this.userHasTakenOver) return

    // Pause playback
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()

    // Go to previous step
    const targetStep = Math.max(0, this.currentStep - 1)
    this.jumpToStep(targetStep)
  }

  stepForward(event) {
    if (event) event.stopPropagation()
    if (this.userHasTakenOver) return

    // Pause playback
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()

    // Go to next step
    const targetStep = Math.min(this.actions.length - 1, this.currentStep + 1)
    this.jumpToStep(targetStep)
  }

  cycleSpeed(event) {
    if (event) event.stopPropagation()

    this.speedIndex = (this.speedIndex + 1) % this.speeds.length
    this.playbackSpeed = this.speeds[this.speedIndex]

    if (this.hasSpeedDisplayTarget) {
      this.speedDisplayTarget.textContent = `${this.playbackSpeed}x`
    }
  }

  restart(event) {
    if (event) event.stopPropagation()

    this.userHasTakenOver = false
    this.isPlaying = true
    this.isPausedByUser = false
    this.clearTimers()

    // Hide handoff overlay
    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Hide trace log
    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'none'
      const entries = this.traceLogTarget.querySelector('.trace-entries')
      if (entries) entries.innerHTML = ''
    }

    this.traceEntries = []
    this.updatePlayPauseIcon()
    this.runAnimation()
  }

  // ==================== Timeline Seeking ====================

  seekTimeline(event) {
    if (this.userHasTakenOver) return

    const timeline = this.timelineTarget
    const rect = timeline.getBoundingClientRect()
    const clickX = event.clientX - rect.left
    const percent = (clickX / rect.width) * 100

    // Map percentage to step (0-6 steps mapped to 0-100%)
    const targetStep = Math.round((percent / 100) * (this.actions.length - 1))

    // Pause and jump
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()

    this.jumpToStep(Math.max(0, Math.min(this.actions.length - 1, targetStep)))
  }

  jumpToSnapshot(event) {
    event.stopPropagation()
    if (this.userHasTakenOver) return

    const step = parseInt(event.currentTarget.dataset.step, 10)

    // Pause and jump
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()

    this.jumpToStep(step)
  }

  jumpToAction(event) {
    event.stopPropagation()
    if (this.userHasTakenOver) return

    const step = parseInt(event.currentTarget.dataset.step, 10)

    // Pause and jump
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()

    this.jumpToStep(step)
  }

  jumpToStep(targetStep) {
    this.clearTimers()

    // Hide handoff overlay when jumping
    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Reset all field values based on target step
    this.fields.forEach((field, idx) => {
      const input = this[`${field.target}Target`]
      if (input) {
        // Steps 2, 3, 4 correspond to typing card, expiry, cvc
        const fieldStep = idx + 2
        if (targetStep > fieldStep) {
          // Field is complete
          input.value = field.text
        } else if (targetStep === fieldStep) {
          // Field is in progress - show partial or empty
          input.value = ''
        } else {
          // Field not yet reached
          input.value = ''
        }
        input.closest('.form-input')?.classList.remove('typing')
        input.disabled = true
        input.classList.remove('user-editable')
      }
    })

    // Update pay button state
    if (this.hasPayTarget) {
      if (targetStep >= 6) {
        this.payTarget.textContent = 'Payment Successful!'
        this.payTarget.style.background = 'linear-gradient(135deg, #10b981, #059669)'
        this.payTarget.style.opacity = '1'
      } else if (targetStep === 5) {
        this.payTarget.textContent = 'Processing...'
        this.payTarget.style.background = ''
        this.payTarget.style.opacity = '0.7'
      } else {
        this.payTarget.textContent = 'Pay $99.00'
        this.payTarget.style.background = ''
        this.payTarget.style.opacity = ''
      }
      this.payTarget.disabled = true
      this.payTarget.classList.remove('user-clickable')
    }

    // Update action statuses
    this.actions.forEach((action, idx) => {
      if (idx < targetStep) {
        action.status = 'completed'
      } else if (idx === targetStep) {
        action.status = 'active'
      } else {
        action.status = 'pending'
      }
    })

    // Update cursor position
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.remove('hidden')
      if (targetStep >= 2 && targetStep <= 4) {
        const fieldIndex = targetStep - 2
        this.cursorTarget.className = 'agent-cursor ' + this.fields[fieldIndex].position
      } else if (targetStep === 5) {
        this.cursorTarget.className = 'agent-cursor at-pay'
      } else if (targetStep >= 6) {
        this.cursorTarget.classList.add('hidden')
      } else {
        this.cursorTarget.className = 'agent-cursor at-card'
      }
    }

    // Reset cassette badge
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }

    this.currentStep = targetStep
    this.updateActionList()
    this.updateTimeline(this.stepToPercent(targetStep))
    this.updateStepCounter()
    this.updateSnapshotMarkers()
  }

  stepToPercent(step) {
    // Map steps 0-6 to timeline percent
    const percents = [5, 15, 30, 45, 60, 75, 95]
    return percents[Math.min(step, percents.length - 1)]
  }

  updateSnapshotMarkers() {
    const markers = this.element.querySelectorAll('.snapshot-marker')
    markers.forEach(marker => {
      const markerStep = parseInt(marker.dataset.step, 10)
      marker.classList.remove('completed', 'active', 'pending')
      if (markerStep < this.currentStep) {
        marker.classList.add('completed')
      } else if (markerStep === this.currentStep) {
        marker.classList.add('active')
      } else {
        marker.classList.add('pending')
      }
    })
  }

  // ==================== Mouse Events ====================

  pauseOnHover() {
    if (!this.userHasTakenOver && !this.isPausedByUser) {
      this.isPausedByHover = true
    }
  }

  resumeOnLeave() {
    if (!this.userHasTakenOver) {
      this.isPausedByHover = false
    }
  }

  // ==================== Handoff ====================

  takeOver() {
    this.userHasTakenOver = true
    this.isPlaying = false
    this.clearTimers()

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

    this.updatePlayPauseIcon()
  }

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

  trackUserInput(event) {
    if (!this.userHasTakenOver) return

    const field = event.target.closest('[data-session-replay-target]')
    const fieldName = field?.dataset.sessionReplayTarget || 'unknown'
    const maskedValue = event.target.value.replace(/\d/g, '*')

    this.addTraceEntry('user_input', `${fieldName}: ${maskedValue}`)
  }

  userPay(event) {
    event.preventDefault()

    if (!this.hasPayTarget) return

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

      this.actions[5].status = 'completed'
      this.actions[6].status = 'completed'
      this.currentStep = 7
      this.updateActionList()
      this.updateTimeline(100)
      this.updateSnapshotMarkers()
    }, 1500)
  }

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

      const container = this.traceLogTarget.querySelector('.trace-entries')
      if (container) {
        container.scrollTop = container.scrollHeight
      }
    }
  }

  // ==================== Animation ====================

  typeText(input, text, callback) {
    let i = input.value.length
    const parent = input.closest('.form-input')
    if (parent) parent.classList.add('typing')

    const baseDelay = 60

    const typeChar = () => {
      if (this.isPaused || this.userHasTakenOver) {
        this.animationTimer = setTimeout(typeChar, 100)
        return
      }
      if (i < text.length) {
        input.value = text.substring(0, i + 1)
        i++
        const delay = (baseDelay + Math.random() * 40) / this.playbackSpeed
        this.animationTimer = setTimeout(typeChar, delay)
      } else {
        if (parent) parent.classList.remove('typing')
        const delay = 300 / this.playbackSpeed
        this.animationTimer = setTimeout(callback, delay)
      }
    }
    typeChar()
  }

  updateActionList() {
    if (!this.hasActionListTarget) return

    this.actionListTarget.innerHTML = this.actions.map((action, idx) => `
      <div class="action-item ${action.status}"
           data-action="click->session-replay#jumpToAction"
           data-step="${idx}"
           style="cursor: pointer;">
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

  updateTimeline(percent) {
    if (this.hasTimelineProgressTarget) {
      this.timelineProgressTarget.style.width = `${percent}%`
    }
    if (this.hasPlayheadTarget) {
      this.playheadTarget.style.left = `${percent}%`
    }
  }

  updateStepCounter() {
    if (this.hasStepCounterTarget) {
      if (this.userHasTakenOver) {
        this.stepCounterTarget.textContent = 'Your session'
      } else {
        this.stepCounterTarget.textContent = `Step ${this.currentStep + 1}/${this.actions.length}`
      }
    }
  }

  showHandoffPrompt() {
    if (!this.handoffEnabledValue) return

    // Pause playback
    this.isPlaying = false
    this.updatePlayPauseIcon()

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
        input.classList.remove('user-editable')
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
    this.updateSnapshotMarkers()

    if (this.hasPayTarget) {
      this.payTarget.textContent = 'Pay $99.00'
      this.payTarget.style.background = ''
      this.payTarget.style.opacity = ''
      this.payTarget.disabled = true
      this.payTarget.classList.remove('user-clickable')
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
        this.updateTimeline(this.stepToPercent(this.currentStep))
        this.updateStepCounter()

        const delay = 400 / this.playbackSpeed
        this.animationTimer = setTimeout(() => {
          if (input) {
            this.typeText(input, field.text, () => {
              this.actions[this.currentStep].status = 'completed'
              this.currentStep++
              fieldIndex++
              this.updateActionList()
              this.updateSnapshotMarkers()
              nextField()
            })
          }
        }, delay)
      } else {
        // Move to pay button
        if (this.hasCursorTarget) {
          this.cursorTarget.className = 'agent-cursor at-pay'
        }

        this.actions[this.currentStep].status = 'active'
        this.updateActionList()
        this.updateTimeline(75)
        this.updateStepCounter()

        const delay1 = 500 / this.playbackSpeed
        this.animationTimer = setTimeout(() => {
          if (this.hasPayTarget) {
            this.payTarget.textContent = 'Processing...'
            this.payTarget.style.opacity = '0.7'

            const delay2 = 1000 / this.playbackSpeed
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
              this.updateSnapshotMarkers()

              if (this.hasCursorTarget) {
                this.cursorTarget.classList.add('hidden')
              }

              // Wait then restart
              const delay3 = 2500 / this.playbackSpeed
              this.animationTimer = setTimeout(() => {
                if (this.hasCursorTarget) {
                  this.cursorTarget.classList.remove('hidden')
                }
                if (!this.userHasTakenOver && this.isPlaying) {
                  this.runAnimation()
                }
              }, delay3)
            }, delay2)
          }
        }, delay1)
      }
    }

    // Start with cursor at card field
    if (this.hasCursorTarget) {
      this.cursorTarget.className = 'agent-cursor at-card'
      this.cursorTarget.classList.remove('hidden')
    }
    const startDelay = 600 / this.playbackSpeed
    this.animationTimer = setTimeout(nextField, startDelay)
  }
}
