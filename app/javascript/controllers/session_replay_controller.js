import { Controller } from "@hotwired/stimulus"

// Session Replay Controller
// Handles agent animation for the demo preview
// Supports both checkout and newsletter demo modes with full interactive controls
export default class extends Controller {
  static targets = [
    "viewport", "cursor", "card", "expiry", "cvc", "pay",
    "actionList", "timeline", "timelineProgress", "playhead",
    "traceLog", "handoffOverlay", "stepCounter", "cassetteBadge",
    "playPauseBtn", "playPauseIcon", "speedBtn", "speedDisplay",
    "demoPage", "demoEmail", "demoSubscribe", "addressBar"
  ]

  static values = {
    recordingId: Number,
    handoffEnabled: { type: Boolean, default: true },
    handoffStep: { type: Number, default: 4 },
    demoMode: { type: String, default: "newsletter" }
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

    // Setup based on demo mode
    if (this.demoModeValue === "newsletter") {
      this.setupNewsletterDemo()
    } else {
      this.setupCheckoutDemo()
    }

    this.updateActionList()
    this.updatePlayPauseIcon()

    setTimeout(() => this.runAnimation(), 800)
  }

  setupNewsletterDemo() {
    this.actions = [
      { type: 'navigate', text: 'navigate', status: 'completed' },
      { type: 'snapshot', text: 'snapshot', status: 'completed' },
      { type: 'scroll', text: 'scroll down', status: 'pending' },
      { type: 'scroll', text: 'scroll to newsletter', status: 'pending' },
      { type: 'click', text: 'click email', status: 'pending' },
      { type: 'type', text: 'type email', status: 'pending' },
    ]
  }

  setupCheckoutDemo() {
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
  }

  updatePlayPauseIcon() {
    if (this.hasPlayPauseIconTarget) {
      this.playPauseIconTarget.className = this.isPlaying && !this.isPausedByUser
        ? 'fa-solid fa-pause'
        : 'fa-solid fa-play'
    }
  }

  stepBackward(event) {
    if (event) event.stopPropagation()
    if (this.userHasTakenOver) return

    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()
    this.jumpToStep(Math.max(0, this.currentStep - 1))
  }

