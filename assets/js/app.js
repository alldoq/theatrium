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
import topbar from "topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
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
    window.addEventListener("keyup", e => keyDown = null)
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

// Vue 3 island framework
import { createApp } from "vue"
import { VueIslands, registerVueIsland } from "./islands/registry.js"

export { registerVueIsland }

// Import all islands before mounting so they register themselves first
import "./islands/hello.js"
import "./tiptap_editor.js"
import FormBuilderIsland from "./islands/FormBuilderIsland.vue"
registerVueIsland("FormBuilderIsland", FormBuilderIsland)

function mountIslands() {
  document.querySelectorAll("[data-vue]").forEach((el) => {
    const name = el.dataset.vue
    const component = VueIslands[name]
    if (!component) return
    const props = el.dataset.props ? JSON.parse(el.dataset.props) : {}
    createApp(component, props).mount(el)
  })
}

if (document.readyState === "loading") {
  window.addEventListener("DOMContentLoaded", mountIslands)
} else {
  mountIslands()
}

// ── Topbar search: typeahead dropdown, Enter → full results, ⌘K focus ──────
;(function () {
  function getInput() { return document.getElementById("topbar-search") }

  let dropdown
  let activeIndex = -1
  let currentResults = []
  let debounceTimer

  function ensureDropdown() {
    if (dropdown) return dropdown
    dropdown = document.createElement("div")
    dropdown.id = "topbar-search-dropdown"
    dropdown.className = "atrium-search-dropdown"
    dropdown.style.display = "none"
    document.body.appendChild(dropdown)
    return dropdown
  }

  function typeIcon(type) {
    const icons = {
      announcement: "📣", course: "🎓", event: "📅",
      community: "💬", document: "📄", user: "👤", tool: "🔧"
    }
    return icons[type] || "•"
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
  }

  function render(results, query) {
    const dd = ensureDropdown()
    if (!results.length) {
      dd.innerHTML = `<div class="atrium-search-empty">No matches for "${escapeHtml(query)}"</div>`
    } else {
      dd.innerHTML = results.map((r, i) => `
        <a href="${escapeHtml(r.path)}" class="atrium-search-result" data-index="${i}">
          <span class="atrium-search-icon">${typeIcon(r.type)}</span>
          <span class="atrium-search-body">
            <span class="atrium-search-title">${escapeHtml(r.title)}</span>
            ${r.snippet ? `<span class="atrium-search-snippet">${escapeHtml(r.snippet)}</span>` : ""}
          </span>
          <span class="atrium-search-section">${escapeHtml(r.section)}</span>
        </a>
      `).join("") + `
        <a href="/search?q=${encodeURIComponent(query)}" class="atrium-search-all">
          View all results →
        </a>
      `
    }
    const input = getInput()
    const rect = input.getBoundingClientRect()
    dd.style.position = "fixed"
    dd.style.top = (rect.bottom + 4) + "px"
    dd.style.left = rect.left + "px"
    dd.style.width = rect.width + "px"
    dd.style.display = "block"
    activeIndex = -1
  }

  function hide() {
    if (dropdown) dropdown.style.display = "none"
    activeIndex = -1
  }

  function fetchResults(query) {
    if (query.length < 2) { hide(); return }
    fetch("/search/suggest?q=" + encodeURIComponent(query), { credentials: "same-origin", headers: { "Accept": "application/json" } })
      .then(r => r.json())
      .then(data => {
        currentResults = data.results || []
        render(currentResults, query)
      })
      .catch(() => hide())
  }

  document.addEventListener("keydown", function (e) {
    const input = getInput()
    if (!input) return
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault(); input.focus(); input.select(); return
    }
    if (e.key === "Escape" && document.activeElement === input) {
      input.blur(); hide()
    }
  })

  document.addEventListener("DOMContentLoaded", function () {
    const input = getInput()
    if (!input) return

    input.addEventListener("input", function () {
      clearTimeout(debounceTimer)
      const q = input.value.trim()
      debounceTimer = setTimeout(() => fetchResults(q), 200)
    })

    input.addEventListener("focus", function () {
      const q = input.value.trim()
      if (q.length >= 2) fetchResults(q)
    })

    input.addEventListener("keydown", function (e) {
      const dd = dropdown
      const items = dd ? dd.querySelectorAll(".atrium-search-result") : []
      if (e.key === "ArrowDown" && items.length) {
        e.preventDefault()
        activeIndex = (activeIndex + 1) % items.length
        items.forEach((el, i) => el.classList.toggle("active", i === activeIndex))
        items[activeIndex].scrollIntoView({ block: "nearest" })
      } else if (e.key === "ArrowUp" && items.length) {
        e.preventDefault()
        activeIndex = activeIndex <= 0 ? items.length - 1 : activeIndex - 1
        items.forEach((el, i) => el.classList.toggle("active", i === activeIndex))
        items[activeIndex].scrollIntoView({ block: "nearest" })
      } else if (e.key === "Enter") {
        e.preventDefault()
        if (activeIndex >= 0 && items[activeIndex]) {
          window.location.href = items[activeIndex].getAttribute("href")
        } else {
          const q = input.value.trim()
          if (q.length >= 2) window.location.href = "/search?q=" + encodeURIComponent(q)
        }
      }
    })

    document.addEventListener("click", function (e) {
      if (!input.contains(e.target) && dropdown && !dropdown.contains(e.target)) {
        hide()
      }
    })

    window.addEventListener("resize", hide)
  })
})()



