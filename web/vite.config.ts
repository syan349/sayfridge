/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { configDefaults } from 'vitest/config'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // Forward API calls to the FastAPI backend so the browser only ever talks to
    // its own origin during development. 127.0.0.1 rather
    // than localhost: uvicorn listens on IPv4 only, and Windows can resolve
    // localhost to IPv6 ::1 first.
    proxy: {
      '/api': 'http://127.0.0.1:8000',
    },
  },
  test: {
    exclude: [...configDefaults.exclude, 'e2e/**'],
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
})
