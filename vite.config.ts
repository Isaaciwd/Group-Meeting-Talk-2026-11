import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'

// The cu-boulder theme layouts import their footer by relative path ('../components/CuFooter.vue'), so a
// same-named project component is not picked up automatically. Redirect that import to the project override,
// which shows only the current talk's footer sections (see components/CuFooter.vue).
export default defineConfig({
  resolve: {
    alias: [
      {
        find: /^\.\.\/components\/CuFooter\.vue$/,
        replacement: fileURLToPath(new URL('./components/CuFooter.vue', import.meta.url)),
      },
    ],
  },
})
