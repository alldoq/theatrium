import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"

function initEditor(container) {
  const input = document.getElementById(container.dataset.inputId)
  if (!input) return

  const editor = new Editor({
    element: container,
    extensions: [StarterKit],
    content: input.value || "",
    onUpdate({ editor }) {
      input.value = editor.getHTML()
    },
  })

  // Prevent the hidden input from being reset on form re-render
  container._tiptapEditor = editor
}

export function initTiptapEditors() {
  document.querySelectorAll("[data-tiptap-editor]").forEach((el) => {
    if (!el._tiptapEditor) initEditor(el)
  })
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initTiptapEditors)
} else {
  initTiptapEditors()
}
