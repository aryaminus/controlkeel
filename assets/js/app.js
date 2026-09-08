// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const Hooks = {}

Hooks.FlashTimeout = {
  mounted() {
    this.hideTimer = setTimeout(() => {
      const kind = this.el.dataset.flashKind
      this.pushEventTo(this.el, "lv:clear-flash", {key: kind})
      this.el.classList.add("opacity-0", "-translate-y-2")
      this.el.style.transition = "opacity 300ms ease, transform 300ms ease"
      setTimeout(() => this.el.classList.add("hidden"), 320)
    }, this.el.dataset.flashKind === "error" ? 10000 : 6000)
  },
  destroyed() {
    clearTimeout(this.hideTimer)
  }
}

Hooks.SidebarNav = {
  mounted() {
    this.restoreScroll()
    this.el.addEventListener("scroll", () => {
      sessionStorage.setItem("sidebar-nav-scroll", this.el.scrollTop)
    }, {passive: true})
    this.el.addEventListener("click", event => {
      const button = event.target.closest("[data-sidebar-toggle]")
      if (!button) return
      this.toggle(button)
    })
    this.applyExpanded()
  },
  updated() {
    this.applyExpanded()
  },
  toggle(button) {
    const collapseId = button.getAttribute("aria-controls")
    const collapse = document.getElementById(collapseId)
    if (!collapse) return
    const expanded = collapse.classList.toggle("hidden") === false
    const chevron = document.getElementById(collapseId.replace("sidebar-collapse-", "sidebar-chevron-"))
    if (chevron) chevron.classList.toggle("rotate-90", expanded)
    button.setAttribute("aria-expanded", String(expanded))
    sessionStorage.setItem(`sidebar-nav-expanded:${collapseId}`, expanded ? "1" : "0")
  },
  applyExpanded() {
    this.el.querySelectorAll("[data-sidebar-toggle]").forEach(button => {
      const collapseId = button.getAttribute("aria-controls")
      const stored = sessionStorage.getItem(`sidebar-nav-expanded:${collapseId}`)
      if (stored === null) return
      const expanded = stored === "1"
      const collapse = document.getElementById(collapseId)
      if (!collapse) return
      collapse.classList.toggle("hidden", !expanded)
      const chevron = document.getElementById(collapseId.replace("sidebar-collapse-", "sidebar-chevron-"))
      if (chevron) chevron.classList.toggle("rotate-90", expanded)
      button.setAttribute("aria-expanded", String(expanded))
    })
  },
  restoreScroll() {
    const saved = sessionStorage.getItem("sidebar-nav-scroll")
    if (saved === null) return
    const position = parseInt(saved, 10)
    if (this.el.scrollTop === position) return
    if (this.el.scrollHeight <= this.el.clientHeight) return
    this.el.scrollTop = position
  }
}

Hooks.ContextSwitcher = {
  mounted() {
    this.observer = new MutationObserver(() => this.maybePlace())
    this.observer.observe(this.el, {attributes: true, subtree: true, attributeFilter: ["class"]})
    window.addEventListener("resize", () => this.maybePlace())
  },
  updated() {
    this.maybePlace()
  },
  destroyed() {
    this.observer.disconnect()
  },
  maybePlace() {
    const popover = this.el.querySelector("[data-context-switcher-popover]")
    if (!popover || popover.classList.contains("hidden")) return
    const button = this.el.querySelector("[data-context-switcher-toggle]")
    const rect = button ? button.getBoundingClientRect() : null
    // w-72 popover (288px) + 8px gap; falls back to below the button.
    const fitsRight = rect
      ? window.innerWidth - rect.right >= 296
      : window.innerWidth >= 640
    popover.classList.toggle("context-switcher-right", fitsRight)
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())
window.addEventListener("phx:copy-to-clipboard", async ({detail}) => {
  const text = detail?.text

  if (!text || !navigator.clipboard?.writeText) {
    return
  }

  try {
    await navigator.clipboard.writeText(text)
  } catch (_error) {
    // Clipboard failures should not break the LiveView session.
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency testing:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
