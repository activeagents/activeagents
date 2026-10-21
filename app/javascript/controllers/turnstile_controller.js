import { Controller } from "@hotwired/stimulus"

// The loader's URL without its query, to find its script element.
const LOADER_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js"

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
    this.stopWaiting()
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

  // Runs `callback` once window.turnstile exists. The loader is an async
  // script in the head: it has usually run before this controller connects
  // (render at once), but when it is still in flight the script element's
  // load event, which fires after the script has executed, says when. No
  // global onload callback is involved, so the loader is included without
  // one and there is nothing for it to look for before any controller runs.
  whenReady(callback) {
    if (window.turnstile) return callback()
    const loader = document.querySelector(`script[src^="${LOADER_URL}"]`)
    if (!loader) return
    this.loader = loader
    this.onLoaderLoad = () => {
      this.stopWaiting()
      callback()
    }
    loader.addEventListener("load", this.onLoaderLoad)
  }

  // A controller that disconnects before the loader has run must not render
  // into its detached element later.
  stopWaiting() {
    if (this.loader && this.onLoaderLoad) this.loader.removeEventListener("load", this.onLoaderLoad)
    this.loader = null
    this.onLoaderLoad = null
  }
}
