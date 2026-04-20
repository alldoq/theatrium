# Rich Text Editor Polish (Tiptap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing Tiptap editor in the Atrium intranet app with three production-grade features — link insertion, image upload, and table support with a context toolbar.

**Architecture:** All frontend changes live in a single file (`assets/js/tiptap_editor.js`). New Tiptap extension packages are installed via npm. The image upload feature requires a new Phoenix controller action, a router entry, and a static file plug — all backend additions are minimal and self-contained. No LiveView is involved; the editor is vanilla JS mounted via a data attribute.

**Tech Stack:** Phoenix 1.8, Elixir, Tiptap 3.x (`@tiptap/core`, `@tiptap/starter-kit`), new packages: `@tiptap/extension-link`, `@tiptap/extension-image`, `@tiptap/extension-table`, `@tiptap/extension-table-row`, `@tiptap/extension-table-header`, `@tiptap/extension-table-cell`. Static file serving via `Plug.Static`.

---

## File Structure

**Modified files:**
- `assets/package.json` — add 6 new `@tiptap/extension-*` packages
- `assets/js/tiptap_editor.js` — add Link, Image, Table extensions + toolbar buttons + context toolbar
- `lib/atrium_web/endpoint.ex` — add `Plug.Static` for `/uploads`
- `lib/atrium_web/router.ex` — add `POST /sections/:section_key/documents/upload_image`
- `lib/atrium_web/controllers/document_controller.ex` — add `upload_image/2` action

---

## Task 1: Install npm packages, add static serving, add upload route + action

**Files:**
- Modify: `assets/package.json`
- Modify: `lib/atrium_web/endpoint.ex`
- Modify: `lib/atrium_web/router.ex`
- Modify: `lib/atrium_web/controllers/document_controller.ex`

- [ ] **Step 1: Add the 6 new tiptap extension packages to package.json**

Replace `assets/package.json` with:

```json
{
  "name": "assets",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "watch": "vite build --watch"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "type": "module",
  "dependencies": {
    "@tiptap/core": "^3.22.4",
    "@tiptap/extension-image": "^3.22.4",
    "@tiptap/extension-link": "^3.22.4",
    "@tiptap/extension-table": "^3.22.4",
    "@tiptap/extension-table-cell": "^3.22.4",
    "@tiptap/extension-table-header": "^3.22.4",
    "@tiptap/extension-table-row": "^3.22.4",
    "@tiptap/starter-kit": "^3.22.4",
    "topbar": "^3.0.1",
    "vue": "^3.5.32"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.2.4",
    "vite": "^6.4.2"
  }
}
```

- [ ] **Step 2: Install the packages**

```bash
cd /Users/marcinwalczak/Kod/atrium/assets
npm install
```

Expected: `node_modules/@tiptap/extension-link`, `node_modules/@tiptap/extension-image`, `node_modules/@tiptap/extension-table`, etc. appear. No errors.

- [ ] **Step 3: Add Plug.Static for /uploads in endpoint.ex**

In `lib/atrium_web/endpoint.ex`, add the new plug immediately after the existing `Plug.Static` block (which serves `/` from `:atrium`). The file should read:

```elixir
defmodule AtriumWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :atrium

  @session_options [
    store: :cookie,
    key: "_atrium_key",
    signing_salt: "G3L9DBCN",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :atrium,
    gzip: not code_reloading?,
    only: AtriumWeb.static_paths()

  plug Plug.Static,
    at: "/uploads",
    from: "priv/uploads",
    gzip: false

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :atrium
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug AtriumWeb.Router
end
```

- [ ] **Step 4: Add the upload_image route to router.ex**

In `lib/atrium_web/router.ex`, add one line inside the authenticated scope, immediately after the existing document routes (after the `download_pdf` line at line 154):

```elixir
      post "/sections/:section_key/documents/upload_image", DocumentController, :upload_image
```

The document route block should now look like this (lines 144–155 of the original, with the new route added):

```elixir
      get  "/sections/:section_key/documents",                    DocumentController, :index
      get  "/sections/:section_key/documents/new",                DocumentController, :new
      post "/sections/:section_key/documents",                    DocumentController, :create
      get  "/sections/:section_key/documents/:id",                DocumentController, :show
      get  "/sections/:section_key/documents/:id/edit",           DocumentController, :edit
      put  "/sections/:section_key/documents/:id",                DocumentController, :update
      post "/sections/:section_key/documents/:id/submit",         DocumentController, :submit
      post "/sections/:section_key/documents/:id/reject",         DocumentController, :reject
      post "/sections/:section_key/documents/:id/approve",        DocumentController, :approve
      post "/sections/:section_key/documents/:id/archive",        DocumentController, :archive
      get  "/sections/:section_key/documents/:id/pdf",            DocumentController, :download_pdf
      post "/sections/:section_key/documents/upload_image",       DocumentController, :upload_image
```

