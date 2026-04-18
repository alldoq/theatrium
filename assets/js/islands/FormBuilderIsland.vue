<template>
  <div style="display:flex;gap:20px;min-height:400px">

    <!-- Field palette -->
    <div style="width:172px;flex-shrink:0">
      <p style="font-size:11px;font-weight:600;color:var(--text-tertiary);text-transform:uppercase;letter-spacing:.08em;margin-bottom:10px">Field types</p>
      <div style="display:flex;flex-direction:column;gap:4px">
        <button
          v-for="type in fieldTypes"
          :key="type.value"
          type="button"
          @click="addField(type.value)"
          style="display:flex;align-items:center;gap:8px;width:100%;text-align:left;font-size:.8125rem;padding:8px 10px;border-radius:var(--radius);border:1px solid var(--border);background:var(--surface);cursor:pointer;color:var(--text-primary);transition:border-color .15s,background .15s"
          @mouseenter="e => { e.currentTarget.style.borderColor='var(--blue-500)'; e.currentTarget.style.background='var(--blue-50)' }"
          @mouseleave="e => { e.currentTarget.style.borderColor='var(--border)'; e.currentTarget.style.background='var(--surface)' }"
        >
          <svg :viewBox="type.viewBox || '0 0 24 24'" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="width:15px;height:15px;flex-shrink:0;color:var(--text-secondary)">
            <path :d="type.icon" />
          </svg>
          <span>{{ type.label }}</span>
        </button>
      </div>
    </div>

    <!-- Field canvas -->
    <div style="flex:1">
      <!-- Empty state -->
      <div
        v-if="fields.length === 0"
        style="border:2px dashed var(--border);border-radius:var(--radius);padding:48px 24px;text-align:center;color:var(--text-tertiary)"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="width:32px;height:32px;margin:0 auto 12px;display:block;opacity:.4">
          <path d="M9 12h6m-6 4h6m2 5H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5.586a1 1 0 0 1 .707.293l5.414 5.414a1 1 0 0 1 .293.707V19a2 2 0 0 1-2 2Z"/>
        </svg>
        <p style="font-size:.875rem;margin-bottom:4px;font-weight:500">No fields yet</p>
        <p style="font-size:.8125rem">Click a field type on the left to add it</p>
      </div>

      <!-- Fields list -->
      <div
        @dragover.prevent="onDragOver"
        @drop.prevent="onDrop"
        style="display:flex;flex-direction:column;gap:8px"
      >
        <div
          v-for="(field, index) in fields"
          :key="field.id"
          draggable="true"
          @dragstart="onDragStart(index, $event)"
          @dragend="onDragEnd"
          @dragenter.prevent="onDragEnter(index)"
          :style="{
            border: dragOver === index ? '1px solid var(--blue-500)' : '1px solid var(--border)',
            borderRadius: 'var(--radius)',
            background: dragging === index ? 'var(--blue-50)' : 'var(--surface)',
            padding: '12px 14px',
            opacity: dragging === index ? 0.5 : 1,
            transition: 'border-color .15s, background .15s, opacity .15s',
          }"
        >
          <div style="display:flex;align-items:flex-start;gap:10px">
            <!-- Drag handle -->
            <div style="flex-shrink:0;padding-top:3px;color:var(--text-tertiary);cursor:grab">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" style="width:14px;height:14px">
                <path stroke-linecap="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"/>
              </svg>
            </div>

            <!-- Field content -->
            <div style="flex:1;min-width:0">
              <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">
                <span style="font-family:'IBM Plex Mono',monospace;font-size:.625rem;letter-spacing:.06em;text-transform:uppercase;color:var(--text-tertiary);background:var(--surface-raised,#f1f5f9);border:1px solid var(--border);border-radius:3px;padding:2px 5px;flex-shrink:0">{{ field.type }}</span>
                <input
                  v-model="field.label"
                  @input="sync"
                  type="text"
                  placeholder="Field label"
                  style="flex:1;min-width:0;border:1px solid var(--border);border-radius:var(--radius);padding:5px 9px;font-size:.875rem;background:var(--surface);color:var(--text-primary);outline:none;transition:border-color .15s"
                  @focus="e => e.target.style.borderColor='var(--blue-500)'"
                  @blur="e => e.target.style.borderColor='var(--border)'"
                />
                <label style="display:flex;align-items:center;gap:5px;font-size:.8125rem;color:var(--text-secondary);cursor:pointer;white-space:nowrap;flex-shrink:0">
                  <input type="checkbox" v-model="field.required" @change="sync" style="accent-color:var(--blue-500);width:13px;height:13px" />
                  Required
                </label>
              </div>

              <div v-if="['radio','select','checkbox_group'].includes(field.type)">
                <label style="font-size:.75rem;color:var(--text-tertiary);display:block;margin-bottom:4px">Options <span style="opacity:.6">(one per line)</span></label>
                <textarea
                  :value="(field.options || []).join('\n')"
                  @change="e => { field.options = e.target.value.split('\n').filter(o => o.trim()); sync() }"
                  rows="4"
                  placeholder="Option A&#10;Option B&#10;Option C"
                  style="width:100%;border:1px solid var(--border);border-radius:var(--radius);padding:6px 9px;font-size:.8125rem;resize:vertical;box-sizing:border-box;background:var(--surface);color:var(--text-primary);outline:none;transition:border-color .15s"
                  @focus="e => e.target.style.borderColor='var(--blue-500)'"
                  @blur="e => { e.target.style.borderColor='var(--border)'; field.options = e.target.value.split('\n').filter(o => o.trim()); sync() }"
                ></textarea>
              </div>
            </div>

            <!-- Remove -->
            <button
              type="button"
              @click="removeField(index)"
              style="flex-shrink:0;border:none;background:none;cursor:pointer;color:var(--text-tertiary);padding:3px;border-radius:3px;display:flex;align-items:center;transition:color .15s"
              @mouseenter="e => e.currentTarget.style.color='var(--color-error,#ef4444)'"
              @mouseleave="e => e.currentTarget.style.color='var(--text-tertiary)'"
              title="Remove field"
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="width:15px;height:15px">
                <path d="M6 18 18 6M6 6l12 12"/>
              </svg>
            </button>
          </div>
        </div>

        <!-- Drop indicator at end -->
        <div
          v-if="fields.length > 0"
          @dragenter.prevent="onDragEnter(fields.length)"
          style="height:6px;border-radius:3px;transition:background .1s"
          :style="{ background: dragOver === fields.length ? 'var(--blue-500)' : 'transparent' }"
        ></div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from "vue"

