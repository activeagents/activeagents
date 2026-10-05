import { Controller } from "@hotwired/stimulus"

// Newsletter signup: one email field, posted as JSON to the newsletter
// subscription endpoint. The server sends a confirmation email; the contact
// reaches Resend once the reader confirms.
export default class extends Controller {
  static targets = ["email", "submit", "response"]

  async submit(event) {
    event.preventDefault()

    const email = this.emailTarget.value.trim()
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      this.showResponse("Enter a valid email address.", "error")
      return
    }

    this.setLoading(true)
    this.showResponse("", "")

    try {
      const response = await fetch(this.element.action, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ email_address: email, source: "newsletter" })
      })
      const data = await response.json().catch(() => ({}))

      if (response.ok || data.success) {
        this.showResponse(data.message || "Check your email to confirm your subscription.", "success")
        this.element.reset()
      } else {
        this.showResponse(data.error || "Something went wrong. Please try again.", "error")
      }
    } catch {
      this.showResponse("Connection error. Please try again.", "error")
    } finally {
      this.setLoading(false)
    }
  }

  setLoading(isLoading) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = isLoading
      this.submitTarget.setAttribute("aria-busy", isLoading ? "true" : "false")
    }
  }

  showResponse(message, type) {
    if (!this.hasResponseTarget) return
    const glyph = type === "success" ? "[+] " : type === "error" ? "[!] " : ""
    this.responseTarget.textContent = message ? glyph + message : ""
    this.responseTarget.className = `lp-form-response lp-mono ${type}`.trim()
  }
}
