import { Controller } from "@hotwired/stimulus"

// Session Replay Controller
// Handles agent typing animation for the checkout form preview
export default class extends Controller {
  static targets = ["viewport", "cursor", "card", "expiry", "cvc", "pay"]

  connect() {
    this.isPaused = false
    this.animationTimer = null

    this.fields = [
      { target: 'card', position: 'at-card' },
      { target: 'expiry', position: 'at-expiry' },
      { target: 'cvc', position: 'at-cvc' },
    ]

    // Start animation after a brief delay
    setTimeout(() => this.runAnimation(), 500)
  }

  disconnect() {
    if (this.animationTimer) clearTimeout(this.animationTimer)
  }

  pause() {
    this.isPaused = true
  }

  resume() {
    this.isPaused = false
  }

  hideCursor() {
    this.isPaused = true
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.add('hidden')
    }
  }

  showCursor() {
    this.isPaused = false
    if (this.hasCursorTarget) {
      this.cursorTarget.classList.remove('hidden')
    }
  }

  typeText(input, text, callback) {
    let i = 0
    const parent = input.closest('.form-input')
    parent.classList.add('typing')

    const typeChar = () => {
      if (this.isPaused) {
        this.animationTimer = setTimeout(typeChar, 100)
        return
      }
      if (i < text.length) {
        input.value = text.substring(0, i + 1)
        i++
        this.animationTimer = setTimeout(typeChar, 60 + Math.random() * 40)
      } else {
        parent.classList.remove('typing')
        this.animationTimer = setTimeout(callback, 300)
      }
    }
    typeChar()
  }

  runAnimation() {
    // Reset all fields
    this.fields.forEach(f => {
      const input = this[`${f.target}Target`]
      if (input) {
        input.value = ''
        input.closest('.form-input')?.classList.remove('typing')
      }
    })

    if (this.hasPayTarget) {
      this.payTarget.textContent = 'Pay $49.00'
      this.payTarget.style.background = ''
      this.payTarget.style.opacity = ''
    }

    let fieldIndex = 0

    const nextField = () => {
      if (this.isPaused) {
        this.animationTimer = setTimeout(nextField, 100)
        return
      }

      if (fieldIndex < this.fields.length) {
        const field = this.fields[fieldIndex]
        const input = this[`${field.target}Target`]

        if (this.hasCursorTarget) {
          this.cursorTarget.className = 'agent-cursor ' + field.position
        }

        this.animationTimer = setTimeout(() => {
          if (input) {
            this.typeText(input, input.dataset.typed || '', () => {
              fieldIndex++
              nextField()
            })
          }
        }, 400)
      } else {
        // Move to pay button
        if (this.hasCursorTarget) {
          this.cursorTarget.className = 'agent-cursor at-pay'
        }

        this.animationTimer = setTimeout(() => {
          if (this.hasPayTarget) {
            this.payTarget.textContent = 'Processing...'
            this.payTarget.style.opacity = '0.7'

            this.animationTimer = setTimeout(() => {
              this.payTarget.textContent = 'Payment Successful!'
              this.payTarget.style.background = 'linear-gradient(135deg, #10b981, #059669)'
              this.payTarget.style.opacity = '1'

              if (this.hasCursorTarget) {
                this.cursorTarget.classList.add('hidden')
              }

              // Wait then restart
              this.animationTimer = setTimeout(() => {
                this.payTarget.style.background = ''
                this.payTarget.style.opacity = ''
                if (this.hasCursorTarget) {
                  this.cursorTarget.classList.remove('hidden')
                }
                this.runAnimation()
              }, 2500)
            }, 1000)
          }
        }, 500)
      }
    }

    // Start with cursor at card field
    if (this.hasCursorTarget) {
      this.cursorTarget.className = 'agent-cursor at-card'
    }
    this.animationTimer = setTimeout(nextField, 600)
  }

  pay(event) {
    event.preventDefault()

    if (!this.hasPayTarget) return

    const btn = this.payTarget
    btn.textContent = 'Processing...'
    btn.style.opacity = '0.7'

    setTimeout(() => {
      btn.textContent = 'Payment Successful!'
      btn.style.background = 'linear-gradient(135deg, #10b981, #059669)'
      btn.style.opacity = '1'
    }, 1000)

    setTimeout(() => {
      btn.textContent = 'Pay $49.00'
      btn.style.background = ''
      btn.style.opacity = ''
    }, 3000)
  }
}