// ── AI chat widget ──────────────────────────────────────────────────────────
;(function () {
  document.addEventListener("DOMContentLoaded", function () {
    const fab = document.getElementById("atrium-ai-fab")
    const panel = document.getElementById("atrium-ai-panel")
    const closeBtn = document.getElementById("atrium-ai-close")
    const form = document.getElementById("atrium-ai-form")
    const input = document.getElementById("atrium-ai-input")
    const messages = document.getElementById("atrium-ai-messages")

    if (!fab || !panel) return

    const history = []

    function open() { panel.hidden = false; setTimeout(() => input && input.focus(), 50) }
    function close() { panel.hidden = true }

    fab.addEventListener("click", () => { panel.hidden ? open() : close() })
    closeBtn.addEventListener("click", close)

    function escapeHtml(s) {
      return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
    }

    function addMessage(role, content, sources) {
      const wrap = document.createElement("div")
      wrap.className = "atrium-ai-msg atrium-ai-msg--" + role
      const bubble = document.createElement("div")
      bubble.className = "atrium-ai-bubble"
      bubble.textContent = content
      if (sources && sources.length) {
        const ul = document.createElement("ul")
        ul.className = "atrium-ai-sources"
        sources.forEach(s => {
          const li = document.createElement("li")
          li.innerHTML = `↗ <a href="${escapeHtml(s.path)}">${escapeHtml(s.title)}</a> <span style="color:var(--text-tertiary)">· ${escapeHtml(s.section)}</span>`
          ul.appendChild(li)
        })
        bubble.appendChild(ul)
      }
      wrap.appendChild(bubble)
      messages.appendChild(wrap)
      messages.scrollTop = messages.scrollHeight
    }

    function addTyping() {
      const el = document.createElement("div")
      el.className = "atrium-ai-typing"
      el.id = "atrium-ai-typing"
      el.textContent = "Thinking…"
      messages.appendChild(el)
      messages.scrollTop = messages.scrollHeight
    }

    function removeTyping() {
      const el = document.getElementById("atrium-ai-typing")
      if (el) el.remove()
    }

    form.addEventListener("submit", function (e) {
      e.preventDefault()
      const message = input.value.trim()
      if (!message) return
      input.value = ""
      addMessage("user", message)
      history.push({ role: "user", content: message })
      addTyping()
      input.disabled = true

      const csrf = form.querySelector('input[name="_csrf_token"]').value
      fetch("/ai/chat", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrf
        },
        body: JSON.stringify({ message, history: history.slice(0, -1) })
      })
        .then(r => r.json().then(j => ({ ok: r.ok, status: r.status, body: j })))
        .then(({ ok, body }) => {
          removeTyping()
          if (ok && body.reply) {
            addMessage("assistant", body.reply, body.sources)
            history.push({ role: "assistant", content: body.reply })
          } else {
            addMessage("assistant", body.error || "Sorry — something went wrong.")
          }
        })
        .catch(() => {
          removeTyping()
          addMessage("assistant", "Network error. Try again.")
        })
        .finally(() => {
          input.disabled = false
          input.focus()
        })
    })
  })
})()
