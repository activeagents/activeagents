import { Controller } from "@hotwired/stimulus"

// Reloads the page while a hunt is running, so the run's status, findings
// and trace appear without a manual refresh. Attached only when a run is
// in progress (see hunts/show), so an idle page never polls.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => Turbo.visit(window.location.href, { action: "replace" }), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