- [ ] **Step 5: Add upload_image/2 action to document_controller.ex**

Add the following function at the end of `lib/atrium_web/controllers/document_controller.ex`, before the final `end` (i.e., after the `run_transition/5` private function). Also add the `:upload_image` action to the existing `:edit` authorization plug so only users with edit permission can upload:

The plug guard at the top of the controller currently reads:

```elixir
  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: &__MODULE__.section_target/1]
       when action in [:new, :create, :edit, :update, :submit]
```

Change it to:

```elixir
  plug AtriumWeb.Plugs.Authorize,
       [capability: :edit, target: &__MODULE__.section_target/1]
       when action in [:new, :create, :edit, :update, :submit, :upload_image]
```

Then add the action itself (add after `download_pdf/2`, before the private helpers):

```elixir
  def upload_image(conn, %{"section_key" => section_key, "image" => %Plug.Upload{} = upload}) do
    prefix = conn.assigns.tenant_prefix
    dir = Path.join(["priv/uploads/documents", prefix, "images"])
    File.mkdir_p!(dir)
    ext = Path.extname(upload.filename)
    filename = "#{System.unique_integer([:positive])}#{ext}"
    dest = Path.join(dir, filename)
    File.cp!(upload.path, dest)
    url = "/uploads/documents/#{prefix}/images/#{filename}"
    json(conn, %{url: url})
  end

  def upload_image(conn, %{"section_key" => _section_key}) do
    conn
    |> put_status(400)
    |> json(%{error: "No image file provided"})
  end
```

- [ ] **Step 6: Verify the app compiles cleanly**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix compile 2>&1 | tail -10
```

Expected: no errors. Warnings about unused variables are acceptable.

- [ ] **Step 7: Smoke-test the upload route is reachable**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix phx.routes 2>&1 | grep upload_image
```

Expected output includes:

```
POST  /sections/:section_key/documents/upload_image  AtriumWeb.DocumentController :upload_image
```

- [ ] **Step 8: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add assets/package.json \
        assets/package-lock.json \
        lib/atrium_web/endpoint.ex \
        lib/atrium_web/router.ex \
        lib/atrium_web/controllers/document_controller.ex
git commit -m "feat(tiptap-polish): add image upload endpoint, static serving, and tiptap extension packages"
```

---

## Task 2: Add Link extension to tiptap_editor.js

**Files:**
- Modify: `assets/js/tiptap_editor.js`

The Link extension lets users highlight text, click "Link", and either set or unset a hyperlink. If the cursor is already on a link when the button is clicked, the link is removed. If text is selected, `window.prompt()` asks for the URL.

- [ ] **Step 1: Replace assets/js/tiptap_editor.js with the Link-extended version**

```javascript
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"

const TOOLBAR = [
  { cmd: "toggleBold",        label: "B",    title: "Bold",         active: "bold",        style: "font-weight:700" },
  { cmd: "toggleItalic",      label: "I",    title: "Italic",       active: "italic",      style: "font-style:italic" },
  { cmd: "toggleStrike",      label: "S",    title: "Strikethrough",active: "strike",      style: "text-decoration:line-through" },
  { sep: true },
  { cmd: "toggleBulletList",  label: "• List",  title: "Bullet list",  active: "bulletList" },
  { cmd: "toggleOrderedList", label: "1. List", title: "Ordered list", active: "orderedList" },
  { sep: true },
  { cmd: "toggleBlockquote",  label: "Quote", title: "Blockquote",  active: "blockquote" },
  { cmd: "toggleCodeBlock",   label: "Code",  title: "Code block",  active: "codeBlock" },
]

function makeBtn(spec, editor) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = spec.title
  btn.textContent = spec.label
  if (spec.style) btn.style.cssText += spec.style + ";"
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    editor.chain().focus()[spec.cmd]().run()
  })
  return btn
}

function makeSep() {
  const s = document.createElement("div")
  s.style.cssText = "width:1px;background:var(--border);margin:2px 4px;align-self:stretch"
  return s
}

function makeHeadingSel(editor) {
  const sel = document.createElement("select")
  Object.assign(sel.style, {
    border: "1px solid var(--border)",
    background: "var(--surface)",
    cursor: "pointer",
    padding: "3px 6px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    fontFamily: "inherit",
    marginLeft: "4px",
  })
  ;[["Paragraph", 0], ["Heading 1", 1], ["Heading 2", 2], ["Heading 3", 3]].forEach(([label, level]) => {
    const opt = document.createElement("option")
    opt.value = level
    opt.textContent = label
    sel.appendChild(opt)
  })
  sel.addEventListener("mousedown", e => e.stopPropagation())
  sel.addEventListener("change", () => {
    const level = parseInt(sel.value, 10)
    if (level === 0) editor.chain().focus().setParagraph().run()
    else editor.chain().focus().setHeading({ level }).run()
  })
  return sel
}

