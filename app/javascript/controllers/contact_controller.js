import { Controller } from "@hotwired/stimulus"

// Contact Controller
// Submits consulting/services inquiries to /leads without a page reload.
export default class extends Controller {
  static targets = [
    "form", "name", "email", "company", "serviceType", "message",
    "submit", "submitText", "submitLoading", "response"
  ]

  connect() {
    // Mounted on the container so the response element is in scope; the
    // submit event bubbles up from the form inside it.
    this.element.addEventListener("submit", this.handleSubmit.bind(this))

    // Service cards link to #contact-advisory, #contact-workshop, etc. Catch
    // those so the right option is preselected when the form is reached.
    this.onHashChange = this.applyHash.bind(this)
    window.addEventListener("hashchange", this.onHashChange)
    this.applyHash()
  }

  disconnect() {
    window.removeEventListener("hashchange", this.onHashChange)
  }

  applyHash() {
    const match = window.location.hash.match(/^#contact-(\w+)$/)
    if (!match || !this.hasServiceTypeTarget) return

    const service = match[1]
    const option = Array.from(this.serviceTypeTarget.options).find((o) => o.value === service)
    if (option) this.serviceTypeTarget.value = service

    this.element.closest("section")?.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  async handleSubmit(event) {
    event.preventDefault()

    const name = this.nameTarget.value.trim()
    const email = this.emailTarget.value.trim()

    if (!name) {
      this.showResponse("Please enter your name.", "error")
      return
    }
    if (!email || !this.isValidEmail(email)) {
      this.showResponse("Please enter a valid email address.", "error")
      return
    }

    this.setLoading(true)
    this.clearResponse()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const response = await fetch("/leads", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({
          name: name,
          email: email,
          company: this.hasCompanyTarget ? this.companyTarget.value.trim() : "",
          service_type: this.hasServiceTypeTarget ? this.serviceTypeTarget.value : "general",
          message: this.hasMessageTarget ? this.messageTarget.value.trim() : "",
          source: "landing_contact"
        })
      })

      const data = await response.json()

      if (response.ok && data.success) {
        this.showResponse(data.message || "Thanks — we'll be in touch within one business day.", "success")
        this.formTarget.reset()
      } else {
        this.showResponse(data.error || "Something went wrong. Please try again.", "error")
      }
    } catch (error) {
      console.error("Contact form error:", error)
      this.showResponse("Connection error. Please try again, or email consulting@activeagents.ai.", "error")
    } finally {
      this.setLoading(false)
    }
  }

  setLoading(isLoading) {
    if (this.hasSubmitTarget) this.submitTarget.disabled = isLoading
    if (this.hasSubmitTextTarget) this.submitTextTarget.style.display = isLoading ? "none" : "inline"
    if (this.hasSubmitLoadingTarget) this.submitLoadingTarget.style.display = isLoading ? "inline" : "none"
  }

  showResponse(message, type) {
    if (this.hasResponseTarget) {
      this.responseTarget.innerHTML = `<i class="fa-solid fa-${type === "success" ? "check" : "exclamation-circle"}"></i> ${message}`
      this.responseTarget.className = `contact-response ${type}`
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
