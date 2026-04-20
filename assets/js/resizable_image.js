import { Image } from '@tiptap/extension-image'

export const ResizableImage = Image.extend({
  addOptions() {
    return {
      ...this.parent?.(),
      inline: false,
      allowBase64: true,
      HTMLAttributes: {},
    }
  },

  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: (element) => element.getAttribute('width'),
        renderHTML: (attributes) => {
          if (!attributes.width) return {}
          return { width: attributes.width }
        },
      },
      'data-align': {
        default: 'left',
        parseHTML: (element) => element.getAttribute('data-align') || 'left',
        renderHTML: (attributes) => {
          return { 'data-align': attributes['data-align'] || 'left' }
        },
      },
    }
  },

  addNodeView() {
    return ({ node: initialNode, editor, getPos }) => {
      let node = initialNode

      // Outer wrapper — controls float / centering
      const wrapper = document.createElement('div')
      wrapper.setAttribute('data-image-wrapper', 'true')
      applyWrapperAlign(wrapper, node.attrs['data-align'])

      // Container is position:relative so resize dots are anchored to it
      const container = document.createElement('div')
      container.style.cssText = 'display:inline-block;position:relative;line-height:0;'
      container.setAttribute('data-image-container', 'true')

      const img = document.createElement('img')
      img.src = node.attrs.src
      img.style.cssText = 'display:block;border:2px solid transparent;border-radius:4px;box-sizing:border-box;max-width:100%;cursor:default;'
      img.draggable = false

      const handleImageLoad = () => {
        const currentWidth = node.attrs.width
        if (currentWidth) {
          img.style.width = typeof currentWidth === 'string' ? currentWidth : `${currentWidth}px`
        } else {
          const editorEl = container.closest('.ProseMirror')
          const editorWidth = editorEl ? editorEl.offsetWidth : 600
          const defaultWidth = Math.min(Math.floor(editorWidth * 0.6), img.naturalWidth || 400)
          img.style.width = `${defaultWidth}px`
          if (typeof getPos === 'function') {
            editor.commands.updateAttributes(this.name, { width: `${defaultWidth}px` })
          }
        }
      }
      img.onload = handleImageLoad
      if (img.complete && img.naturalWidth > 0) handleImageLoad()

      container.appendChild(img)
      wrapper.appendChild(container)

      const listeners = {}

      if (editor.isEditable) {
        // ── Alignment toolbar ──────────────────────────────────────────────
        const toolbar = document.createElement('div')
        toolbar.style.cssText = `
          display: none;
          position: absolute;
          top: -34px;
          left: 50%;
          transform: translateX(-50%);
          background: #1e293b;
          border-radius: 6px;
          padding: 3px 4px;
          gap: 2px;
          align-items: center;
          box-shadow: 0 2px 8px rgba(0,0,0,0.3);
          z-index: 100;
          white-space: nowrap;
        `

        const alignments = [
          { value: 'left',   icon: alignLeftSVG(),   title: 'Align left'   },
          { value: 'center', icon: alignCenterSVG(), title: 'Align center' },
          { value: 'right',  icon: alignRightSVG(),  title: 'Align right'  },
        ]

        const alignBtns = {}

        alignments.forEach(({ value, icon, title }) => {
          const btn = document.createElement('button')
          btn.title = title
          btn.type = 'button'
          btn.innerHTML = icon
          btn.style.cssText = `
            width: 26px; height: 26px; border: 1px solid transparent;
            border-radius: 4px; background: none; cursor: pointer;
            color: #e2e8f0; display: inline-flex; align-items: center;
            justify-content: center; padding: 0;
          `
          btn.addEventListener('mousedown', (e) => {
            e.preventDefault()
            e.stopPropagation()
            if (typeof getPos === 'function') {
              editor.chain().focus().updateAttributes('image', { 'data-align': value }).run()
            }
            applyWrapperAlign(wrapper, value)
            refreshToolbarActive(value)
          })
          toolbar.appendChild(btn)
          alignBtns[value] = btn
        })

        // Separator
        const sep = document.createElement('div')
        sep.style.cssText = 'width:1px;height:18px;background:#475569;margin:0 2px;display:inline-block;'
        toolbar.appendChild(sep)

        // Delete button
        const delBtn = document.createElement('button')
        delBtn.title = 'Delete image'
        delBtn.type = 'button'
        delBtn.innerHTML = trashSVG()
        delBtn.style.cssText = `
          width: 26px; height: 26px; border: 1px solid transparent;
          border-radius: 4px; background: none; cursor: pointer;
          color: #f87171; display: inline-flex; align-items: center;
          justify-content: center; padding: 0;
        `
        delBtn.addEventListener('mousedown', (e) => {
          e.preventDefault()
          e.stopPropagation()
          if (typeof getPos === 'function') {
            const pos = getPos()
            editor.chain().focus().deleteRange({ from: pos, to: pos + node.nodeSize }).run()
          }
        })
        toolbar.appendChild(delBtn)

        container.appendChild(toolbar)

        function refreshToolbarActive(activeAlign) {
          Object.entries(alignBtns).forEach(([val, btn]) => {
            if (val === activeAlign) {
              btn.style.background = 'rgba(255,255,255,0.15)'
              btn.style.borderColor = 'rgba(255,255,255,0.2)'
            } else {
              btn.style.background = 'none'
              btn.style.borderColor = 'transparent'
            }
          })
        }

        const dots = []
        let isResizing = false, startX, startWidth, activeDotIndex

        const showToolbar = () => {
          img.style.border = '2px dashed #6C6C6C'
          toolbar.style.display = 'inline-flex'
          refreshToolbarActive(node.attrs['data-align'] || 'left')
          dots.forEach(d => (d.style.display = 'block'))
        }

        const hideToolbar = (e) => {
          if (!container.contains(e.target)) {
            img.style.border = '2px solid transparent'
            toolbar.style.display = 'none'
            dots.forEach(d => (d.style.display = 'none'))
            document.removeEventListener('click', hideToolbar, true)
          }
        }

        container.addEventListener('click', (e) => {
          e.stopPropagation()
          showToolbar()
          setTimeout(() => document.addEventListener('click', hideToolbar, true), 0)
        })

        // ── Resize dots ────────────────────────────────────────────────────
        const dotSize = 9
        const dotOffset = -4
        const dotPositions = [
          { top: `${dotOffset}px`,    left:  `${dotOffset}px`, cursor: 'nwse-resize' },
          { top: `${dotOffset}px`,    right: `${dotOffset}px`, cursor: 'nesw-resize' },
          { bottom: `${dotOffset}px`, left:  `${dotOffset}px`, cursor: 'nesw-resize' },
          { bottom: `${dotOffset}px`, right: `${dotOffset}px`, cursor: 'nwse-resize' },
        ]

        dotPositions.forEach((pos, index) => {
          const dot = document.createElement('div')
          dot.style.cssText = `
            position:absolute; width:${dotSize}px; height:${dotSize}px;
            border:1.5px solid #6C6C6C; border-radius:50%;
            background:white; cursor:${pos.cursor}; display:none; z-index:1000;
            ${pos.top    ? `top:${pos.top};`       : ''}
            ${pos.left   ? `left:${pos.left};`     : ''}
            ${pos.bottom ? `bottom:${pos.bottom};` : ''}
            ${pos.right  ? `right:${pos.right};`   : ''}
          `
          dots.push(dot)
          container.appendChild(dot)

          dot.addEventListener('mousedown', (e) => {
            e.preventDefault()
            e.stopPropagation()
            isResizing = true
            startX = e.clientX
            startWidth = img.offsetWidth
            activeDotIndex = index
            document.addEventListener('mousemove', onMouseMove)
            document.addEventListener('mouseup', onMouseUp)
          })
        })

        const onMouseMove = (e) => {
          if (!isResizing) return
          let deltaX = e.clientX - startX
          if (activeDotIndex === 0 || activeDotIndex === 2) deltaX = -deltaX
          const editorEl = container.closest('.ProseMirror')
          const maxWidth = editorEl ? editorEl.offsetWidth * 0.95 : 600
          const newWidth = Math.max(50, Math.min(startWidth + deltaX, maxWidth))
          img.style.width = `${newWidth}px`
        }

        const onMouseUp = () => {
          if (isResizing) {
            isResizing = false
            const finalWidth = img.style.width
            if (finalWidth && node.attrs.width !== finalWidth) {
              if (typeof getPos === 'function') {
                editor.commands.updateAttributes('image', { width: finalWidth })
              }
            }
          }
          document.removeEventListener('mousemove', onMouseMove)
          document.removeEventListener('mouseup', onMouseUp)
        }

        listeners.move = onMouseMove
        listeners.up = onMouseUp
      }

      return {
        dom: wrapper,
        destroy: () => {
          img.onload = null
          if (listeners.move) document.removeEventListener('mousemove', listeners.move)
          if (listeners.up)   document.removeEventListener('mouseup',   listeners.up)
        },
        update: (updatedNode) => {
          if (updatedNode.type !== node.type) return false
          node = updatedNode
          const newAlign = updatedNode.attrs['data-align'] || 'left'
          applyWrapperAlign(wrapper, newAlign)
          if (updatedNode.attrs.src !== img.src) img.src = updatedNode.attrs.src
          if (updatedNode.attrs.width) img.style.width = updatedNode.attrs.width
          return true
        },
      }
    }
  },
})