const props = defineProps(["fields", "fields_input_id"])

const fieldTypes = [
  { value: "text",           label: "Text",       icon: "M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12" },
  { value: "textarea",       label: "Long text",  icon: "M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" },
  { value: "number",         label: "Number",     icon: "M5.25 8.25h13.5m-13.5 4.5h13.5m-13.5 4.5h13.5M3 3.75h18v16.5H3z", viewBox: "0 0 24 24" },
  { value: "date",           label: "Date",       icon: "M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5" },
  { value: "radio",          label: "Radio",      icon: "M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0-18 0m0 0m-3 0a3 3 0 1 0 6 0a3 3 0 1 0-6 0", viewBox: "0 0 24 24" },
  { value: "select",         label: "Select",     icon: "M8.25 15 12 18.75 15.75 15m-7.5-6L12 5.25 15.75 9" },
  { value: "checkbox_group", label: "Checkboxes", icon: "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" },
  { value: "file",           label: "File",       icon: "M18.375 12.739l-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.01.01m5.699-9.941-7.81 7.81a1.5 1.5 0 0 0 2.112 2.13" },
]

const fields = ref((props.fields || []).map(f => ({ ...f })))
const dragging = ref(null)
const dragOver = ref(null)

function generateId() {
  return "field_" + Math.random().toString(36).slice(2, 10)
}

function sync() {
  const input = document.getElementById(props.fields_input_id)
  if (input) {
    input.value = JSON.stringify(fields.value.map((f, i) => ({ ...f, order: i + 1 })))
  }
}

function addField(type) {
  fields.value.push({ id: generateId(), type, label: "", required: false, order: fields.value.length + 1, options: [], conditions: [] })
  sync()
}

function removeField(index) {
  fields.value.splice(index, 1)
  sync()
}

function onDragStart(index, e) {
  dragging.value = index
  e.dataTransfer.effectAllowed = "move"
}

function onDragEnd() {
  dragging.value = null
  dragOver.value = null
}

function onDragEnter(index) {
  if (dragging.value !== null) dragOver.value = index
}

function onDragOver(e) {
  e.preventDefault()
  e.dataTransfer.dropEffect = "move"
}

function onDrop() {
  const from = dragging.value
  let to = dragOver.value
  if (from === null || to === null || from === to) {
    dragging.value = null
    dragOver.value = null
    return
  }
  const item = fields.value.splice(from, 1)[0]
  if (to > from) to--
  fields.value.splice(to, 0, item)
  sync()
  dragging.value = null
  dragOver.value = null
}

onMounted(sync)
</script>