// SVG icons — inline so no external asset dependency
function svgLink() {
  const s = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  s.setAttribute("width", "14")
  s.setAttribute("height", "14")
  s.setAttribute("viewBox", "0 0 24 24")
  s.setAttribute("fill", "none")
  s.setAttribute("stroke", "currentColor")
  s.setAttribute("stroke-width", "2")
  s.setAttribute("stroke-linecap", "round")
  s.setAttribute("stroke-linejoin", "round")
  s.innerHTML = `<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
    <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>`
  return s
}

function makeLinkBtn(editor) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = "Link"
  btn.dataset.active = "link"
  btn.appendChild(svgLink())
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
    display: "inline-flex",
    alignItems: "center",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    if (editor.isActive("link")) {
      editor.chain().focus().unsetLink().run()
    } else {
      // eslint-disable-next-line no-alert
      const url = window.prompt("Enter URL")
      if (url && url.trim()) {
        editor.chain().focus().setLink({ href: url.trim() }).run()
      }
    }
  })
  return btn
}

function refreshToolbar(bar, editor) {
  bar.querySelectorAll("button[data-active]").forEach(btn => {
    const isActive = editor.isActive(btn.dataset.active)
    btn.style.background = isActive ? "var(--blue-100,#dbeafe)" : ""
    btn.style.borderColor = isActive ? "var(--blue-400,#60a5fa)" : "transparent"
    btn.style.color = isActive ? "var(--blue-700,#1d4ed8)" : "var(--text-secondary)"
  })
  const sel = bar.querySelector("select")
  if (sel) {
    const level = [1, 2, 3].find(l => editor.isActive("heading", { level: l }))
    sel.value = level || 0
  }
}

function buildToolbar(editor) {
  const bar = document.createElement("div")
  bar.style.cssText = [
    "display:flex", "align-items:center", "gap:2px", "flex-wrap:wrap",
    "padding:6px 12px",
    "border-bottom:1px solid var(--border)",
    "background:var(--surface-raised,#f8fafc)",
    "position:sticky", "top:0", "z-index:5",
  ].join(";")

  TOOLBAR.forEach(spec => {
    if (spec.sep) {
      bar.appendChild(makeSep())
    } else {
      const btn = makeBtn(spec, editor)
      btn.dataset.active = spec.active
      bar.appendChild(btn)
    }
  })

  bar.appendChild(makeHeadingSel(editor))
  bar.appendChild(makeSep())
  bar.appendChild(makeLinkBtn(editor))

  return bar
}

function initEditor(container) {
  const input = document.getElementById(container.dataset.inputId)
  if (!input) return

  const wrapper = document.createElement("div")
  wrapper.style.cssText = "display:flex;flex-direction:column;height:100%"
  container.parentNode.insertBefore(wrapper, container)

  const editorEl = document.createElement("div")
  editorEl.style.cssText = "flex:1;padding:0"
  wrapper.appendChild(editorEl)

  const editor = new Editor({
    element: editorEl,
    extensions: [
      StarterKit,
      Link.configure({ openOnClick: false }),
    ],
    content: input.value || "",
    editorProps: {
      attributes: {
        style: "min-height:600px;padding:0;outline:none",
        class: "prosemirror-content",
      },
    },
    onUpdate({ editor }) {
      input.value = editor.getHTML()
    },
    onTransaction({ editor }) {
      refreshToolbar(toolbar, editor)
    },
  })

  const toolbar = buildToolbar(editor)
  wrapper.insertBefore(toolbar, editorEl)

  container.remove()
  wrapper._tiptapEditor = editor
}

export function initTiptapEditors() {
  document.querySelectorAll("[data-tiptap-editor]").forEach(el => {
    if (!el._tiptapEditor && !el.dataset.tiptapInit) {
      el.dataset.tiptapInit = "1"
      initEditor(el)
    }
  })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initTiptapEditors)
} else {
  initTiptapEditors()
}
```

- [ ] **Step 2: Verify the JS bundle compiles**

```bash
cd /Users/marcinwalczak/Kod/atrium/assets
npm run build 2>&1 | tail -15
```

Expected: build succeeds with no errors. A warning about `window.prompt` is acceptable.

- [ ] **Step 3: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add assets/js/tiptap_editor.js
git commit -m "feat(tiptap-polish): add Link extension with toggle behaviour"
```

---

## Task 3: Add Image upload extension to tiptap_editor.js

**Files:**
- Modify: `assets/js/tiptap_editor.js`

The Image button triggers a hidden `<input type="file">`. On file selection, it POSTs to the upload endpoint via `fetch()`, then inserts the returned URL into the editor. The `section_key` is read from a `data-section-key` attribute on the container element — this attribute must already exist in the HEEx template that renders the editor container.

