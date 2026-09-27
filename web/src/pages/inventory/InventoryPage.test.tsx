import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { InventoryItem } from '../../api/inventory'
import { addDays, todayLocal } from '../../lib/dates'
import { signInAs, testUser } from '../../test/fixtures'
import { dairy, freezer, fridge, milk, page, tomatoes, vegetables, yogurt } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

// Every GET /inventory-items the page sends. Count requests use page_size=1; the table uses 20.
let listRequests: URLSearchParams[] = []

function answerInventory(items: InventoryItem[]) {
  server.use(
    http.get('/api/v1/inventory-items', ({ request }) => {
      const params = new URL(request.url).searchParams
      if (params.get('page_size') === '20') listRequests.push(params)
      return HttpResponse.json(params.get('page_size') === '1' ? page([], items.length) : page(items))
    }),
  )
}

/** The most recent request made for the table (not for a chip count). */
const lastListRequest = () => listRequests[listRequests.length - 1]

beforeEach(() => {
  listRequests = []
  signInAs(testUser)
  server.use(
    http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([freezer, fridge]))),
    http.get('/api/v1/item-categories', () => HttpResponse.json(page([dairy, vegetables]))),
  )
})

describe('InventoryPage (W03)', () => {
  it('lists the items with their quantity, category and space', async () => {
    answerInventory([yogurt, milk, tomatoes])
    renderApp('/inventory')

    const table = await screen.findByRole('table', { name: 'Inventory items' })
    expect(await within(table).findByText('Yogurt')).toBeInTheDocument()
    expect(within(table).getByText('2 L')).toBeInTheDocument()
    expect(within(table).getByText('confirmed 10 kg')).toBeInTheDocument()
    expect(await screen.findByText('3 items across 2 storage spaces')).toBeInTheDocument()
    expect(lastListRequest().get('status')).toBe('IN_STOCK')
  })

  it('changes the request when a filter changes', async () => {
    answerInventory([yogurt, milk])
    const user = userEvent.setup()
    renderApp('/inventory')
    await screen.findByText('Yogurt')

    await user.click(await screen.findByRole('button', { name: /^Fridge/ }))
    await waitFor(() => expect(lastListRequest().get('storage_space_id')).toBe(fridge.id))

    await user.selectOptions(screen.getByLabelText('Category'), 'Dairy')
    await waitFor(() => expect(lastListRequest().get('category_id')).toBe(dairy.id))

    await user.selectOptions(screen.getByLabelText('Status'), 'Archived')
    await waitFor(() => expect(lastListRequest().get('status')).toBe('ARCHIVED'))

    await user.click(screen.getByRole('button', { name: /Expiring ≤ 3 days/ }))
    await waitFor(() => expect(lastListRequest().get('expiry_to')).toBe(addDays(todayLocal(), 3)))

    await user.type(screen.getByLabelText('Search inventory'), 'milk')
    // The search waits for a short pause in typing before it is sent.
    await waitFor(() => expect(lastListRequest().get('q')).toBe('milk'))

    // All filters are sent together.
    expect(lastListRequest().get('storage_space_id')).toBe(fridge.id)
    expect(lastListRequest().get('category_id')).toBe(dairy.id)
  })

  it('moves every selected item in one batch-move request, with each item’s version', async () => {
    answerInventory([yogurt, milk, tomatoes])
    let body: unknown
    server.use(
      http.post('/api/v1/inventory-items/batch-move', async ({ request }) => {
        body = await request.json()
        return HttpResponse.json({ items: [], count: 2 })
      }),
    )
    const user = userEvent.setup()
    renderApp('/inventory')

    await user.click(await screen.findByRole('checkbox', { name: 'Select Yogurt' }))
    await user.click(screen.getByRole('checkbox', { name: 'Select Milk' }))
    expect(screen.getByText('2 items selected')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Move to space' }))
    await user.selectOptions(screen.getByLabelText(/Move 2 items to/), 'Freezer')
    await user.click(screen.getByRole('button', { name: 'Move' }))

    expect(await screen.findByRole('status')).toHaveTextContent('Moved 2 items to Freezer.')
    expect(body).toEqual({
      target_storage_space_id: freezer.id,
      items: [
        { id: yogurt.id, expected_version: yogurt.version },
        { id: milk.id, expected_version: milk.version },
      ],
    })
    expect(screen.queryByText(/selected$/)).not.toBeInTheDocument() // selection cleared
  })

  it('records consumption item by item and reports the one that failed', async () => {
    answerInventory([yogurt, milk])
    const received: { id: string; key: string | null; body: unknown }[] = []
    server.use(
      http.post('/api/v1/inventory-items/:id/operations', async ({ request, params }) => {
        received.push({ id: String(params.id), key: request.headers.get('Idempotency-Key'), body: await request.json() })
        if (params.id === milk.id) {
          return HttpResponse.json(
            { detail: { code: 'VERSION_CONFLICT', message: 'Inventory version conflict' } },
            { status: 409 },
          )
        }
        return HttpResponse.json({ operation: {}, inventory: yogurt, replayed: false }, { status: 201 })
      }),
    )
    const user = userEvent.setup()
    renderApp('/inventory')

    await user.click(await screen.findByRole('checkbox', { name: 'Select all items on this page' }))
    await user.click(screen.getByRole('button', { name: 'Record consumption' }))
    await user.click(screen.getByLabelText('Half'))
    await user.click(screen.getByRole('button', { name: 'Record for 2 items' }))

    const result = await screen.findByRole('status')
    expect(result).toHaveTextContent('Recorded consumption for 1 of 2 items. These didn’t work:')
    expect(within(result).getByRole('listitem')).toHaveTextContent('Milk: It changed since the list was loaded.')

    // One request per item, each with the item's version and its own idempotency key.
    expect(received).toHaveLength(2)
    expect(received.find((r) => r.id === milk.id)?.body).toEqual({
      expected_version: milk.version,
      operation_type: 'CONSUME',
      quantity_kind: 'FRACTION',
      quantity_value: '1/2',
      quantity_unit: 'remaining',
    })
    const keys = received.map((r) => r.key)
    expect(keys.every(Boolean)).toBe(true)
    expect(new Set(keys).size).toBe(2)
  })

  it('shows an empty state for a new household', async () => {
    answerInventory([])
    renderApp('/inventory')

    expect(await screen.findByText('Your inventory is empty.')).toBeInTheDocument()
  })

  it('shows an error with "Try again" when the list cannot be loaded', async () => {
    let calls = 0
    server.use(
      http.get('/api/v1/inventory-items', ({ request }) => {
        if (new URL(request.url).searchParams.get('page_size') === '1') return HttpResponse.json(page([], 1))
        calls += 1
        return calls === 1
          ? HttpResponse.json({ detail: { code: 'SERVER_ERROR', message: 'Database unavailable' } }, { status: 500 })
          : HttpResponse.json(page([yogurt]))
      }),
    )
    const user = userEvent.setup()
    renderApp('/inventory')

    expect(await screen.findByText('We couldn’t load your inventory.')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Yogurt')).toBeInTheDocument()
  })
})
