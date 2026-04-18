<!-- assets/js/islands/FormBuilderIsland.vue -->
<template>
  <div>
    <div class="flex gap-4 mb-4">
      <div class="w-48 border rounded p-3 bg-slate-50">
        <p class="text-xs font-semibold text-slate-600 mb-2 uppercase tracking-wide">Add field</p>
        <button
          v-for="type in fieldTypes"
          :key="type.value"
          type="button"
          @click="addField(type.value)"
          class="block w-full text-left text-sm px-2 py-1 rounded hover:bg-slate-200 mb-1"
        >
          + {{ type.label }}
        </button>
      </div>

      <div class="flex-1">
        <p v-if="fields.length === 0" class="text-slate-400 text-sm italic p-4 border rounded">
          No fields yet. Add a field from the left panel.
        </p>
        <div
          v-for="(field, index) in fields"
          :key="field.id"
          class="border rounded p-3 mb-2 bg-white"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="flex-1 space-y-2">
              <div class="flex gap-2 items-center">
                <span class="text-xs text-slate-400 uppercase font-semibold w-16 shrink-0">{{ field.type }}</span>
                <input
                  v-model="field.label"
                  @input="sync"
                  type="text"
                  placeholder="Field label"
                  class="flex-1 border rounded p-1 text-sm"
                />
                <label class="flex items-center gap-1 text-xs text-slate-600 shrink-0">
                  <input type="checkbox" v-model="field.required" @change="sync" />
                  Required
                </label>
              </div>

              <div v-if="['radio','select','checkbox_group'].includes(field.type)" class="ml-16">
                <p class="text-xs text-slate-500 mb-1">Options (one per line)</p>
                <textarea
                  :value="(field.options || []).join('\n')"
                  @input="e => { field.options = e.target.value.split('\n').filter(o => o.trim()); sync() }"
                  rows="3"
                  class="w-full border rounded p-1 text-xs"
                  placeholder="Option 1&#10;Option 2"
                ></textarea>
              </div>
            </div>

            <div class="flex flex-col gap-1">
              <button type="button" @click="moveUp(index)" :disabled="index === 0" class="text-slate-400 hover:text-slate-700 disabled:opacity-30 text-xs">▲</button>
              <button type="button" @click="moveDown(index)" :disabled="index === fields.length - 1" class="text-slate-400 hover:text-slate-700 disabled:opacity-30 text-xs">▼</button>
              <button type="button" @click="removeField(index)" class="text-red-400 hover:text-red-600 text-xs">✕</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { registerVueIsland } from "./registry.js"
import { ref } from "vue"

registerVueIsland("FormBuilderIsland", {
  props: ["fields", "fields_input_id"],
  setup(props) {
    const fieldTypes = [
      { value: "text", label: "Text" },
      { value: "textarea", label: "Long text" },
      { value: "number", label: "Number" },
      { value: "date", label: "Date" },
      { value: "radio", label: "Radio" },
      { value: "select", label: "Select" },
      { value: "checkbox_group", label: "Checkboxes" },
      { value: "file", label: "File upload" },
    ]

    const fields = ref((props.fields || []).map(f => ({ ...f })))

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
      fields.value.push({
        id: generateId(),
        type,
        label: "",
        required: false,
        order: fields.value.length + 1,
        options: [],
        conditions: [],
      })
      sync()
    }

    function removeField(index) {
      fields.value.splice(index, 1)
      sync()
    }

    function moveUp(index) {
      if (index === 0) return
      const tmp = fields.value[index - 1]
      fields.value[index - 1] = fields.value[index]
      fields.value[index] = tmp
      sync()
    }

    function moveDown(index) {
      if (index === fields.value.length - 1) return
      const tmp = fields.value[index + 1]
      fields.value[index + 1] = fields.value[index]
      fields.value[index] = tmp
      sync()
    }

    sync()

    return { fieldTypes, fields, addField, removeField, moveUp, moveDown, sync }
  }
})
</script>