- [ ] **Step 1: Replace assets/js/tiptap_editor.js with the Image-extended version**

```javascript
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"

const TOOLBAR = [
  { cmd: "toggleBold",        label: "B",    title: "Bold",         active: "bold",        style: "font-weight:700" },
  { cmd: "toggleItalic",      label: "I",    title: "Italic",       active: "italic",      style: "font-style:italic" },
  { cmd: "toggleStrike",      label: "S",    title: "Strikethrough",active: "strike",      style: "text-decoration:line-through" },
  { sep: true },
  { cmd: "toggleBulletList",  label: "• List",  title: "Bullet list",  active: "bulletList" },
  { cmd: "toggleOrderedList", label: "1. List", title: "Ordered list", active: "orderedList" },
  { sep: true },
  { cmd: "toggleBlockquote",  label: "Quote", title: "Blockquote",  active: "blockquote" },
  { cmd: "toggleCodeBlock",   label: "Code",  title: "Code block",  active: "codeBlock" },
]

function makeBtn(spec, editor) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = spec.title
  btn.textContent = spec.label
  if (spec.style) btn.style.cssText += spec.style + ";"
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    editor.chain().focus()[spec.cmd]().run()
  })
  return btn
}

function makeSep() {
  const s = document.createElement("div")
  s.style.cssText = "width:1px;background:var(--border);margin:2px 4px;align-self:stretch"
  return s
}

function makeHeadingSel(editor) {
  const sel = document.createElement("select")
  Object.assign(sel.style, {
    border: "1px solid var(--border)",
    background: "var(--surface)",
    cursor: "pointer",
    padding: "3px 6px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    fontFamily: "inherit",
    marginLeft: "4px",
  })
  ;[["Paragraph", 0], ["Heading 1", 1], ["Heading 2", 2], ["Heading 3", 3]].forEach(([label, level]) => {
    const opt = document.createElement("option")
    opt.value = level
    opt.textContent = label
    sel.appendChild(opt)
  })
  sel.addEventListener("mousedown", e => e.stopPropagation())
  sel.addEventListener("change", () => {
    const level = parseInt(sel.value, 10)
    if (level === 0) editor.chain().focus().setParagraph().run()
    else editor.chain().focus().setHeading({ level }).run()
  })
  return sel
}

function svgLink() {
  const s = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  s.setAttribute("width", "14")
  s.setAttribute("height", "14")
  s.setAttribute("viewBox", "0 0 24 24")
  s.setAttribute("fill", "none")
  s.setAttribute("stroke", "currentColor")
  s.setAttribute("stroke-width", "2")
  s.setAttribute("stroke-linecap", "round")
  s.setAttribute("stroke-linejoin", "round")
  s.innerHTML = `<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
    <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>`
  return s
}

function svgImage() {
  const s = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  s.setAttribute("width", "14")
  s.setAttribute("height", "14")
  s.setAttribute("viewBox", "0 0 24 24")
  s.setAttribute("fill", "none")
  s.setAttribute("stroke", "currentColor")
  s.setAttribute("stroke-width", "2")
  s.setAttribute("stroke-linecap", "round")
  s.setAttribute("stroke-linejoin", "round")
  s.innerHTML = `<rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
    <circle cx="8.5" cy="8.5" r="1.5"/>
    <polyline points="21 15 16 10 5 21"/>`
  return s
}

function makeLinkBtn(editor) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = "Link"
  btn.dataset.active = "link"
  btn.appendChild(svgLink())
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
    display: "inline-flex",
    alignItems: "center",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    if (editor.isActive("link")) {
      editor.chain().focus().unsetLink().run()
    } else {
      // eslint-disable-next-line no-alert
      const url = window.prompt("Enter URL")
      if (url && url.trim()) {
        editor.chain().focus().setLink({ href: url.trim() }).run()
      }
    }
  })
  return btn
}

function makeImageBtn(editor, sectionKey) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = "Image"
  btn.appendChild(svgImage())
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
    display: "inline-flex",
    alignItems: "center",
  })

  // Hidden file input — appended to document.body so it doesn't interfere with layout
  const fileInput = document.createElement("input")
  fileInput.type = "file"
  fileInput.accept = "image/*"
  fileInput.style.display = "none"
  document.body.appendChild(fileInput)

  fileInput.addEventListener("change", async () => {
    const file = fileInput.files[0]
    if (!file) return
    // Reset so the same file can be re-selected later
    fileInput.value = ""

    const formData = new FormData()
    formData.append("image", file)

    // CSRF token is stored by Phoenix in a <meta> tag when using protect_from_forgery
    const csrfMeta = document.querySelector("meta[name='csrf-token']")
    const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") : ""

    try {
      const resp = await fetch(`/sections/${sectionKey}/documents/upload_image`, {
        method: "POST",
        headers: { "x-csrf-token": csrfToken },
        body: formData,
      })
      if (!resp.ok) {
        console.error("Image upload failed", resp.status)
        return
      }
      const { url } = await resp.json()
      editor.chain().focus().setImage({ src: url }).run()
    } catch (err) {
      console.error("Image upload error", err)
    }
  })

  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    fileInput.click()
  })

  return btn
}

function refreshToolbar(bar, editor) {
  bar.querySelectorAll("button[data-active]").forEach(btn => {
    const isActive = editor.isActive(btn.dataset.active)
    btn.style.background = isActive ? "var(--blue-100,#dbeafe)" : ""
    btn.style.borderColor = isActive ? "var(--blue-400,#60a5fa)" : "transparent"
    btn.style.color = isActive ? "var(--blue-700,#1d4ed8)" : "var(--text-secondary)"
  })
  const sel = bar.querySelector("select")
  if (sel) {
    const level = [1, 2, 3].find(l => editor.isActive("heading", { level: l }))
    sel.value = level || 0
  }
}

function buildToolbar(editor, sectionKey) {
  const bar = document.createElement("div")
  bar.style.cssText = [
    "display:flex", "align-items:center", "gap:2px", "flex-wrap:wrap",
    "padding:6px 12px",
    "border-bottom:1px solid var(--border)",
    "background:var(--surface-raised,#f8fafc)",
    "position:sticky", "top:0", "z-index:5",
  ].join(";")

  TOOLBAR.forEach(spec => {
    if (spec.sep) {
      bar.appendChild(makeSep())
    } else {
      const btn = makeBtn(spec, editor)
      btn.dataset.active = spec.active
      bar.appendChild(btn)
    }
  })

  bar.appendChild(makeHeadingSel(editor))
  bar.appendChild(makeSep())
  bar.appendChild(makeLinkBtn(editor))
  bar.appendChild(makeImageBtn(editor, sectionKey))

  return bar
}

function initEditor(container) {
  const input = document.getElementById(container.dataset.inputId)
  if (!input) return

  const sectionKey = container.dataset.sectionKey || ""

  const wrapper = document.createElement("div")
  wrapper.style.cssText = "display:flex;flex-direction:column;height:100%"
  container.parentNode.insertBefore(wrapper, container)

  const editorEl = document.createElement("div")
  editorEl.style.cssText = "flex:1;padding:0"
  wrapper.appendChild(editorEl)

  const editor = new Editor({
    element: editorEl,
    extensions: [
      StarterKit,
      Link.configure({ openOnClick: false }),
      Image,
    ],
    content: input.value || "",
    editorProps: {
      attributes: {
        style: "min-height:600px;padding:0;outline:none",
        class: "prosemirror-content",
      },
    },
    onUpdate({ editor }) {
      input.value = editor.getHTML()
    },
    onTransaction({ editor }) {
      refreshToolbar(toolbar, editor)
    },
  })

  const toolbar = buildToolbar(editor, sectionKey)
  wrapper.insertBefore(toolbar, editorEl)

  container.remove()
  wrapper._tiptapEditor = editor
}

export function initTiptapEditors() {
  document.querySelectorAll("[data-tiptap-editor]").forEach(el => {
    if (!el._tiptapEditor && !el.dataset.tiptapInit) {
      el.dataset.tiptapInit = "1"
      initEditor(el)
    }
  })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initTiptapEditors)
} else {
  initTiptapEditors()
}
```

