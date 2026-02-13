import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    threshold: { type: Number, default: 0.05 },
    rootMargin: { type: String, default: "50px 0px 0px 0px" }
  }

  connect() {
    // Check if element is already in viewport on page load
    if (this.isInViewport()) {
      this.element.classList.add("visible")
      return
    }

    this.observer = new IntersectionObserver(
      (entries) => this.handleIntersection(entries),
      {
        threshold: this.thresholdValue,
        rootMargin: this.rootMarginValue
      }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  isInViewport() {
    const rect = this.element.getBoundingClientRect()
    return (
      rect.top < window.innerHeight &&
      rect.bottom > 0 &&
      rect.left < window.innerWidth &&
      rect.right > 0
    )
  }

  handleIntersection(entries) {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        this.element.classList.add("visible")
        // Unobserve after animating once
        this.observer.unobserve(this.element)
      }
    })
  }
}
