import { defineConfig, devices } from '@playwright/test'

if (!process.env.E2E_BASE_URL || !process.env.E2E_WEB_PORT || !process.env.VITE_API_BASE_URL) {
  throw new Error('Start the isolated stack with: python backend/scripts/run_e2e.py')
}

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 45_000,
  globalTimeout: 180_000,
  expect: { timeout: 10_000 },
  outputDir: '.e2e-artifacts/results',
  reporter: [
    ['list'],
    ['html', { outputFolder: '.e2e-artifacts/html', open: 'never' }],
    ['junit', { outputFile: '.e2e-artifacts/junit.xml' }],
  ],
  use: {
    baseURL: process.env.E2E_BASE_URL,
    launchOptions: { slowMo: Number(process.env.E2E_SLOW_MO_MS ?? 0) },
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `npm run build -- --outDir .e2e-dist && npm run preview -- --outDir .e2e-dist --host 127.0.0.1 --port ${process.env.E2E_WEB_PORT} --strictPort`,
    url: process.env.E2E_BASE_URL,
    reuseExistingServer: false,
    timeout: 120_000,
  },
})
