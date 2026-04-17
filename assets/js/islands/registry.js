export const VueIslands = {}

export function registerVueIsland(name, component) {
  VueIslands[name] = component
}