function applyWrapperAlign(wrapper, align) {
  wrapper.style.cssText = 'display:block;margin:4px 0;line-height:0;'
  if (align === 'center') {
    wrapper.style.textAlign = 'center'
  } else if (align === 'right') {
    wrapper.style.float = 'right'
    wrapper.style.marginLeft = '1rem'
    wrapper.style.marginBottom = '0.5rem'
    wrapper.style.marginRight = '0'
    wrapper.style.marginTop = '0'
  } else {
    wrapper.style.float = 'none'
  }
}

function alignLeftSVG() {
  return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M15 15H3v2h12v-2zm0-8H3v2h12V7zM3 13h18v-2H3v2zm0 8h18v-2H3v2zM3 3v2h18V3H3z"/></svg>`
}
function alignCenterSVG() {
  return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M7 15v2h10v-2H7zm-4 6h18v-2H3v2zm0-8h18v-2H3v2zm4-6v2h10V7H7zM3 3v2h18V3H3z"/></svg>`
}
function alignRightSVG() {
  return `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M3 21h18v-2H3v2zm6-4h12v-2H9v2zm-6-4h18v-2H3v2zm6-4h12V7H9v2zM3 3v2h18V3H3z"/></svg>`
}
function trashSVG() {
  return `<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>`
}
