import { randomUUID } from 'node:crypto'
import { test, expect } from '@playwright/test'

test('register, sign out, sign in and load an empty inventory from PostgreSQL', async ({ page }) => {
  const email = `e2e-${randomUUID()}@example.com`
  const password = `E2e-${randomUUID()}!`
  await page.goto('/register')
  await page.getByLabel('Email', { exact: true }).fill(email)
  await page.getByLabel('Password', { exact: true }).fill(password)
  await page.getByLabel('Confirm password', { exact: true }).fill(password)
  const registered = page.waitForResponse(r => r.url().endsWith('/auth/register') && r.request().method() === 'POST')
  await page.getByRole('button', { name: 'Create account', exact: true }).click()
  expect((await registered).status()).toBe(201)
  await page.getByRole('button', { name: 'Log out', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Sign in', exact: true })).toBeVisible()
  await page.getByLabel('Email', { exact: true }).fill(email)
  await page.getByLabel('Password', { exact: true }).fill(password)
  const signedIn = page.waitForResponse(r => r.url().endsWith('/auth/login') && r.request().method() === 'POST')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  expect((await signedIn).status()).toBe(200)
  await expect(page.getByRole('button', { name: 'Log out', exact: true })).toBeVisible()

  await page.getByRole('navigation', { name: 'Main', exact: true })
    .getByRole('link', { name: /^Inventory(?:\s+\d+)?$/ }).click()
  await expect(page.getByText('Your inventory is empty.', { exact: true })).toBeVisible()
  // Dashboard also loads inventory after login. Verify persisted data separately
  // so this assertion cannot capture a background count response.
  const api = process.env.VITE_API_BASE_URL!
  const token = await page.evaluate(() => JSON.parse(sessionStorage.getItem('sayfridge.auth')!).token as string)
  const response = await page.request.get(`${api}/inventory-items`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  expect(response.status()).toBe(200)
  expect(await response.json()).toMatchObject({ total: 0, items: [] })
  await page.reload()
  await expect(page.getByText('Your inventory is empty.', { exact: true })).toBeVisible()

  // Force client-side access expiry; the real backend must rotate the session.
  const before = await page.evaluate(() => JSON.parse(sessionStorage.getItem('sayfridge.auth')!))
  await page.evaluate(() => {
    const stored = JSON.parse(sessionStorage.getItem('sayfridge.auth')!)
    stored.expiresAt = 0
    sessionStorage.setItem('sayfridge.auth', JSON.stringify(stored))
  })
  const refreshed = page.waitForResponse(r => r.url().endsWith('/auth/refresh'))
  await page.reload()
  expect((await refreshed).status()).toBe(200)
  await expect(page.getByText('Your inventory is empty.', { exact: true })).toBeVisible()
  const after = await page.evaluate(() => JSON.parse(sessionStorage.getItem('sayfridge.auth')!))
  expect(after.refreshToken).not.toBe(before.refreshToken)
  const revoked = page.waitForResponse(r => r.url().endsWith('/auth/logout'))
  await page.getByRole('button', { name: 'Log out', exact: true }).click()
  expect((await revoked).status()).toBe(204)
  expect((await page.request.get(`${api}/auth/me`, {
    headers: { Authorization: `Bearer ${after.token}` },
  })).status()).toBe(401)
})
