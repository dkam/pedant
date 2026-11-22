import { Controller } from "@hotwired/stimulus"

// System, light or dark (ADR 0028).
//
// The choice is this browser's, kept in localStorage: a phone and a laptop can
// differ, and the server never sees it. "System" is the absence of a choice.
// The stylesheet does the rest: <html> has color-scheme "light dark" until
// data-theme pins it, and each colour role picks its value with light-dark(),
// so following the system, even when it changes at sunset, needs no script.
//
// The layout's head script applies a stored choice before the first paint;
// this only changes it, and marks which button is pressed.
export default class extends Controller {
  static targets = ["option"]
  static storageKey = "pedant:theme"

  connect() {
    this.mark()
  }

  choose({ params: { value } }) {
    const pinned = value === "light" || value === "dark"

    try {
      if (pinned) localStorage.setItem(this.constructor.storageKey, value)
      else localStorage.removeItem(this.constructor.storageKey)
    } catch (e) {
      // Storage is off: the theme still changes, until the next full load.
    }

    if (pinned) document.documentElement.dataset.theme = value
    else delete document.documentElement.dataset.theme

    this.mark()
  }

  mark() {
    const current = document.documentElement.dataset.theme || "system"

    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", option.dataset.themeValueParam === current)
    })
  }
}
