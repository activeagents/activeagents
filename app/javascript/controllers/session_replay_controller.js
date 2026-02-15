import { Controller } from "@hotwired/stimulus"

// Session Replay Controller
// Handles user interaction mode for the checkout form preview
export default class extends Controller {
  static targets = ["viewport", "cursor", "hint", "cardInput", "expiryInput", "cvcInput", "payButton"]

  connect() {
    this.isUserMode = false
  }

  pause() {
    if (!this.hasViewportTarget) return

    this.isUserMode = true
    this.viewportTarget.classList.add('user-mode')

    // Focus the card input when entering user mode
    if (this.hasCardInputTarget) {
      setTimeout(() => this.cardInputTarget.focus(), 100)
    }
  }

  resume() {
    if (!this.hasViewportTarget) return

    this.isUserMode = false
    this.viewportTarget.classList.remove('user-mode')

    // Clear inputs on leave so animation shows properly
    if (this.hasCardInputTarget) this.cardInputTarget.value = ''
    if (this.hasExpiryInputTarget) this.expiryInputTarget.value = ''
    if (this.hasCvcInputTarget) this.cvcInputTarget.value = ''

    // Blur any focused inputs
    document.activeElement?.blur()

    // Reset pay button if it was modified
    if (this.hasPayButtonTarget) {
      this.payButtonTarget.textContent = 'Pay $49.00'
      this.payButtonTarget.style.background = ''
      this.payButtonTarget.style.opacity = ''
    }
  }

  pay(event) {
    if (!this.isUserMode) return

    event.preventDefault()

    if (!this.hasPayButtonTarget) return

    const btn = this.payButtonTarget
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
