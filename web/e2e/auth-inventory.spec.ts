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

  // Sidebar and dashboard counts use the same endpoint; wait for the inventory page's list.
  const inventory = page.waitForResponse(r => {
    const url = new URL(r.url())
    return url.pathname === '/api/v1/inventory-items'
      && r.request().method() === 'GET'
      && url.searchParams.get('status') === 'IN_STOCK'
      && url.searchParams.get('page') === '1'
      && url.searchParams.get('page_size') === '20'
      && !url.searchParams.has('storage_space_id')
      && !url.searchParams.has('category_id')
      && !url.searchParams.has('expiry_to')
  })
  await page.getByRole('navigation', { name: 'Main', exact: true })
    .getByRole('link', { name: /^Inventory(?:\s+\d+)?$/ }).click()
  const response = await inventory
  expect(response.status()).toBe(200)
  expect(await response.json()).toMatchObject({ total: 0, items: [] })
  await expect(page.getByText('Your inventory is empty.', { exact: true })).toBeVisible()
  await page.reload()
  await expect(page.getByText('Your inventory is empty.', { exact: true })).toBeVisible()
})
