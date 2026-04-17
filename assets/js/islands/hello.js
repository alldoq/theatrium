import { h } from "vue"
import { registerVueIsland } from "../app.js"

registerVueIsland("hello", {
  props: ["name"],
  setup(props) {
    return () => h("span", {}, `Hello, ${props.name || "Atrium"}!`)
  },
})
