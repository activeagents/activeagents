import { Controller } from "@hotwired/stimulus"

// Renders a Cloudflare Turnstile widget into its element.
//
// The loader is included with ?render=explicit so widgets are rendered here,
// once the script is ready, rather than by a DOM scan at load time: that keeps
// a widget working after Turbo navigations and in forms that appear later.
// The widget writes its token into a hidden input named cf-turnstile-response
// inside the form; the signup and newsletter controllers read it from there.
//
// `turnstile#reset` (also reachable as the "turnstile:reset" event on the
// element) asks for a fresh token after a refused submission, since each
// token is single use.
export default class extends Controller {
  static values = {
    sitekey: String,
    theme: { type: String, default: "auto" },
    appearance: { type: String, default: "interaction-only" }
  }

  connect() {
    this.widgetId = null
    this.element.addEventListener("turnstile:reset", this.reset)
    this.whenReady(() => this.render())
  }

  disconnect() {
    this.element.removeEventListener("turnstile:reset", this.reset)
    if (this.widgetId !== null && window.turnstile) {
      try { window.turnstile.remove(this.widgetId) } catch { /* already gone */ }
    }
    this.widgetId = null
  }

  render() {
    if (this.widgetId !== null || !window.turnstile) return
    this.widgetId = window.turnstile.render(this.element, {
      sitekey: this.sitekeyValue,
      theme: this.themeValue,
      appearance: this.appearanceValue,
      size: "flexible",
      "response-field-name": "cf-turnstile-response"
    })
  }

  reset = () => {
    if (this.widgetId !== null && window.turnstile) window.turnstile.reset(this.widgetId)
  }

  // The api.js loader calls window.onloadTurnstileCallback when it is ready;
  // chain onto it so several widgets on one page all render.
  whenReady(callback) {
    if (window.turnstile) return callback()
    const previous = window.onloadTurnstileCallback
    window.onloadTurnstileCallback = () => {
      if (typeof previous === "function") previous()
      callback()
    }
  }
}
