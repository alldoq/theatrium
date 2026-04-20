import { defineConfig } from "vite"
import vue from "@vitejs/plugin-vue"
import path from "path"

export default defineConfig(({ command }) => ({
  plugins: [vue()],
  build: {
    outDir: "../priv/static/assets",
    emptyOutDir: false,
    sourcemap: command === "serve" ? "inline" : false,
    rollupOptions: {
      input: {
        app: path.resolve(__dirname, "js/app.js"),
      },
      output: {
        entryFileNames: "js/[name].js",
        chunkFileNames: "js/[name].js",
      },
    },
  },
  server: {
    port: 5173,
    host: "127.0.0.1",
    origin: "http://127.0.0.1:5173",
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "js"),
      phoenix_html: path.resolve(__dirname, "../deps/phoenix_html/priv/static/phoenix_html.js"),
      phoenix: path.resolve(__dirname, "../deps/phoenix/priv/static/phoenix.mjs"),
      phoenix_live_view: path.resolve(__dirname, "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js"),
    },
  },
}))