- [ ] **Step 2: Add data-section-key to the editor container in HEEx templates**

The editor container element in `lib/atrium_web/controllers/document_html/new.html.heex` and `lib/atrium_web/controllers/document_html/edit.html.heex` needs a `data-section-key` attribute. Find the element that has `data-tiptap-editor` (the container `initEditor` receives) and ensure it carries the section key.

In `new.html.heex`, change the tiptap container element from whatever renders `data-tiptap-editor` to include `data-section-key={@section_key}`. For example, if the current template renders something like:

```heex
<div data-tiptap-editor data-input-id="document_body_html"></div>
```

Change it to:

```heex
<div data-tiptap-editor data-input-id="document_body_html" data-section-key={@section_key}></div>
```

Apply the identical change in `edit.html.heex`.

- [ ] **Step 3: Verify the JS bundle compiles**

```bash
cd /Users/marcinwalczak/Kod/atrium/assets
npm run build 2>&1 | tail -15
```

Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add assets/js/tiptap_editor.js \
        lib/atrium_web/controllers/document_html/new.html.heex \
        lib/atrium_web/controllers/document_html/edit.html.heex
git commit -m "feat(tiptap-polish): add Image upload extension with fetch-based upload"
```

---

## Task 4: Add Table extension + context toolbar to tiptap_editor.js

**Files:**
- Modify: `assets/js/tiptap_editor.js`

A "Table" button inserts a 3×3 table with a header row. A second row of context toolbar buttons (Add col, Del col, Add row, Del row) appears below the main toolbar only when the cursor is inside a table. The context toolbar is hidden by default via `display:none` and shown/hidden during `onTransaction`.

- [ ] **Step 1: Replace assets/js/tiptap_editor.js with the complete final version**

```javascript
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"
import Table from "@tiptap/extension-table"
import TableRow from "@tiptap/extension-table-row"
import TableHeader from "@tiptap/extension-table-header"
import TableCell from "@tiptap/extension-table-cell"

