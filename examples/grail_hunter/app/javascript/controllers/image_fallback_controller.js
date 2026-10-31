import { Controller } from "@hotwired/stimulus"

// Swaps a listing picture for its category tile when the marketplace's
// thumbnail no longer loads: listings expire, hosts rate-limit hotlinks, and a
// broken image is worse than a placeholder.
export default class extends Controller {
  static values = { src: String }

  replace(event) {
    const image = event.target
    if (image.dataset.fallbackApplied || !this.srcValue) return
    image.dataset.fallbackApplied = "true"
    image.src = this.srcValue
  }
}
