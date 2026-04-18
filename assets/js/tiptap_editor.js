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
