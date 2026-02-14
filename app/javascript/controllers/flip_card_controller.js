import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Check if touch device or mobile viewport
    this.isTouchDevice = this.checkTouchDevice()

    // Set up scroll-to-flip on mobile
    if (this.isTouchDevice) {
      this.setupScrollFlip()
    }
  }

  disconnect() {
    // Clean up observer when controller disconnects
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  checkTouchDevice() {
    return (
      "ontouchstart" in window ||
      navigator.maxTouchPoints > 0 ||
      window.matchMedia("(max-width: 767px)").matches
    )
  }

  setupScrollFlip() {
    // Flip card when it's centered in viewport
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            // Card is in the "flip zone" - flip it
            this.element.classList.add("flipped")
          } else {
            // Card left the flip zone - flip back
            this.element.classList.remove("flipped")
          }
        })
      },
      {
        // Trigger when card is in the middle 40% of the viewport
        rootMargin: "-30% 0px -30% 0px",
        threshold: 0.5
      }
    )

    this.observer.observe(this.element)
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
