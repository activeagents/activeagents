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
    "demoPage", "demoEmail", "demoSubscribe", "addressBar",
    "demoForm", "demoResponse",
    "landerIframe", "iframeContainer"
  ]

  static values = {
    recordingId: Number,
    handoffEnabled: { type: Boolean, default: true },
    handoffStep: { type: Number, default: 4 },
    demoMode: { type: String, default: "newsletter" },
    landerUrl: { type: String, default: "" }
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
    this.userSessionId = null // Track the user's session recording ID

    // Setup based on demo mode
    if (this.demoModeValue === "iframe") {
      this.setupIframeDemo()
    } else if (this.demoModeValue === "newsletter") {
      this.setupNewsletterDemo()
    } else {
      this.setupCheckoutDemo()
    }

    this.updateActionList()
    this.updatePlayPauseIcon()

    setTimeout(() => this.runAnimation(), 800)
  }

  setupIframeDemo() {
    // Iframe mode - shows real lander with agent cursor overlay
    // Scroll positions are in original page pixels, converted to scaled offset via scrollIframeTo()
    // Scale factor is 0.35, viewport ~500px, so visible area is ~1428px of original page
    // Newsletter section "Stay up to date" needs to show the form input centered
    // Newsletter header is at ~6645px, email input at ~6841px in iframe content
    // With scale 0.35 and ~500px viewport, visible area is ~1428px of original
    // y=6500 shows header at ~145px from top, email input at ~341px - well centered
    this.iframeScale = 0.35
    this.iframeScrollPositions = [
      { y: 0 },      // Step 0-1: Hero
      { y: 0 },      // Step 1: Still at hero (snapshot)
      { y: 1200 },   // Step 2: Scroll to features
      { y: 6500 },   // Step 3: Scroll to newsletter - shows header + email input centered
      { y: 6500 },   // Step 4: Click email (still at newsletter, form visible)
      { y: 6500 },   // Step 5: Type email (still at newsletter)
    ]

    // Cursor CSS classes for each step
    this.iframeCursorClasses = [
      'iframe-hero',       // Step 0: Navigate
      'iframe-hero',       // Step 1: Snapshot
      'iframe-scrolling',  // Step 2: Scrolling
      'iframe-newsletter', // Step 3: At newsletter
      'iframe-email',      // Step 4: Click email
      'iframe-subscribe',  // Step 5: Type & subscribe
    ]

    this.actions = [
      { type: 'navigate', text: 'navigate', status: 'completed' },
      { type: 'snapshot', text: 'snapshot', status: 'completed' },
      { type: 'scroll', text: 'scroll down', status: 'pending' },
      { type: 'scroll', text: 'scroll to newsletter', status: 'pending' },
      { type: 'click', text: 'click email', status: 'pending' },
      { type: 'type', text: 'type email', status: 'pending' },
    ]
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

    if (this.demoModeValue === "iframe") {
      this.jumpToIframeStep(targetStep)
    } else if (this.demoModeValue === "newsletter") {
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

  jumpToIframeStep(targetStep) {
    // Scroll the iframe content to simulate agent scrolling by moving iframe position
    if (this.hasLanderIframeTarget && this.iframeScrollPositions) {
      const scrollPos = this.iframeScrollPositions[Math.min(targetStep, this.iframeScrollPositions.length - 1)]
      this.scrollIframeTo(scrollPos.y)
    }

    // Position the cursor using CSS classes
    if (this.hasCursorTarget && this.iframeCursorClasses) {
      // Remove all iframe cursor classes
      this.cursorTarget.className = 'agent-cursor'
      // Add the class for current step
      const cursorClass = this.iframeCursorClasses[Math.min(targetStep, this.iframeCursorClasses.length - 1)]
      this.cursorTarget.classList.add(cursorClass)
      this.cursorTarget.classList.remove('hidden')
    }

    // Update action statuses
    this.actions.forEach((action, idx) => {
      action.status = idx < targetStep ? 'completed' : idx === targetStep ? 'active' : 'pending'
    })

    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle recording"></i> <span>REC</span>'
      this.cassetteBadgeTarget.classList.remove('live')
    }
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

  // Take over the session - redirect to signup section
  takeOverSignup() {
    this.userHasTakenOver = true
    this.isPlaying = false
    this.clearTimers()

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Hide the agent cursor
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.add('hidden')
    }

    // Update cassette badge to show LIVE (recording user interactions)
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle"></i> <span>LIVE</span>'
      this.cassetteBadgeTarget.classList.add('live')
    }

    // Start user session recording in database
    this.startUserSessionRecording()

    // Add trace entry
    this.addTraceEntry('handoff', 'User took over session')

    // Scroll to signup section on the main page
    const signupSection = document.querySelector('#signup')
    if (signupSection) {
      signupSection.scrollIntoView({ behavior: 'smooth', block: 'center' })
      // Focus the email input after scrolling
      setTimeout(() => {
        const emailInput = signupSection.querySelector('input[type="email"]')
        if (emailInput) {
          emailInput.focus()
          this.recordUserAction('focus', '#signup input[type="email"]', 'Focused signup email input')
        }
      }, 800)

      // Track signup form interactions
      this.startSignupInteractionRecording(signupSection)
    } else {
      // Fallback to registration page if no signup section
      window.location.href = '/registration/new'
    }

    // Show trace log
    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'block'
    }

    this.updatePlayPauseIcon()
    this.updateStepCounter()
  }

  // Record user interactions with the signup form
  startSignupInteractionRecording(signupSection) {
    const signupForm = signupSection.querySelector('#signup-form, form')
    if (!signupForm) return

    const emailInput = signupForm.querySelector('input[type="email"]')
    if (emailInput) {
      emailInput.addEventListener('input', this.throttle(() => {
        this.recordUserAction('type', '#signup input[type="email"]', 'Typing signup email')
      }, 2000))
      emailInput.addEventListener('focus', () => {
        this.recordUserAction('focus', '#signup input[type="email"]', 'Focused signup email')
      })
    }

    signupForm.addEventListener('submit', (e) => {
      const email = emailInput?.value || ''
      const maskedEmail = email ? email.substring(0, 3) + '***' : 'empty'
      this.recordUserAction('submit', '#signup-form', `Signup submitted: ${maskedEmail}`, { email_provided: !!email })
      this.completeUserSession('signup', true, true)
    })
  }

  // Take over the session - enable user interaction within the demo viewport
  // For iframe mode: enable pointer-events on iframe so user can interact
  // For other modes: scroll to real newsletter section
  takeOverNewsletter() {
    this.userHasTakenOver = true
    this.isPlaying = false
    this.clearTimers()

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Hide the agent cursor
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.add('hidden')
    }

    // Update cassette badge to show LIVE (recording user interactions)
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle"></i> <span>LIVE</span>'
      this.cassetteBadgeTarget.classList.add('live')
    }

    // Start user session recording in database
    this.startUserSessionRecording()

    // Add trace entry
    this.addTraceEntry('handoff', 'User took over session')

    // Handle iframe mode - enable interaction within the iframe
    if (this.demoModeValue === "iframe" && this.hasLanderIframeTarget) {
      // Add class to viewport to enable pointer-events on iframe
      if (this.hasViewportTarget) {
        this.viewportTarget.classList.add('user-controlled')
      }

      // Setup iframe interaction tracking
      this.setupIframeInteractionTracking()

      // Focus the email input inside the iframe after a short delay
      setTimeout(() => {
        try {
          const iframeDoc = this.landerIframeTarget.contentDocument || this.landerIframeTarget.contentWindow.document
          const emailInput = iframeDoc.querySelector('#newsletter input[type="email"], input[type="email"]')
          if (emailInput) {
            emailInput.focus()
            this.recordUserAction('focus', '#newsletter input[type="email"]', 'Focused email input')
          }
        } catch (e) {
          // Cross-origin access might fail, that's ok
          console.log('Could not focus iframe input:', e)
        }
      }, 100)

      // Show trace log
      if (this.hasTraceLogTarget) {
        this.traceLogTarget.style.display = 'block'
      }

      this.updatePlayPauseIcon()
      this.updateStepCounter()
      return
    }

    // For non-iframe modes: scroll to the real newsletter section on the main page
    this.startUserInteractionRecording()

    const newsletterSection = document.querySelector('#newsletter')
    if (newsletterSection) {
      newsletterSection.scrollIntoView({ behavior: 'smooth', block: 'center' })
      // Focus the email input after scrolling
      setTimeout(() => {
        const emailInput = newsletterSection.querySelector('input[type="email"]')
        if (emailInput) {
          emailInput.focus()
          this.recordUserAction('focus', '#newsletter input[type="email"]', 'Focused email input')
        }
      }, 800)
    } else {
      // If no newsletter section, scroll to footer or signup
      window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' })
    }
  }

  // Start a new user session recording in the database
  async startUserSessionRecording() {
    try {
      const response = await fetch('/api/session_recordings/start_user_session', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          page_url: window.location.href,
          step: this.currentStep,
          parent_demo_id: this.recordingIdValue || null
        })
      })

      if (response.ok) {
        const data = await response.json()
        this.userSessionId = data.recording_id
        console.log('User session started:', this.userSessionId)
      } else {
        console.error('Failed to start user session:', response.status)
      }
    } catch (error) {
      console.error('Error starting user session:', error)
    }
  }

  // Record a user action to the database
  async recordUserAction(actionType, selector = null, value = null, metadata = {}) {
    // Always add to trace log
    this.addTraceEntry(actionType, value || selector || actionType)

    // If we have a session, record to database
    if (!this.userSessionId) return

    try {
      await fetch(`/api/session_recordings/${this.userSessionId}/record_action`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          action_type: actionType,
          selector: selector,
          value: value,
          metadata: metadata
        })
      })
    } catch (error) {
      console.error('Error recording action:', error)
    }
  }

  // Complete the user session recording
  async completeUserSession(completionType = 'session_end', emailSubmitted = false, success = false) {
    if (!this.userSessionId) return

    try {
      const response = await fetch(`/api/session_recordings/${this.userSessionId}/complete`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({
          completion_type: completionType,
          email_submitted: emailSubmitted,
          success: success
        })
      })

      if (response.ok) {
        const data = await response.json()
        console.log('User session completed:', data)
      }
    } catch (error) {
      console.error('Error completing session:', error)
    }
  }

  // Setup tracking for interactions within the iframe
  setupIframeInteractionTracking() {
    if (!this.hasLanderIframeTarget) return

    try {
      const iframeDoc = this.landerIframeTarget.contentDocument || this.landerIframeTarget.contentWindow.document

      // Track email input
      const emailInput = iframeDoc.querySelector('#newsletter input[type="email"], input[type="email"]')
      if (emailInput) {
        emailInput.addEventListener('input', this.throttle(() => {
          this.recordUserAction('type', '#newsletter input[type="email"]', 'Typing email')
        }, 2000))
      }

      // Track form submission
      const form = iframeDoc.querySelector('#newsletter-form, form')
      if (form) {
        form.addEventListener('submit', (e) => {
          const email = emailInput?.value || ''
          const maskedEmail = email ? email.substring(0, 3) + '***' : 'empty'
          this.recordUserAction('submit', '#newsletter-form', `Submitted: ${maskedEmail}`, { email_provided: !!email })
          this.completeUserSession('newsletter_signup', true, true)
        })
      }
    } catch (e) {
      console.log('Could not setup iframe tracking:', e)
    }
  }

  // Get CSRF token for API calls
  getCSRFToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }

  // Record user interactions during handoff for agent handback
  startUserInteractionRecording() {
    // Track scroll events
    this.userScrollHandler = () => {
      this.recordUserAction('scroll', null, `${window.scrollY}px`)
    }
    window.addEventListener('scroll', this.throttle(this.userScrollHandler, 2000), { passive: true })

    // Track newsletter form interactions
    const newsletterForm = document.querySelector('#newsletter-form')
    if (newsletterForm) {
      const emailInput = newsletterForm.querySelector('input[type="email"]')
      if (emailInput) {
        emailInput.addEventListener('input', this.throttle(() => {
          this.recordUserAction('type', '#newsletter input[type="email"]', 'Typing email')
        }, 2000))
        emailInput.addEventListener('focus', () => {
          this.recordUserAction('focus', '#newsletter input[type="email"]', 'Focused email')
        })
      }

      newsletterForm.addEventListener('submit', (e) => {
        const email = emailInput?.value || ''
        const maskedEmail = email ? email.substring(0, 3) + '***' : 'empty'
        this.recordUserAction('submit', '#newsletter-form', `Submitted: ${maskedEmail}`, { email_provided: !!email })
        this.completeUserSession('newsletter_signup', true, true)
      })
    }

    // Show trace log to display user actions
    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'block'
    }
  }

  // Throttle helper for scroll events
  throttle(func, limit) {
    let inThrottle
    return function(...args) {
      if (!inThrottle) {
        func.apply(this, args)
        inThrottle = true
        setTimeout(() => inThrottle = false, limit)
      }
    }
  }

  // Enable the demo form for user input (within the demo viewport)
  enableDemoForm() {
    this.userHasTakenOver = true
    this.isPlaying = false
    this.clearTimers()

    if (this.hasHandoffOverlayTarget) {
      this.handoffOverlayTarget.style.display = 'none'
    }

    // Hide the agent cursor
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.add('hidden')
    }

    // Enable the email input and subscribe button within the demo
    if (this.hasDemoEmailTarget) {
      this.demoEmailTarget.removeAttribute('readonly')
      this.demoEmailTarget.value = ''
      this.demoEmailTarget.classList.add('user-editable')
      this.demoEmailTarget.focus()
    }

    if (this.hasDemoSubscribeTarget) {
      this.demoSubscribeTarget.disabled = false
      this.demoSubscribeTarget.classList.add('user-clickable')
    }

    // Update cassette badge to show LIVE
    if (this.hasCassetteBadgeTarget) {
      this.cassetteBadgeTarget.innerHTML = '<i class="fa-solid fa-circle"></i> <span>LIVE</span>'
      this.cassetteBadgeTarget.classList.add('live')
    }

    // Show trace log
    this.addTraceEntry('handoff', 'User took over session')
    if (this.hasTraceLogTarget) {
      this.traceLogTarget.style.display = 'block'
    }

    this.updatePlayPauseIcon()
    this.updateStepCounter()
  }

  // Handle demo newsletter form submission
  submitDemoNewsletter(event) {
    event.preventDefault()
    if (!this.hasDemoEmailTarget) return

    const email = this.demoEmailTarget.value.trim()
    if (!email || !this.isValidEmail(email)) {
      this.showDemoResponse('Please enter a valid email address.', 'error')
      return
    }

    // Show loading state
    const btnText = this.demoSubscribeTarget?.querySelector('.btn-text')
    const btnLoading = this.demoSubscribeTarget?.querySelector('.btn-loading')
    if (btnText) btnText.style.display = 'none'
    if (btnLoading) btnLoading.style.display = 'inline'
    if (this.hasDemoSubscribeTarget) this.demoSubscribeTarget.disabled = true

    this.addTraceEntry('user_action', `Subscribing: ${email}`)

    // Register user (syncs to Loops via background job)
    fetch('/registration', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({ email_address: email, source: 'demo' })
    })
    .then(response => response.json().then(data => ({ ok: response.ok, data })))
    .then(result => {
      this.handleSubscribeResponse(result, email)
    })
    .catch(() => {
      this.handleSubscribeError()
    })
  }

  handleSubscribeResponse(result, email) {
    // Reset button state
    const btnText = this.demoSubscribeTarget?.querySelector('.btn-text')
    const btnLoading = this.demoSubscribeTarget?.querySelector('.btn-loading')
    if (btnText) btnText.style.display = 'inline'
    if (btnLoading) btnLoading.style.display = 'none'

    if (result.ok || result.data.success) {
      this.showDemoResponse('Thanks for subscribing!', 'success')
      this.addTraceEntry('completion', 'Newsletter subscription successful')

      // Complete the remaining steps
      this.actions[4].status = 'completed'
      this.actions[5].status = 'completed'
      this.currentStep = 6
      this.updateActionList()
      this.updateTimeline(100)
      this.updateSnapshotMarkers()

      // Disable the form
      if (this.hasDemoEmailTarget) {
        this.demoEmailTarget.setAttribute('readonly', true)
        this.demoEmailTarget.classList.remove('user-editable')
      }
      if (this.hasDemoSubscribeTarget) {
        this.demoSubscribeTarget.disabled = true
        this.demoSubscribeTarget.classList.remove('user-clickable')
      }
    } else {
      const errorMsg = (result.data.errors && result.data.errors[0]) || 'Subscription failed. Please try again.'
      this.showDemoResponse(errorMsg, 'error')
      this.addTraceEntry('error', errorMsg)
      if (this.hasDemoSubscribeTarget) this.demoSubscribeTarget.disabled = false
    }
  }

  handleSubscribeError() {
    // Reset button state
    const btnText = this.demoSubscribeTarget?.querySelector('.btn-text')
    const btnLoading = this.demoSubscribeTarget?.querySelector('.btn-loading')
    if (btnText) btnText.style.display = 'inline'
    if (btnLoading) btnLoading.style.display = 'none'
    if (this.hasDemoSubscribeTarget) this.demoSubscribeTarget.disabled = false

    this.showDemoResponse('Network error. Please try again.', 'error')
    this.addTraceEntry('error', 'Network error during subscription')
  }

  showDemoResponse(message, type) {
    if (this.hasDemoResponseTarget) {
      this.demoResponseTarget.textContent = message
      this.demoResponseTarget.className = `demo-newsletter-response ${type}`
      this.demoResponseTarget.style.display = 'block'
    }
  }

  isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
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
    if (this.demoModeValue === "iframe") {
      this.runIframeAnimation()
    } else if (this.demoModeValue === "newsletter") {
      this.runNewsletterAnimation()
    } else {
      this.runCheckoutAnimation()
    }
  }

  runIframeAnimation() {
    // Reset to initial state
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

    // Position cursor at hero
    if (this.hasCursorTarget) {
      this.cursorTarget.className = 'agent-cursor iframe-hero'
      this.cursorTarget.classList.remove('hidden')
    }

    // Scroll iframe to top
    this.scrollIframeTo(0)

    const d = () => 1500 / this.playbackSpeed
    const shortD = () => 1000 / this.playbackSpeed

    // Step 0: navigate - mark as active then completed
    this.actions[0].status = 'active'
    this.updateActionList()

    this.animationTimer = setTimeout(() => {
      if (this.isPaused || this.userHasTakenOver) { this.animationTimer = setTimeout(() => this.runIframeAnimation(), 100); return }

      this.actions[0].status = 'completed'
      this.currentStep = 1
      this.actions[1].status = 'active'
      this.updateActionList()
      this.updateTimeline(15)
      this.updateStepCounter()

      // Step 1: snapshot
      this.animationTimer = setTimeout(() => {
        if (this.isPaused || this.userHasTakenOver) return

        this.actions[1].status = 'completed'
        this.currentStep = 2
        this.actions[2].status = 'active'
        this.updateActionList()
        this.updateTimeline(35)
        this.updateStepCounter()
        this.updateSnapshotMarkers()

        // Step 2: scroll down - move cursor and scroll iframe
        this.animationTimer = setTimeout(() => {
          if (this.isPaused || this.userHasTakenOver) return

          if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor iframe-scrolling'
          this.scrollIframeTo(1200)

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

              if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor iframe-newsletter'
              this.scrollIframeTo(6500)

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
                this.continueIframeAnimation()
              }, d())
            }, shortD())
          }, d())
        }, shortD())
      }, d())
    }, d())
  }

  continueIframeAnimation() {
    // Step 4: click email
    this.actions[4].status = 'active'
    this.updateActionList()
    if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor iframe-email'

    this.animationTimer = setTimeout(() => {
      this.actions[4].status = 'completed'
      this.currentStep = 5
      this.actions[5].status = 'active'
      this.updateActionList()
      this.updateTimeline(95)
      this.updateStepCounter()

      // Step 5: type email
      if (this.hasCursorTarget) this.cursorTarget.className = 'agent-cursor iframe-subscribe'

      this.animationTimer = setTimeout(() => {
        this.actions[5].status = 'completed'
        this.updateActionList()
        this.updateSnapshotMarkers()
        if (this.hasCursorTarget) this.cursorTarget.classList.add('hidden')

        // Loop the animation
        this.animationTimer = setTimeout(() => {
          if (this.hasCursorTarget) this.cursorTarget.classList.remove('hidden')
          if (!this.userHasTakenOver && this.isPlaying) this.runAnimation()
        }, 3000 / this.playbackSpeed)
      }, 1500 / this.playbackSpeed)
    }, 800 / this.playbackSpeed)
  }

  scrollIframeTo(y) {
    if (this.hasLanderIframeTarget) {
      // Convert original page coordinates to scaled offset
      // The iframe is scaled to this.iframeScale, so moving it by y * scale
      // shows content from y onwards in the original page
      const scale = this.iframeScale || 0.35
      const offset = -(y * scale)
      this.landerIframeTarget.style.top = `${offset}px`
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
