import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.applyTheme(this.getPreferredTheme())

    // Listen for system preference changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
      if (!this.hasStoredPreference()) {
        this.applyTheme(e.matches ? 'dark' : 'light')
      }
    })
  }

  toggle() {
    const currentTheme = document.documentElement.classList.contains('theme-dark') ? 'dark' : 'light'
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark'
    this.setTheme(newTheme)
  }

  setTheme(theme) {
    localStorage.setItem('theme', theme)
    this.applyTheme(theme)
  }

  applyTheme(theme) {
    if (theme === 'dark') {
      document.documentElement.classList.add('theme-dark')
      document.documentElement.classList.remove('theme-light')
    } else {
      document.documentElement.classList.add('theme-light')
      document.documentElement.classList.remove('theme-dark')
    }
    // CSS handles the sunglasses lens transition automatically
  }

  getPreferredTheme() {
    const stored = localStorage.getItem('theme')
    if (stored) return stored

    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  }

  hasStoredPreference() {
    return localStorage.getItem('theme') !== null
  }
}
