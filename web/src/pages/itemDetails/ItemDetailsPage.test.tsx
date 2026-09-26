import { fireEvent, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { InventoryItem, InventoryOperation } from '../../api/inventory'
import { signInAs, testUser } from '../../test/fixtures'
import { fridge, freezer, makeOperation, page, tomatoes } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

// Tomatoes: 20 kg at first, 10 kg confirmed, the AI thinks ≈ 9.7 kg are left.
const estimatedTomatoes: InventoryItem = { ...tomatoes, initial_amount: '20.000', initial_unit: 'kg', version: 2 }

const usedSome = makeOperation({
  id: 'op-2',
  inventory_item_id: tomatoes.id,
  operation_type: 'CONSUME',
  quantity_value: '2',
  quantity_unit: 'more',
  input_method: 'VOICE',
  calculation_method: 'AI_ESTIMATED',
  affects_state: 'ESTIMATED',
  applied_change_amount: '0.300',
  applied_change_unit: 'kg',
})
const counted = makeOperation({
  id: 'op-1',
  inventory_item_id: tomatoes.id,
  operation_type: 'RECONCILE',
  quantity_value: '10',
  quantity_unit: 'kg',
  applied_change_amount: null,
  applied_change_unit: null,
  created_at: '2026-09-21T09:15:00Z',
})

// What the fake backend currently holds; tests change these to simulate a write.
let current: InventoryItem
let history: InventoryOperation[]
let itemReads: number

beforeEach(() => {
  current = estimatedTomatoes
  history = [usedSome, counted]
  itemReads = 0
  signInAs(testUser)
  server.use(
    http.get('/api/v1/inventory-items/:id', () => {
      itemReads += 1
      return HttpResponse.json(current)
    }),
    http.get('/api/v1/inventory-items/:id/operations', () => HttpResponse.json(history)),
    http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([freezer, fridge]))),
  )
})

/** The value shown in one of the three quantity cards ("Initial", "Confirmed", "Estimated"). */
function trioCard(label: string) {
  const term = screen.getByText(label, { selector: 'dt' })
  return term.parentElement as HTMLElement
}