const TOOLBAR = [
  { cmd: "toggleBold",        label: "B",    title: "Bold",         active: "bold",        style: "font-weight:700" },
  { cmd: "toggleItalic",      label: "I",    title: "Italic",       active: "italic",      style: "font-style:italic" },
  { cmd: "toggleStrike",      label: "S",    title: "Strikethrough",active: "strike",      style: "text-decoration:line-through" },
  { sep: true },
  { cmd: "toggleBulletList",  label: "• List",  title: "Bullet list",  active: "bulletList" },
  { cmd: "toggleOrderedList", label: "1. List", title: "Ordered list", active: "orderedList" },
  { sep: true },
  { cmd: "toggleBlockquote",  label: "Quote", title: "Blockquote",  active: "blockquote" },
  { cmd: "toggleCodeBlock",   label: "Code",  title: "Code block",  active: "codeBlock" },
]

// ---------------------------------------------------------------------------
// Generic button factory (used for both toolbar and context toolbar)
// ---------------------------------------------------------------------------
function makeBtn(spec, editor) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = spec.title
  btn.textContent = spec.label
  if (spec.style) btn.style.cssText += spec.style + ";"
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    editor.chain().focus()[spec.cmd]().run()
  })
  return btn
}

function makeSep() {
  const s = document.createElement("div")
  s.style.cssText = "width:1px;background:var(--border);margin:2px 4px;align-self:stretch"
  return s
}

// ---------------------------------------------------------------------------
// SVG icon helpers
// ---------------------------------------------------------------------------
function svgIcon(pathsHtml) {
  const s = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  s.setAttribute("width", "14")
  s.setAttribute("height", "14")
  s.setAttribute("viewBox", "0 0 24 24")
  s.setAttribute("fill", "none")
  s.setAttribute("stroke", "currentColor")
  s.setAttribute("stroke-width", "2")
  s.setAttribute("stroke-linecap", "round")
  s.setAttribute("stroke-linejoin", "round")
  s.innerHTML = pathsHtml
  return s
}

function svgLink() {
  return svgIcon(`
    <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
    <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
  `)
}

function svgImage() {
  return svgIcon(`
    <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
    <circle cx="8.5" cy="8.5" r="1.5"/>
    <polyline points="21 15 16 10 5 21"/>
  `)
}

function svgTable() {
  return svgIcon(`
    <rect x="3" y="3" width="18" height="18" rx="1"/>
    <line x1="3" y1="9" x2="21" y2="9"/>
    <line x1="3" y1="15" x2="21" y2="15"/>
    <line x1="9" y1="3" x2="9" y2="21"/>
    <line x1="15" y1="3" x2="15" y2="21"/>
  `)
}

// ---------------------------------------------------------------------------
// Heading select
// ---------------------------------------------------------------------------
function makeHeadingSel(editor) {
  const sel = document.createElement("select")
  Object.assign(sel.style, {
    border: "1px solid var(--border)",
    background: "var(--surface)",
    cursor: "pointer",
    padding: "3px 6px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    fontFamily: "inherit",
    marginLeft: "4px",
  })
  ;[["Paragraph", 0], ["Heading 1", 1], ["Heading 2", 2], ["Heading 3", 3]].forEach(([label, level]) => {
    const opt = document.createElement("option")
    opt.value = level
    opt.textContent = label
    sel.appendChild(opt)
  })
  sel.addEventListener("mousedown", e => e.stopPropagation())
  sel.addEventListener("change", () => {
    const level = parseInt(sel.value, 10)
    if (level === 0) editor.chain().focus().setParagraph().run()
    else editor.chain().focus().setHeading({ level }).run()
  })
  return sel
}

// ---------------------------------------------------------------------------
// Icon button factory (for Link, Image, Table)
// ---------------------------------------------------------------------------
function makeIconBtn(title, svgEl, onMousedown) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.title = title
  btn.appendChild(svgEl)
  Object.assign(btn.style, {
    border: "1px solid transparent",
    background: "none",
    cursor: "pointer",
    padding: "3px 9px",
    borderRadius: "4px",
    fontSize: ".8125rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    transition: "background .1s,border-color .1s,color .1s",
    fontFamily: "inherit",
    display: "inline-flex",
    alignItems: "center",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    onMousedown()
  })
  return btn
}

