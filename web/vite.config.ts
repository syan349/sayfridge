/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // Forward API calls to the FastAPI backend so the browser only ever talks to
    // its own origin (the backend has no CORS middleware yet). 127.0.0.1 rather
    // than localhost: uvicorn listens on IPv4 only, and Windows can resolve
    // localhost to IPv6 ::1 first.
    proxy: {
      '/api': 'http://127.0.0.1:8000',
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
  },
})
