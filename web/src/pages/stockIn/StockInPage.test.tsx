import { fireEvent, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { ItemDefinition } from '../../api/itemDefinitions'
import { signInAs, testUser } from '../../test/fixtures'
import { dairy, freezer, fridge, page } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

const milk: ItemDefinition = { id: 'def-milk', name: 'Milk', category_id: dairy.id, status: 'ACTIVE', scope: 'PUBLIC' }
const eggs: ItemDefinition = { ...milk, id: 'def-eggs', name: 'Eggs' }
const definitions = [milk, eggs]

beforeEach(() => {
  signInAs(testUser)
  server.use(
    http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([fridge, freezer]))),
    http.get('/api/v1/item-categories', () => HttpResponse.json(page([dairy]))),
    http.get('/api/v1/item-definitions', ({ request }) => {
      const q = (new URL(request.url).searchParams.get('q') ?? '').toLowerCase()
      return HttpResponse.json(page(definitions.filter((d) => d.name.toLowerCase().includes(q))))
    }),
  )
})

/** Fills the "New item" form for one item and adds it to the batch. */
async function addRow(user: ReturnType<typeof userEvent.setup>, search: string, amount: string, unit: string, expiry = '') {
  const form = screen.getByRole('region', { name: 'New item' })
  await user.type(within(form).getByLabelText('Item'), search)
  await user.click(await within(form).findByRole('button', { name: new RegExp(`^${search}`, 'i') }))
  await user.type(within(form).getByLabelText('Quantity'), amount)
  await user.type(within(form).getByLabelText('Unit'), unit)
  if (expiry) fireEvent.change(within(form).getByLabelText('Expires'), { target: { value: expiry } })
  await user.click(within(form).getByRole('button', { name: 'Add to batch' }))
}

describe('StockInPage (W06)', () => {
  it('saves the whole batch with ONE batch-create request, amounts as text', async () => {
    let body: unknown
    let requests = 0
    server.use(
      http.post('/api/v1/inventory-items/batch-create', async ({ request }) => {
        requests += 1
        body = await request.json()
        return HttpResponse.json({ items: [], count: 2 }, { status: 201 })
      }),
    )
    const user = userEvent.setup()
    renderApp('/inventory/new')
    await screen.findByRole('option', { name: 'Fridge' })

    await addRow(user, 'Milk', '2.5', 'L', '2026-10-03')
    await addRow(user, 'Eggs', '12', 'each')
    expect(screen.getByText('2 items ready')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Save 2 items' }))

    expect(await screen.findByText('Saved 2 items.')).toBeInTheDocument()
    expect(requests).toBe(1)
    expect(body).toEqual({
      items: [
        { storage_space_id: fridge.id, item_definition_id: milk.id, amount: '2.5', unit: 'L', expiry_date: '2026-10-03' },
        { storage_space_id: fridge.id, item_definition_id: eggs.id, amount: '12', unit: 'each' },
      ],
    })
    expect(screen.getByText('Nothing in the batch yet. Add items with the form above.')).toBeInTheDocument()
  })

  it('highlights the row the backend rejected (item_index) and keeps the whole batch', async () => {
    server.use(
      http.post('/api/v1/inventory-items/batch-create', () =>
        HttpResponse.json(
          { detail: { code: 'STATE_CONFLICT', message: 'Item definition is archived', item_index: 1 } },
          { status: 409 },
        ),
      ),
    )
    const user = userEvent.setup()
    renderApp('/inventory/new')
    await screen.findByRole('option', { name: 'Fridge' })

    await addRow(user, 'Milk', '2', 'L')
    await addRow(user, 'Eggs', '12', 'each')
    await user.click(screen.getByRole('button', { name: 'Save 2 items' }))

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('Nothing was saved.')
    expect(alert).toHaveTextContent('Row 2 (Eggs): Item definition is archived')

    const table = screen.getByRole('table', { name: 'Items to add' })
    const [milkRow, eggsRow] = within(table).getAllByRole('row').slice(1) // skip the header row
    expect(eggsRow).toHaveTextContent('This row stopped the save')
    expect(milkRow).not.toHaveTextContent('This row stopped the save')
    // Nothing is lost: both rows are still there to fix and save again.
    expect(screen.getByText('2 items ready')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save 2 items' })).toBeEnabled()
  })

  it('checks the new item before adding it to the batch', async () => {
    const user = userEvent.setup()
    renderApp('/inventory/new')
    await screen.findByRole('option', { name: 'Fridge' })

    const form = screen.getByRole('region', { name: 'New item' })
    await user.type(within(form).getByLabelText('Quantity'), '1.2345')
    await user.click(within(form).getByRole('button', { name: 'Add to batch' }))

    expect(within(form).getByText('Choose an item from the list, or create your own.')).toBeInTheDocument()
    expect(within(form).getByLabelText('Quantity')).toHaveAccessibleDescription('Use a number like 2 or 0.25 (up to 3 decimals).')
    expect(within(form).getByLabelText('Unit')).toHaveAccessibleDescription('Enter a unit, e.g. g, kg, L or each.')
    expect(screen.getByText('0 items ready')).toBeInTheDocument()
  })

  it('creates your own (private) item when nothing matches', async () => {
    let body: unknown
    server.use(
      http.post('/api/v1/item-definitions', async ({ request }) => {
        body = await request.json()
        return HttpResponse.json(
          { id: 'def-rice', name: 'Brown rice', category_id: dairy.id, status: 'ACTIVE', scope: 'PRIVATE' },
          { status: 201 },
        )
      }),
    )
    const user = userEvent.setup()
    renderApp('/inventory/new')

    const form = await screen.findByRole('region', { name: 'New item' })
    await user.type(within(form).getByLabelText('Item'), 'Brown rice')
    expect(await within(form).findByText('No item called “Brown rice” yet.')).toBeInTheDocument()

    await user.selectOptions(within(form).getByLabelText('Category for Brown rice'), 'Dairy')
    await user.click(within(form).getByRole('button', { name: 'Create “Brown rice”' }))

    expect(await within(form).findByText('Yours')).toBeInTheDocument() // chosen, and marked as private
    expect(within(form).getByText('Brown rice')).toBeInTheDocument()
    expect(body).toEqual({ name: 'Brown rice', category_id: dairy.id })
  })
})