describe('ItemDetailsPage (W05)', () => {
  it('shows the three stored amounts and the history, newest first', async () => {
    renderApp(`/inventory/${tomatoes.id}`)

    expect(await screen.findByRole('heading', { level: 1, name: 'Tomatoes' })).toBeInTheDocument()
    expect(trioCard('Initial')).toHaveTextContent('20 kg')
    expect(trioCard('Confirmed')).toHaveTextContent('10 kg')
    expect(trioCard('Estimated')).toHaveTextContent('≈ about 9.7 kg')
    expect(screen.getByText(/because an AI estimate exists/)).toBeInTheDocument()

    const historyCard = screen.getByRole('region', { name: 'Operation history' })
    const entries = await within(historyCard).findAllByRole('listitem')
    expect(entries).toHaveLength(3) // two operations + "batch created"
    expect(entries[0]).toHaveTextContent('Used ≈ 0.3 kg')
    expect(entries[0]).toHaveTextContent('“2 more”') // the user's own words
    expect(entries[1]).toHaveTextContent('Confirmed 10 kg')
    expect(entries[2]).toHaveTextContent('Batch created with 20 kg')
    expect(screen.getByText('2 operations')).toBeInTheDocument()
  })

  it('clears the estimate after a reconcile, and sends the version and an idempotency key', async () => {
    let received: { key: string | null; body: unknown } | null = null
    server.use(
      http.post('/api/v1/inventory-items/:id/operations', async ({ request }) => {
        received = { key: request.headers.get('Idempotency-Key'), body: await request.json() }
        // The backend's answer to a stock check: confirmed 10 kg, no estimate any more.
        current = {
          ...current,
          confirmed_current_amount: '10.000',
          estimated_current_amount: null,
          estimated_current_unit: null,
          estimated_at: null,
          display_amount: '10.000',
          is_estimated: false,
          version: 3,
        }
        history = [makeOperation({ ...counted, id: 'op-3' }), ...history]
        return HttpResponse.json({ operation: history[0], inventory: current, replayed: false }, { status: 201 })
      }),
    )
    const user = userEvent.setup()
    renderApp(`/inventory/${tomatoes.id}`)

    await user.click(await screen.findByRole('button', { name: 'Reconcile count' }))
    const dialog = screen.getByRole('dialog', { name: 'Record a change' })
    expect(within(dialog).getByLabelText('Counted it')).toBeChecked()
    await user.type(within(dialog).getByLabelText('How much is there now?'), '10')
    await user.click(within(dialog).getByRole('button', { name: 'Confirm count' }))

    expect(await screen.findByText('Confirmed 10 kg.')).toBeInTheDocument()
    await waitFor(() => expect(trioCard('Estimated')).toHaveTextContent('No estimate: the confirmed amount is shown'))
    expect(screen.queryByText(/because an AI estimate exists/)).not.toBeInTheDocument()

    expect(received).toEqual({
      key: expect.any(String),
      body: {
        expected_version: 2,
        operation_type: 'RECONCILE',
        quantity_kind: 'AMOUNT',
        quantity_value: '10',
        quantity_unit: 'kg',
      },
    })
  })

  it('asks for confirmation before discarding', async () => {
    let discards = 0
    let discardBody: unknown
    server.use(
      http.post('/api/v1/inventory-items/:id/discard', async ({ request }) => {
        discards += 1
        discardBody = await request.json()
        current = { ...current, status: 'DISCARDED', version: 3 }
        return HttpResponse.json(current)
      }),
    )
    const user = userEvent.setup()
    renderApp(`/inventory/${tomatoes.id}`)

    const dangerZone = await screen.findByRole('region', { name: 'Remove this batch' })
    await user.click(within(dangerZone).getByRole('button', { name: 'Discard' }))

    // Nothing has happened yet: only the question is shown.
    const dialog = screen.getByRole('dialog', { name: 'Discard Tomatoes?' })
    expect(dialog).toHaveTextContent('The item and its whole history stay in the log.')
    expect(discards).toBe(0)

    await user.click(within(dialog).getByRole('button', { name: 'Cancel' }))
    expect(discards).toBe(0)

    await user.click(within(dangerZone).getByRole('button', { name: 'Discard' }))
    await user.click(within(screen.getByRole('dialog', { name: 'Discard Tomatoes?' })).getByRole('button', { name: 'Discard' }))

    expect(await screen.findByText('Discarded.')).toBeInTheDocument()
    expect(discards).toBe(1)
    expect(discardBody).toEqual({ expected_version: 2 })
    // A discarded item can't change any more.
    expect(await screen.findByRole('region', { name: 'Read-only' })).toHaveTextContent('This item is discarded.')
  })

  it('shows the "changed" banner on a 409 and reloads the item', async () => {
    server.use(
      http.post('/api/v1/inventory-items/:id/operations', () =>
        HttpResponse.json({ detail: { code: 'VERSION_CONFLICT', message: 'Inventory version conflict' } }, { status: 409 }),
      ),
    )
    const user = userEvent.setup()
    renderApp(`/inventory/${tomatoes.id}`)

    await user.click(await screen.findByRole('button', { name: 'Record consumption' }))
    const dialog = screen.getByRole('dialog', { name: 'Record a change' })
    await user.type(within(dialog).getByLabelText('How much was used?'), '1')
    await user.click(within(dialog).getByRole('button', { name: 'Record use' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('This item changed since you opened it')
    expect(dialog).not.toHaveAttribute('open')
    await waitFor(() => expect(itemReads).toBeGreaterThan(1)) // the latest version was loaded again
  })

  it('edits only what changed, with the version', async () => {
    let patchBody: unknown
    server.use(
      http.patch('/api/v1/inventory-items/:id', async ({ request }) => {
        patchBody = await request.json()
        current = { ...current, expiry_date: '2026-10-05', notes: 'Opened', version: 3 }
        return HttpResponse.json(current)
      }),
    )
    const user = userEvent.setup()
    renderApp(`/inventory/${tomatoes.id}`)

    await user.click(await screen.findByRole('button', { name: 'Edit item' }))
    const dialog = screen.getByRole('dialog', { name: 'Edit item' })
    // Date inputs are set in one go (typing digit by digit isn't how people use a date picker).
    fireEvent.change(within(dialog).getByLabelText('Expiry date'), { target: { value: '2026-10-05' } })
    await user.type(within(dialog).getByLabelText('Notes'), 'Opened')
    await user.click(within(dialog).getByRole('button', { name: 'Save changes' }))

    expect(await screen.findByText('Saved your changes.')).toBeInTheDocument()
    // The space and purchase date didn't change, so they aren't sent.
    expect(patchBody).toEqual({ expected_version: 2, expiry_date: '2026-10-05', notes: 'Opened' })
  })

  it('opens from the inventory list, and the breadcrumb goes back', async () => {
    server.use(
      http.get('/api/v1/inventory-items', () => HttpResponse.json(page([estimatedTomatoes]))),
      http.get('/api/v1/item-categories', () => HttpResponse.json(page([]))),
    )
    const user = userEvent.setup()
    renderApp('/inventory')

    await user.click(await screen.findByRole('link', { name: 'Tomatoes' }))
    expect(await screen.findByRole('heading', { level: 1, name: 'Tomatoes' })).toBeInTheDocument()

    await user.click(within(screen.getByRole('navigation', { name: 'Breadcrumb' })).getByRole('link', { name: 'Inventory' }))
    expect(await screen.findByRole('heading', { level: 1, name: 'Inventory' })).toBeInTheDocument()
  })

  it('says so when the item does not exist', async () => {
    server.use(
      http.get('/api/v1/inventory-items/:id', () =>
        HttpResponse.json({ detail: { code: 'NOT_FOUND', message: 'Inventory item not found' } }, { status: 404 }),
      ),
    )
    renderApp('/inventory/00000000-0000-4000-8000-000000000000')

    expect(await screen.findByText('This item doesn’t exist, or it isn’t in your inventory.')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to inventory' })).toBeInTheDocument()
  })
})
