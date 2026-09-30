import { randomUUID } from 'node:crypto'
import { test, expect, type Page } from '@playwright/test'

const api = process.env.VITE_API_BASE_URL!

async function register(page: Page) {
  await page.goto('/register')
  await page.getByLabel('Email', { exact: true }).fill(`e2e-${randomUUID()}@example.com`)
  await page.getByLabel('Password', { exact: true }).fill('BrowserE2e@734')
  await page.getByLabel('Confirm password', { exact: true }).fill('BrowserE2e@734')
  await page.getByRole('button', { name: 'Create account', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Log out', exact: true })).toBeVisible()
}

// Fixture setup and persistence checks use real authenticated HTTP requests.
// The business action under test is performed through the rendered Web UI.
async function headers(page: Page) {
  const token = await page.evaluate(() => JSON.parse(sessionStorage.getItem('sayfridge.auth')!).token as string)
  return { Authorization: `Bearer ${token}` }
}
async function read(page: Page, path: string) {
  const response = await page.request.get(api + path, { headers: await headers(page) })
  expect(response.status()).toBe(200)
  return response.json()
}
async function post(page: Page, path: string, data: unknown) {
  const response = await page.request.post(api + path, { headers: await headers(page), data })
  expect(response.ok()).toBeTruthy()
  return response.json()
}
async function fixture(page: Page) {
  const space = await post(page, '/storage-spaces', { name: 'E2E Fridge', type: 'FRIDGE' })
  const categories = await read(page, '/item-categories')
  const definition = await post(page, '/item-definitions', { name: 'E2E Apples', category_id: categories.items[0].id })
  const batch = await post(page, '/inventory-items/batch-create', { items: [{ storage_space_id: space.id, item_definition_id: definition.id, amount: '10', unit: 'each' }] })
  return { space, item: batch.items[0] }
}
async function openItem(page: Page, id: string) {
  await page.goto(`/inventory/${id}`)
  await expect(page.getByRole('heading', { name: 'E2E Apples', exact: true })).toBeVisible()
}

test.beforeEach(async ({ page }) => register(page))

test('create, rename, archive and restore an empty storage space', async ({ page }) => {
  await page.goto('/spaces')
  await page.getByLabel('Name', { exact: true }).fill('Browser Fridge')
  await page.getByRole('button', { name: 'Create space', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Rename Browser Fridge', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Rename Browser Fridge', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Name', { exact: true }).fill('Renamed Fridge')
  await dialog.getByRole('button', { name: 'Save', exact: true }).click()
  await page.getByRole('button', { name: 'Archive Renamed Fridge', exact: true }).click()
  await dialog.getByRole('button', { name: 'Archive', exact: true }).click()
  await page.getByRole('button', { name: 'Restore Renamed Fridge', exact: true }).click()
  await page.reload()
  await expect(page.getByRole('button', { name: 'Rename Renamed Fridge', exact: true })).toBeVisible()
  expect((await read(page, '/storage-spaces')).items).toEqual(expect.arrayContaining([expect.objectContaining({ name: 'Renamed Fridge', status: 'ACTIVE' })]))
})

test('create an item through stock-in and see it in inventory and expiry summary', async ({ page }) => {
  await post(page, '/storage-spaces', { name: 'Stock Fridge', type: 'FRIDGE' })
  await page.goto('/inventory/new')
  await page.getByLabel('Item', { exact: true }).fill('Browser Apple')
  const category = page.getByLabel('Category for Browser Apple', { exact: true })
  await expect(category.locator('option')).not.toHaveCount(1)
  await category.selectOption({ index: 1 })
  await page.getByRole('button', { name: 'Create “Browser Apple”', exact: true }).click()
  await page.getByLabel('Quantity', { exact: true }).fill('5')
  await page.getByLabel('Unit', { exact: true }).fill('each')
  const today = await page.evaluate(() => {
    const date = new Date()
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
  })
  await page.getByLabel('Expires', { exact: true }).fill(today)
  await page.getByRole('button', { name: 'Add to batch', exact: true }).click()
  await page.getByRole('button', { name: 'Save 1 item', exact: true }).click()
  await expect(page.getByText('Saved 1 item.', { exact: true })).toBeVisible()
  await page.goto('/inventory')
  await expect(page.getByText('Browser Apple', { exact: true })).toBeVisible()
  await page.reload()
  await expect(page.getByText('Browser Apple', { exact: true })).toBeVisible()
  const inventory = await read(page, '/inventory-items')
  expect(inventory.total).toBe(1)
  expect(Number(inventory.items[0].confirmed_current_amount)).toBe(5)
  await page.goto('/expiry')
  await expect(page.getByText('Browser Apple', { exact: true })).toBeVisible()
  expect((await read(page, `/inventory-items/expiry-summary?as_of=${today}&days_before=3`)).items).toHaveLength(1)
})

test('edit notes and move an item, then preserve changes after reload', async ({ page }) => {
  const { item } = await fixture(page)
  const target = await post(page, '/storage-spaces', { name: 'Target Pantry', type: 'PANTRY' })
  await openItem(page, item.id)
  await page.getByRole('button', { name: 'Edit item', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('Notes', { exact: true }).fill('Edited in the browser')
  await dialog.getByLabel('Storage space', { exact: true }).selectOption(target.id)
  await dialog.getByRole('button', { name: 'Save changes', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await page.reload()
  await expect(page.getByText('Edited in the browser', { exact: true })).toBeVisible()
  expect(await read(page, `/inventory-items/${item.id}`)).toMatchObject({ notes: 'Edited in the browser', storage_space_id: target.id, version: item.version + 1 })
})

test('record consumption and persist the exact amount and operation history', async ({ page }) => {
  const { item } = await fixture(page)
  await openItem(page, item.id)
  await page.getByRole('button', { name: 'Record consumption', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('How much was used?', { exact: true }).fill('2')
  await dialog.getByRole('button', { name: 'Record use', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await page.reload()
  expect(Number((await read(page, `/inventory-items/${item.id}`)).confirmed_current_amount)).toBe(8)
  expect(await read(page, `/inventory-items/${item.id}/operations`)).toEqual(expect.arrayContaining([expect.objectContaining({ operation_type: 'CONSUME', status: 'SUCCESS', quantity_value: '2' })]))
  await expect(page.getByText('1 operation', { exact: true })).toBeVisible()
})

test('reconcile to an exact count and clear the estimated amount', async ({ page }) => {
  const { item } = await fixture(page)
  await openItem(page, item.id)
  await page.getByRole('button', { name: 'Reconcile count', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await dialog.getByLabel('How much is there now?', { exact: true }).fill('3')
  await dialog.getByRole('button', { name: 'Confirm count', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await page.reload()
  const saved = await read(page, `/inventory-items/${item.id}`)
  expect(Number(saved.confirmed_current_amount)).toBe(3)
  expect(saved.estimated_current_amount).toBeNull()
  expect(await read(page, `/inventory-items/${item.id}/operations`)).toEqual(expect.arrayContaining([expect.objectContaining({ operation_type: 'RECONCILE', status: 'SUCCESS' })]))
})

test('archive an item while retaining its read-only record', async ({ page }) => {
  const { item } = await fixture(page)
  await openItem(page, item.id)
  await page.getByRole('button', { name: 'Archive', exact: true }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Archive', exact: true }).click()
  await expect(page.getByText('Read-only', { exact: true })).toBeVisible()
  await page.reload()
  await expect(page.getByRole('button', { name: 'Edit item', exact: true })).toHaveCount(0)
  expect((await read(page, `/inventory-items/${item.id}`)).status).toBe('ARCHIVED')
  expect((await read(page, '/inventory-items?status=IN_STOCK')).total).toBe(0)
})

test('a second user cannot read or change another user’s item or list admin accounts', async ({ page, browser }) => {
  const { item } = await fixture(page)
  const context = await browser.newContext()
  try {
    const other = await context.newPage()
    await register(other)
    await other.goto(`/inventory/${item.id}`)
    await expect(other.getByRole('heading', { name: 'Item not found', exact: true })).toBeVisible()
    const auth = await headers(other)
    expect((await other.request.patch(`${api}/inventory-items/${item.id}`, { headers: auth, data: { expected_version: item.version, notes: 'unauthorized' } })).status()).toBe(404)
    expect((await other.request.get(`${api}/admin/users`, { headers: auth })).status()).toBe(403)
    expect((await read(other, '/inventory-items')).total).toBe(0)
    expect((await read(page, `/inventory-items/${item.id}`)).notes).toBeNull()
  } finally {
    await context.close()
  }
})