// ---------------------------------------------------------------------------
// Link button
// ---------------------------------------------------------------------------
function makeLinkBtn(editor) {
  const btn = makeIconBtn("Link", svgLink(), () => {
    if (editor.isActive("link")) {
      editor.chain().focus().unsetLink().run()
    } else {
      // eslint-disable-next-line no-alert
      const url = window.prompt("Enter URL")
      if (url && url.trim()) {
        editor.chain().focus().setLink({ href: url.trim() }).run()
      }
    }
  })
  btn.dataset.active = "link"
  return btn
}

// ---------------------------------------------------------------------------
// Image button
// ---------------------------------------------------------------------------
function makeImageBtn(editor, sectionKey) {
  const fileInput = document.createElement("input")
  fileInput.type = "file"
  fileInput.accept = "image/*"
  fileInput.style.display = "none"
  document.body.appendChild(fileInput)

  fileInput.addEventListener("change", async () => {
    const file = fileInput.files[0]
    if (!file) return
    fileInput.value = ""

    const formData = new FormData()
    formData.append("image", file)

    const csrfMeta = document.querySelector("meta[name='csrf-token']")
    const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") : ""

    try {
      const resp = await fetch(`/sections/${sectionKey}/documents/upload_image`, {
        method: "POST",
        headers: { "x-csrf-token": csrfToken },
        body: formData,
      })
      if (!resp.ok) {
        console.error("Image upload failed", resp.status)
        return
      }
      const { url } = await resp.json()
      editor.chain().focus().setImage({ src: url }).run()
    } catch (err) {
      console.error("Image upload error", err)
    }
  })

  return makeIconBtn("Image", svgImage(), () => fileInput.click())
}

// ---------------------------------------------------------------------------
// Table button
// ---------------------------------------------------------------------------
function makeTableBtn(editor) {
  return makeIconBtn("Table", svgTable(), () => {
    editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run()
  })
}

// ---------------------------------------------------------------------------
// Context toolbar (shown only when cursor is inside a table)
// ---------------------------------------------------------------------------
const TABLE_CONTEXT_ACTIONS = [
  { cmd: "addColumnBefore", label: "Add col" },
  { cmd: "deleteColumn",    label: "Del col" },
  { sep: true },
  { cmd: "addRowAfter",     label: "Add row" },
  { cmd: "deleteRow",       label: "Del row" },
]

function makeContextBtn(label, cmd, editor) {
  const btn = document.createElement("button")
  btn.type = "button"
  btn.textContent = label
  Object.assign(btn.style, {
    border: "1px solid var(--border,#e2e8f0)",
    background: "none",
    cursor: "pointer",
    padding: "2px 8px",
    borderRadius: "4px",
    fontSize: ".75rem",
    color: "var(--text-secondary)",
    lineHeight: "1.5",
    fontFamily: "inherit",
    transition: "background .1s,border-color .1s",
  })
  btn.addEventListener("mousedown", e => {
    e.preventDefault()
    editor.chain().focus()[cmd]().run()
  })
  return btn
}

function buildContextToolbar(editor) {
  const bar = document.createElement("div")
  bar.dataset.tableContext = "1"
  bar.style.cssText = [
    "display:none",
    "align-items:center",
    "gap:4px",
    "padding:4px 12px",
    "border-bottom:1px solid var(--border)",
    "background:var(--surface-raised,#f8fafc)",
  ].join(";")

  TABLE_CONTEXT_ACTIONS.forEach(item => {
    if (item.sep) {
      bar.appendChild(makeSep())
    } else {
      bar.appendChild(makeContextBtn(item.label, item.cmd, editor))
    }
  })

  return bar
}

// ---------------------------------------------------------------------------
// Toolbar state refresh
// ---------------------------------------------------------------------------
function refreshToolbar(bar, contextBar, editor) {
  // Active state on main toolbar buttons
  bar.querySelectorAll("button[data-active]").forEach(btn => {
    const isActive = editor.isActive(btn.dataset.active)
    btn.style.background = isActive ? "var(--blue-100,#dbeafe)" : ""
    btn.style.borderColor = isActive ? "var(--blue-400,#60a5fa)" : "transparent"
    btn.style.color = isActive ? "var(--blue-700,#1d4ed8)" : "var(--text-secondary)"
  })

  // Heading select sync
  const sel = bar.querySelector("select")
  if (sel) {
    const level = [1, 2, 3].find(l => editor.isActive("heading", { level: l }))
    sel.value = level || 0
  }

  // Show/hide context toolbar
  contextBar.style.display = editor.isActive("table") ? "flex" : "none"
}