  stepForward(event) {
    if (event) event.stopPropagation()
    if (this.userHasTakenOver) return

    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()
    this.jumpToStep(Math.min(this.actions.length - 1, this.currentStep + 1))
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

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }
    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'none'
      const entries = this.traceLogTarget.querySelector('.trace-entries')
      if (entries) entries.innerHTML = ''
    }
    if (this.hasDemoPageTarget) {
      this.demoPageTarget.style.transform = ''
    }
    if (this.hasDemoEmailTarget) {
      this.demoEmailTarget.value = ''
      this.demoEmailTarget.classList.remove('typing')
    }

    this.traceEntries = []
    this.updatePlayPauseIcon()
    this.runAnimation()
  }

  // ==================== Timeline ====================

  seekTimeline(event) {
    if (this.userHasTakenOver) return
    const rect = this.timelineTarget.getBoundingClientRect()
    const percent = ((event.clientX - rect.left) / rect.width) * 100
    const targetStep = Math.round((percent / 100) * (this.actions.length - 1))

    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()
    this.jumpToStep(Math.max(0, Math.min(this.actions.length - 1, targetStep)))
  }

  jumpToSnapshot(event) {
    event.stopPropagation()
    if (this.userHasTakenOver) return
    const step = parseInt(event.currentTarget.dataset.step, 10)
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()
    this.jumpToStep(step)
  }

  jumpToAction(event) {
    event.stopPropagation()
    if (this.userHasTakenOver) return
    const step = parseInt(event.currentTarget.dataset.step, 10)
    this.isPlaying = false
    this.isPausedByUser = true
    this.updatePlayPauseIcon()
    this.jumpToStep(step)
  }

  jumpToStep(targetStep) {
    this.clearTimers()
    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    if (this.demoModeValue === "newsletter") {
      this.jumpToNewsletterStep(targetStep)
    } else {
      this.jumpToCheckoutStep(targetStep)
    }

    this.currentStep = targetStep
    this.updateActionList()
    this.updateTimeline(this.stepToPercent(targetStep))
    this.updateStepCounter()
    this.updateSnapshotMarkers()
  }

  jumpToNewsletterStep(targetStep) {
    if (this.hasDemoPageTarget) {
      if (targetStep >= 3) {
        this.demoPageTarget.style.transform = 'translateY(-260px)'
      } else if (targetStep >= 2) {
        this.demoPageTarget.style.transform = 'translateY(-130px)'
      } else {
        this.demoPageTarget.style.transform = ''
      }
    }

    if (this.hasDemoEmailTarget) {
      this.demoEmailTarget.value = targetStep >= 5 ? 'you@example.com' : ''
      this.demoEmailTarget.classList.remove('typing')
    }

    if (this.hasCursorTarget) {
      this.cursorTarget.classList.remove('hidden')
      this.cursorTarget.className = targetStep <= 1 ? 'agent-cursor at-hero'
        : targetStep === 2 ? 'agent-cursor at-features'
        : 'agent-cursor at-email'
    }

    this.actions.forEach((action, idx) => {
      action.status = idx < targetStep ? 'completed' : idx === targetStep ? 'active' : 'pending'
    })

    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }
  }

  jumpToCheckoutStep(targetStep) {
    if (this.fields) {
      this.fields.forEach((field, idx) => {
        const input = this[`${field.target}Target`]
        if (input) {
          input.value = targetStep > idx + 2 ? field.text : ''
          input.closest('.form-input')?.classList.remove('typing')
          input.disabled = true
          input.classList.remove('user-editable')
        }
      })
    }

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

    this.actions.forEach((action, idx) => {
      action.status = idx < targetStep ? 'completed' : idx === targetStep ? 'active' : 'pending'
    })

    if (this.hasCursorTarget) {
      this.cursorTarget.classList.remove('hidden')
      if (targetStep >= 2 && targetStep <= 4 && this.fields) {
        this.cursorTarget.className = 'agent-cursor ' + this.fields[targetStep - 2].position
      } else if (targetStep === 5) {
        this.cursorTarget.className = 'agent-cursor at-pay'
      } else if (targetStep >= 6) {
        this.cursorTarget.classList.add('hidden')
      } else {
        this.cursorTarget.className = 'agent-cursor at-card'
      }
    }

    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }
  }

  stepToPercent(step) {
    const percents = this.demoModeValue === "newsletter"
      ? [5, 15, 35, 55, 75, 95]
      : [5, 15, 30, 45, 60, 75, 95]
    return percents[Math.min(step, percents.length - 1)]
  }

  updateSnapshotMarkers() {
    this.element.querySelectorAll('.snapshot-marker').forEach(marker => {
      const markerStep = parseInt(marker.dataset.step, 10)
      marker.classList.remove('completed', 'active', 'pending')
      marker.classList.add(markerStep < this.currentStep ? 'completed'
        : markerStep === this.currentStep ? 'active' : 'pending')
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

  takeOverNewsletter() {
    this.userHasTakenOver = true
    this.isPlaying = false
    this.clearTimers()

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Scroll to real newsletter section
    const newsletterSection = document.querySelector('#newsletter')
    if (newsletterSection) {
      newsletterSection.scrollIntoView({ behavior: 'smooth' })
      setTimeout(() => {
        const emailInput = document.querySelector('#newsletter-email')
        if (emailInput) emailInput.focus()
      }, 800)
    }

    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle"></i> <span>DONE</span>'
      this.cassetteBadgeTarget.classList.add('live')
    }

    this.updatePlayPauseIcon()
  }

  takeOver() {
    this.userHasTakenOver = true
    this.isPlaying = false
    this.clearTimers()

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.add('hidden')
    }
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle"></i> <span>LIVE</span>'
      this.cassetteBadgeTarget.classList.add('live')
    }

    this.enableInputs()
    this.addTraceEntry('handoff', 'User took over session')

    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'block'
    }
    this.updatePlayPauseIcon()
  }

  enableInputs() {
    if (!this.fields) return
    [this.cardTarget, this.expiryTarget, this.cvcTarget].filter(Boolean).forEach(input => {
      input.disabled = false
      input.classList.add('user-editable')
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
    this.addTraceEntry('user_input', `${fieldName}: ${event.target.value.replace(/\d/g, '*')}`)
  }

  userPay(event) {
    event.preventDefault()
    if (!this.hasPayTarget || !this.userHasTakenOver) return

    this.addTraceEntry('user_action', 'click: Pay button')
    this.payTarget.textContent = 'Processing...'
    this.payTarget.style.opacity = '0.7'
    this.payTarget.disabled = true

    setTimeout(() => {
      this.payTarget.textContent = 'Payment Successful!'
      this.payTarget.style.background = 'linear-gradient(135deg, #10b981, #059669)'
      this.payTarget.style.opacity = '1'
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
    this.traceEntries.push({ type, message, timestamp: new Date().toISOString() })
    if (this.hasTraceLogTarget) {
      const entryEl = document.createElement('div')
      entryEl.className = `trace-entry ${type}`
      entryEl.innerHTML = `<span class="trace-type">${type}</span><span class="trace-message">${message}</span>`
      this.traceLogTarget.querySelector('.trace-entries')?.appendChild(entryEl)
      const container = this.traceLogTarget.querySelector('.trace-entries')
      if (container) container.scrollTop = container.scrollHeight
    }
  }

  // ==================== Animation ====================

  typeText(input, text, callback) {
    let i = input.value.length
    const parent = input.closest('.form-input') || input
    parent.classList.add('typing')
    const baseDelay = 60

    const typeChar = () => {
      if (this.isPaused || this.userHasTakenOver) {
        this.animationTimer = setTimeout(typeChar, 100)
        return
      }
      if (i < text.length) {
        input.value = text.substring(0, i + 1)
        i++
        this.animationTimer = setTimeout(typeChar, (baseDelay + Math.random() * 40) / this.playbackSpeed)
      } else {
        parent.classList.remove('typing')
        this.animationTimer = setTimeout(callback, 300 / this.playbackSpeed)
      }
    }
    typeChar()
  }

  updateActionList() {
    if (!this.hasActionListTarget) return
    this.actionListTarget.innerHTML = this.actions.map((action, idx) => `
      <div class="action-item ${action.status}" data-action="click->session-replay#jumpToAction" data-step="${idx}" style="cursor: pointer;">
        <span class="action-icon"><i class="fa-solid ${this.getActionIcon(action.type)}"></i></span>
        <span class="action-text">${action.text}</span>
        <span class="action-status">
          ${action.status === 'completed' ? '<i class="fa-solid fa-check"></i>' : ''}
          ${action.status === 'active' ? '<i class="fa-solid fa-play"></i>' : ''}
        </span>
      </div>
    `).join('')
  }

  getActionIcon(type) {
    return { navigate: 'fa-globe', snapshot: 'fa-camera', type: 'fa-keyboard', click: 'fa-hand-pointer', scroll: 'fa-arrow-down' }[type] || 'fa-circle'
  }

  updateTimeline(percent) {
    if (this.hasTimelineProgressTarget) this.timelineProgressTarget.style.width = `${percent}%`
    if (this.hasPlayheadTarget) this.playheadTarget.style.left = `${percent}%`
  }

  updateStepCounter() {
    if (this.hasStepCounterTarget) {
      this.stepCounterTarget.textContent = this.userHasTakenOver ? 'Your session' : `Step ${this.currentStep + 1}/${this.actions.length}`
    }
  }

  showHandoffPrompt() {
    if (!this.handoffEnabledValue) return
    this.isPlaying = false
    this.updatePlayPauseIcon()
    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'flex'
    }
  }

  runAnimation() {
    if (this.demoModeValue === "newsletter") {
      this.runNewsletterAnimation()
    } else {
      this.runCheckoutAnimation()
    }
  }

  runNewsletterAnimation() {
    // Reset to initial state - show hero section
    if (this.hasDemoPageTarget) this.demoPageTarget.style.transform = ''
    if (this.hasDemoEmailTarget) {
      this.demoEmailTarget.value = ''
      this.demoEmailTarget.classList.remove('typing')
    }

    // Start at step 0 - all pending
    this.actions.forEach((action, idx) => action.status = 'pending')
    this.currentStep = 0
    this.updateActionList()
    this.updateTimeline(5)
    this.updateStepCounter()
    this.updateSnapshotMarkers()

    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }
    if (this.hasCursorTarget) {
      this.cursorTarget.className = 'agent-cursor at-hero'
      this.cursorTarget.classList.remove('hidden')
    }

    // Longer delays for better viewing
    const d = () => 1500 / this.playbackSpeed
    const shortD = () => 1000 / this.playbackSpeed

    // Step 0: navigate - mark as active then completed
    this.actions[0].status = 'active'
    this.updateActionList()

    this.animationTimer = setTimeout(() => {
      if (this.isPaused || this.userHasTakenOver) { this.animationTimer = setTimeout(() => this.runNewsletterAnimation(), 100); return }

      this.actions[0].status = 'completed'
      this.currentStep = 1
      this.actions[1].status = 'active'
      this.updateActionList()
      this.updateTimeline(15)
      this.updateStepCounter()

      // Step 1: snapshot - show hero section longer
      this.animationTimer = setTimeout(() => {
        if (this.isPaused || this.userHasTakenOver) return

        this.actions[1].status = 'completed'
        this.currentStep = 2
        this.actions[2].status = 'active'
        this.updateActionList()
        this.updateTimeline(35)
        this.updateStepCounter()
        this.updateSnapshotMarkers()

        // Step 2: scroll to features
        this.animationTimer = setTimeout(() => {
          if (this.isPaused || this.userHasTakenOver) return

          if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor at-features'
          if (this.hasDemoPageTarget) this.demoPageTarget.style.transform = 'translateY(-130px)'

          this.animationTimer = setTimeout(() => {
            this.actions[2].status = 'completed'
            this.currentStep = 3
            this.actions[3].status = 'active'
            this.updateActionList()
            this.updateTimeline(55)
            this.updateStepCounter()
            this.updateSnapshotMarkers()

            // Step 3: scroll to newsletter
            this.animationTimer = setTimeout(() => {
              if (this.isPaused || this.userHasTakenOver) return

              if (this.hasDemoPageTarget) this.demoPageTarget.style.transform = 'translateY(-260px)'
              if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor at-email'

              this.animationTimer = setTimeout(() => {
                this.actions[3].status = 'completed'
                this.currentStep = 4
                this.updateActionList()
                this.updateTimeline(75)
                this.updateStepCounter()
                this.updateSnapshotMarkers()

                // Handoff check at step 4
                if (this.handoffEnabledValue && this.currentStep === this.handoffStepValue) {
                  this.actions[4].status = 'active'
                  this.updateActionList()
                  this.animationTimer = setTimeout(() => this.showHandoffPrompt(), shortD())
                  return
                }
                this.continueNewsletterAnimation()
              }, d())
            }, shortD())
          }, d())
        }, shortD())
      }, d())
    }, d())
  }

  continueNewsletterAnimation() {
    this.actions[4].status = 'active'
    this.updateActionList()
    if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor at-email'

    this.animationTimer = setTimeout(() => {
      this.actions[4].status = 'completed'
      this.currentStep = 5
      this.actions[5].status = 'active'
      this.updateActionList()
      this.updateTimeline(95)
      this.updateStepCounter()

      if (this.hasDemoEmailTarget) {
        this.typeText(this.demoEmailTarget, 'you@example.com', () => {
          this.actions[5].status = 'completed'
          this.updateActionList()
          this.updateSnapshotMarkers()
          if (this.hasCursorTarget) this.cursorTarget.classList.add('hidden')

          this.animationTimer = setTimeout(() => {
            if (this.hasCursorTarget) this.cursorTarget.classList.remove('hidden')
            if (!this.userHasTakenOver && this.isPlaying) this.runAnimation()
          }, 3000 / this.playbackSpeed)
        })
      }
    }, 400 / this.playbackSpeed)
  }

  runCheckoutAnimation() {
    if (this.fields) {
      this.fields.forEach(f => {
        const input = this[`${f.target}Target`]
        if (input) {
          input.value = ''
          input.closest('.form-input')?.classList.remove('typing')
          input.disabled = true
          input.classList.remove('user-editable')
        }
      })
    }
    this.actions.forEach((action, idx) => action.status = idx < 2 ? 'completed' : 'pending')
    this.currentStep = 2
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
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }

    let fieldIndex = 0
    const nextField = () => {
      if (this.isPaused || this.userHasTakenOver) { this.animationTimer = setTimeout(nextField, 100); return }
      if (this.handoffEnabledValue && this.currentStep === this.handoffStepValue) { this.showHandoffPrompt(); return }

      if (fieldIndex < this.fields.length) {
        const field = this.fields[fieldIndex]
        const input = this[`${field.target}Target`]
        if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor ' + field.position
        this.actions[this.currentStep].status = 'active'
        this.updateActionList()
        this.updateTimeline(this.stepToPercent(this.currentStep))
        this.updateStepCounter()

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
        }, 400 / this.playbackSpeed)
      } else {
        if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor at-pay'
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
              this.updateSnapshotMarkers()
              if (this.hasCursorTarget) this.cursorTarget.classList.add('hidden')

              this.animationTimer = setTimeout(() => {
                if (this.hasCursorTarget) this.cursorTarget.classList.remove('hidden')
                if (!this.userHasTakenOver && this.isPlaying) this.runAnimation()
              }, 2500 / this.playbackSpeed)
            }, 1000 / this.playbackSpeed)
          }
        }, 500 / this.playbackSpeed)
      }
    }

    if (this.hasCursorTarget) {
      this.cursorTarget.className = 'agent-cursor at-card'
      this.cursorTarget.classList.remove('hidden')
    }
    this.animationTimer = setTimeout(nextField, 600 / this.playbackSpeed)
  }
}
