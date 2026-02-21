import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count"]
  static values = { repo: String }

  connect() {
    this.fetchStarCount()
  }

  async fetchStarCount() {
    try {
      const response = await fetch(`https://api.github.com/repos/${this.repoValue}`)
      if (!response.ok) return
      const data = await response.json()
      const count = data.stargazers_count
      this.countTarget.textContent = this.formatCount(count)
    } catch {
      // Keep the default text on failure
    }
  }

  formatCount(count) {
    if (count >= 1000) {
      return `${(count / 1000).toFixed(1).replace(/\.0$/, "")}k`
    }
    return count.toString()
  }
}
