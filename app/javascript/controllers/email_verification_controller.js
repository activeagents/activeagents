import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

// Email Verification Controller
// Subscribes to ActionCable to detect when email is verified
// and automatically redirects user to complete profile page
export default class extends Controller {
  static values = { userId: Number }

  connect() {
    if (!this.userIdValue) {
      console.warn("[EmailVerification] No user ID provided")
      return
    }

    this.cable = createConsumer()
    this.subscription = this.cable.subscriptions.create(
      { channel: "EmailVerificationChannel" },
      {
        connected: () => {
          console.log("[EmailVerification] Connected to channel")
        },
        disconnected: () => {
          console.log("[EmailVerification] Disconnected from channel")
        },
        received: (data) => {
          console.log("[EmailVerification] Received:", data)
          if (data.type === "email_verified" && data.redirect_to) {
            this.handleVerified(data.redirect_to)
          }
        },
        rejected: () => {
          console.warn("[EmailVerification] Subscription rejected")
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  handleVerified(redirectTo) {
    // Show a brief success message before redirecting
    const heading = this.element.querySelector("h2")
    if (heading) {
      heading.textContent = "Email verified!"
    }

    const icon = this.element.querySelector(".fa-envelope")
    if (icon) {
      icon.classList.remove("fa-envelope")
      icon.classList.add("fa-check")
    }

    // Redirect after a short delay for user feedback
    setTimeout(() => {
      window.location.href = redirectTo
    }, 1000)
  }
}
