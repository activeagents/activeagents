import { Controller } from "@hotwired/stimulus"

// Signup Controller
// Handles user registration with database registration + email verification
export default class extends Controller {
  static targets = ["form", "email", "submit", "submitText", "submitLoading", "response"]
  // "source" tags where the signup came from; "responseClass" lets a section
  // reuse this controller with its own styling; "redirect" is false for the
  // newsletter, where a subscriber should stay on the page rather than being
  // sent into account verification. "successMessage" matches that intent.
  static values = {
    source: String,
    responseClass: { type: String, default: "signup-response" },
    redirect: { type: Boolean, default: true },
    successMessage: { type: String, default: "Check your email to verify your account!" }
  }

  connect() {
    // Mounted on the container so the response element is in scope; the
    // submit event bubbles up from the form inside it.
    this.element.addEventListener("submit", this.handleSubmit.bind(this))
  }

  async handleSubmit(event) {
    event.preventDefault()

    const email = this.emailTarget.value.trim()
    if (!email || !this.isValidEmail(email)) {
      this.showResponse("Please enter a valid email address.", "error")
      return
    }

    // Show loading state
    this.setLoading(true)
    this.clearResponse()

    try {
      const registrationResult = await this.registerUser(email)

      if (registrationResult.success) {
        this.showResponse(this.successMessageValue, "success")

        if (this.redirectValue) {
          setTimeout(() => {
            window.location.href = registrationResult.redirect_url || "/pending_verification"
          }, 1500)
        } else {
          if (this.hasFormTarget) this.formTarget.reset()
          this.setLoading(false)
        }
      } else {
        this.showResponse(registrationResult.error || "Registration failed. Please try again.", "error")
        this.setLoading(false)
      }
    } catch (error) {
      console.error("Signup error:", error)
      this.showResponse("An error occurred. Please try again.", "error")
      this.setLoading(false)
    }
  }

  async registerUser(email) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch("/registration", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({
        email_address: email,
        source: this.sourceValue || undefined
      })
    })

    const data = await response.json()

    if (response.ok) {
      return { success: true, redirect_url: data.redirect_url }
    } else {
      return { success: false, error: data.error || data.errors?.join(", ") }
    }
  }

  setLoading(isLoading) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = isLoading
    }
    if (this.hasSubmitTextTarget) {
      this.submitTextTarget.style.display = isLoading ? "none" : "inline"
    }
    if (this.hasSubmitLoadingTarget) {
      this.submitLoadingTarget.style.display = isLoading ? "inline" : "none"
    }
  }

  showResponse(message, type) {
    if (this.hasResponseTarget) {
      this.responseTarget.innerHTML = `<i class="fa-solid fa-${type === "success" ? "check" : "exclamation-circle"}"></i> ${message}`
      this.responseTarget.className = `${this.responseClassValue} ${type}`
      this.responseTarget.style.display = "block"
    }
  }

  clearResponse() {
    if (this.hasResponseTarget) {
      this.responseTarget.innerHTML = ""
      this.responseTarget.style.display = "none"
    }
  }

  isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  }
}
