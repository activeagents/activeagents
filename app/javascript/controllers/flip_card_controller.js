import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Check if touch device or mobile viewport
    this.isTouchDevice = this.checkTouchDevice()
  }

  checkTouchDevice() {
    return (
      "ontouchstart" in window ||
      navigator.maxTouchPoints > 0 ||
      window.matchMedia("(max-width: 767px)").matches
    )
  }

  toggle(event) {
    // Only handle taps on mobile/touch devices
    if (!this.checkTouchDevice()) return

    // Don't flip back if clicking the docs link when flipped
    const isFlipped = this.element.classList.contains("flipped")
    const clickedDocsLink = event.target.closest(".docs-link")

    if (isFlipped && clickedDocsLink) {
      // Let the link work normally
      return
    }

    // Toggle the flip
    this.element.classList.toggle("flipped")
  }

  keyToggle(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      this.element.classList.toggle("flipped")
    }
  }
}
