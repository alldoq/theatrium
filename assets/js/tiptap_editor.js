import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"
import { Table, TableRow, TableHeader, TableCell } from "@tiptap/extension-table"
import { ResizableImage } from "./resizable_image.js"

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

async function resizeImage(file, maxDim = 1500) {
  return new Promise((resolve) => {
    const img = new window.Image()
    const objectUrl = URL.createObjectURL(file)
    img.onload = () => {
      URL.revokeObjectURL(objectUrl)
      const { naturalWidth: w, naturalHeight: h } = img
      if (w <= maxDim && h <= maxDim) { resolve(file); return }
      const scale = Math.min(maxDim / w, maxDim / h)
      const canvas = document.createElement("canvas")
      canvas.width  = Math.round(w * scale)
      canvas.height = Math.round(h * scale)
      canvas.getContext("2d").drawImage(img, 0, 0, canvas.width, canvas.height)
      canvas.toBlob(blob => resolve(blob || file), "image/jpeg", 0.8)
    }
    img.onerror = () => { URL.revokeObjectURL(objectUrl); resolve(file) }
    img.src = objectUrl
  })
}

async function uploadImage(file, sectionKey) {
  const isHeic = /heic|heif/i.test(file.type)
  const processed = isHeic ? file : await resizeImage(file)
  const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") ?? ""
  const formData = new FormData()
  formData.append("image", processed)
  const resp = await fetch(`/sections/${sectionKey}/documents/upload_image`, {
    method: "POST",
    headers: { "x-csrf-token": csrfToken },
    body: formData,
  })
  if (!resp.ok) throw new Error(`Upload failed: ${resp.status}`)
  const { url } = await resp.json()
  return url
}

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
    try {
      const url = await uploadImage(file, sectionKey)
      editor.chain().focus().setImage({ src: url }).run()
    } catch (err) {
      console.error("Image upload error", err)
    }
  })

  return makeIconBtn("Image", svgImage(), () => fileInput.click())
}

function makeTableBtn(editor) {
  return makeIconBtn("Table", svgTable(), () => {
    editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run()
  })
}

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

function refreshToolbar(bar, contextBar, editor) {
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

  contextBar.style.display = editor.isActive("table") ? "flex" : "none"
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
  bar.appendChild(makeSep())
  bar.appendChild(makeTableBtn(editor))

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

  let toolbar
  let contextBar

  const editor = new Editor({
    element: editorEl,
    extensions: [
      StarterKit,
      Link.configure({ openOnClick: false }),
      ResizableImage,
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

  editorEl.addEventListener("paste", async (e) => {
    const items = Array.from(e.clipboardData?.items ?? [])
    const imageItem = items.find(i => i.type.startsWith("image/"))
    if (!imageItem || !sectionKey) return
    e.preventDefault()
    const file = imageItem.getAsFile()
    if (!file) return
    try {
      const url = await uploadImage(file, sectionKey)
      editor.chain().focus().setImage({ src: url }).run()
    } catch (err) {
      console.error("Paste image upload error", err)
    }
  })

  editorEl.addEventListener("drop", async (e) => {
    const files = Array.from(e.dataTransfer?.files ?? []).filter(f => f.type.startsWith("image/"))
    if (!files.length || !sectionKey) return
    e.preventDefault()
    for (const file of files) {
      try {
        const url = await uploadImage(file, sectionKey)
        editor.chain().focus().setImage({ src: url }).run()
      } catch (err) {
        console.error("Drop image upload error", err)
      }
    }
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
