import { Controller } from "@hotwired/stimulus"

// Signup Controller
// Handles user registration with:
// 1. Database registration + email verification
// 2. Mailchimp subscription for newsletter updates
export default class extends Controller {
  static targets = ["email", "submit", "submitText", "submitLoading", "response"]

  connect() {
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
      // Step 1: Register in database with email verification
      const registrationResult = await this.registerUser(email)

      if (registrationResult.success) {
        // Step 2: Subscribe to Mailchimp in parallel (fire and forget)
        this.subscribeToMailchimp(email)

        // Show success and redirect to verification pending page
        this.showResponse("Check your email to verify your account!", "success")

        // Redirect to pending verification after a short delay
        setTimeout(() => {
          window.location.href = registrationResult.redirect_url || "/pending_verification"
        }, 1500)
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
        email_address: email
      })
    })

    const data = await response.json()

    if (response.ok) {
      return { success: true, redirect_url: data.redirect_url }
    } else {
      return { success: false, error: data.error || data.errors?.join(", ") }
    }
  }

  subscribeToMailchimp(email) {
    // Fire-and-forget Mailchimp subscription
    // Uses JSONP to avoid CORS issues
    const callbackName = "mc_signup_" + Date.now()
    const baseUrl = "https://remoteworkera.us7.list-manage.com/subscribe/post-json"
    const params = new URLSearchParams({
      u: "a5e2d973d5bb834e4c2693a3f",
      id: "a1c5e41527",
      f_id: "001d43e4f0",
      EMAIL: email,
      c: callbackName
    })

    window[callbackName] = (response) => {
      delete window[callbackName]
      if (response.result === "success") {
        console.log("Mailchimp subscription successful")
      } else {
        console.log("Mailchimp subscription note:", response.msg)
      }
    }

    const script = document.createElement("script")
    script.src = `${baseUrl}?${params.toString()}`
    script.onerror = () => {
      delete window[callbackName]
      console.log("Mailchimp subscription request failed")
    }
    document.body.appendChild(script)

    // Cleanup after timeout
    setTimeout(() => {
      if (window[callbackName]) {
        delete window[callbackName]
      }
      script.remove()
    }, 5000)
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
      this.responseTarget.className = `signup-response ${type}`
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