// ---------------------------------------------------------------------------
// Main toolbar builder
// ---------------------------------------------------------------------------
function buildToolbar(editor, sectionKey) {
  const bar = document.createElement("div")
  bar.style.cssText = [
    "display:flex", "align-items:center", "gap:2px", "flex-wrap:wrap",
    "padding:6px 12px",
    "border-bottom:1px solid var(--border)",
    "background:var(--surface-raised,#f8fafc)",
    "position:sticky", "top:0", "z-index:5",
  ].join(";")

  TOOLBAR.forEach(spec => {
    if (spec.sep) {
      bar.appendChild(makeSep())
    } else {
      const btn = makeBtn(spec, editor)
      btn.dataset.active = spec.active
      bar.appendChild(btn)
    }
  })

  bar.appendChild(makeHeadingSel(editor))
  bar.appendChild(makeSep())
  bar.appendChild(makeLinkBtn(editor))
  bar.appendChild(makeImageBtn(editor, sectionKey))
  bar.appendChild(makeSep())
  bar.appendChild(makeTableBtn(editor))

  return bar
}

// ---------------------------------------------------------------------------
// Editor initialisation
// ---------------------------------------------------------------------------
function initEditor(container) {
  const input = document.getElementById(container.dataset.inputId)
  if (!input) return

  const sectionKey = container.dataset.sectionKey || ""

  const wrapper = document.createElement("div")
  wrapper.style.cssText = "display:flex;flex-direction:column;height:100%"
  container.parentNode.insertBefore(wrapper, container)

  const editorEl = document.createElement("div")
  editorEl.style.cssText = "flex:1;padding:0"
  wrapper.appendChild(editorEl)

  // Build placeholders — real references filled in after Editor construction
  let toolbar
  let contextBar

  const editor = new Editor({
    element: editorEl,
    extensions: [
      StarterKit,
      Link.configure({ openOnClick: false }),
      Image,
      Table.configure({ resizable: false }),
      TableRow,
      TableHeader,
      TableCell,
    ],
    content: input.value || "",
    editorProps: {
      attributes: {
        style: "min-height:600px;padding:0;outline:none",
        class: "prosemirror-content",
      },
    },
    onUpdate({ editor }) {
      input.value = editor.getHTML()
    },
    onTransaction({ editor }) {
      if (toolbar && contextBar) {
        refreshToolbar(toolbar, contextBar, editor)
      }
    },
  })

  toolbar = buildToolbar(editor, sectionKey)
  contextBar = buildContextToolbar(editor)

  wrapper.insertBefore(contextBar, editorEl)
  wrapper.insertBefore(toolbar, contextBar)

  container.remove()
  wrapper._tiptapEditor = editor
}

export function initTiptapEditors() {
  document.querySelectorAll("[data-tiptap-editor]").forEach(el => {
    if (!el._tiptapEditor && !el.dataset.tiptapInit) {
      el.dataset.tiptapInit = "1"
      initEditor(el)
    }
  })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initTiptapEditors)
} else {
  initTiptapEditors()
}
```

- [ ] **Step 2: Verify the JS bundle compiles**

```bash
cd /Users/marcinwalczak/Kod/atrium/assets
npm run build 2>&1 | tail -15
```

Expected: build succeeds with no errors.

- [ ] **Step 3: Run the Phoenix server and manually verify all three features**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix phx.server
```

Open a document edit page in the browser. Verify:
1. **Link** — select some text, click the chain icon, enter a URL in the prompt. The selected text becomes a hyperlink. Click it again while the cursor is on the link: the link is removed.
2. **Image** — click the image icon, choose a local image file. The image appears inline in the editor. Confirm the file was written to `priv/uploads/documents/<prefix>/images/`.
3. **Table** — click the table icon. A 3-column, 3-row table with a header row is inserted. Move the cursor into the table: a second toolbar row appears with "Add col", "Del col", "Add row", "Del row". Move the cursor outside the table: the context toolbar disappears.

- [ ] **Step 4: Commit**

```bash
cd /Users/marcinwalczak/Kod/atrium
git add assets/js/tiptap_editor.js
git commit -m "feat(tiptap-polish): add Table extension with context toolbar"
```

---

## Task 5: Final commit and tag

**Files:** none (verification + tag only)

- [ ] **Step 1: Run the full Elixir test suite**

```bash
cd /Users/marcinwalczak/Kod/atrium
mix test 2>&1 | tail -10
```

Expected: all tests pass. The backend changes (endpoint, router, controller) are covered by existing document controller tests — the new `upload_image` action is only reachable with a real multipart POST, which the existing test suite does not attempt, so no new test failures are expected.

- [ ] **Step 2: Build the production JS bundle**

```bash
cd /Users/marcinwalczak/Kod/atrium/assets
npm run build 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Tag the milestone**

```bash
cd /Users/marcinwalczak/Kod/atrium
git tag tiptap-polish-complete
git tag | grep tiptap
```

Expected: `tiptap-polish-complete`
