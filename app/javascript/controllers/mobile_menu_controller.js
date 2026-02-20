import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.classList.toggle("open")
    document.body.classList.toggle("nav-open")
  }

  close() {
    this.menuTarget.classList.remove("open")
    document.body.classList.remove("nav-open")
  }
}
