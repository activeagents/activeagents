import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Check if touch device or mobile viewport
    this.isTouchDevice = this.checkTouchDevice()

    // Store original height and measure back content
    this.originalHeight = this.element.offsetHeight
    this.measureBackHeight()

    // Set up scroll-to-flip on mobile
    if (this.isTouchDevice) {
      this.setupScrollFlip()
    }

    // Set up hover listeners for desktop
    if (!this.isTouchDevice) {
      this.element.addEventListener("mouseenter", () => this.expand())
      this.element.addEventListener("mouseleave", () => this.collapse())
    }
  }

  disconnect() {
    // Clean up observer when controller disconnects
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  measureBackHeight() {
    const back = this.element.querySelector(".flip-card-back")
    if (!back) return

    // Temporarily make back visible to measure
    const inner = this.element.querySelector(".flip-card-inner")
    const originalTransform = inner.style.transform
    inner.style.transform = "rotateY(180deg)"
    back.style.visibility = "hidden"
    back.style.position = "relative"
    back.style.height = "auto"

    this.backHeight = back.scrollHeight + 20 // padding

    // Restore original styles
    back.style.visibility = ""
    back.style.position = ""
    back.style.height = ""
    inner.style.transform = originalTransform
  }

  expand() {
    if (this.backHeight > this.originalHeight) {
      this.element.style.height = `${this.backHeight}px`
    }
  }

  collapse() {
    this.element.style.height = `${this.originalHeight}px`
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
            this.expand()
          } else {
            // Card left the flip zone - flip back
            this.element.classList.remove("flipped")
            this.collapse()
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

    // Toggle the flip and height
    if (isFlipped) {
      this.element.classList.remove("flipped")
      this.collapse()
    } else {
      this.element.classList.add("flipped")
      this.expand()
    }
  }

  keyToggle(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault()
      const isFlipped = this.element.classList.contains("flipped")
      if (isFlipped) {
        this.element.classList.remove("flipped")
        this.collapse()
      } else {
        this.element.classList.add("flipped")
        this.expand()
      }
    }
  }
}
