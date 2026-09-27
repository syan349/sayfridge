import { screen, within } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { DASHBOARD_HEADING, signInAs, testUser } from '../../test/fixtures'
import { freezer, fridge, makeOperation, page, tomatoes, yogurt } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

/** A stat tile, found by its label ("In stock"). */
function tile(label: string) {
  return screen.getByText(label, { selector: 'p' }).parentElement as HTMLElement
}

describe('DashboardPage', () => {
  it('works for a brand-new household with no data at all', async () => {
    signInAs(testUser) // the test server's defaults answer every list with nothing
    renderApp('/')

    expect(await screen.findByRole('heading', { level: 1, name: DASHBOARD_HEADING })).toHaveTextContent('tim')
    expect(await screen.findByText('Nothing is overdue or expiring in the next 3 days.')).toBeInTheDocument()
    const spaces = screen.getByRole('region', { name: 'Storage spaces' })
    expect(await within(spaces).findByText(/No storage spaces yet/)).toBeInTheDocument()
    expect(await screen.findByText('No changes recorded yet.')).toBeInTheDocument()
    expect(tile('In stock')).toHaveTextContent(/0\s*items/)
    expect(tile('Needs attention')).toHaveTextContent(/0\s*items/)
    expect(document.title).toBe('Dashboard · SayFridge')
  })

  it('shows what needs attention, how full each space is, and recent activity', async () => {
    signInAs(testUser)
    server.use(
      http.get('/api/v1/inventory-items/expiry-summary', () =>
        HttpResponse.json({
          counts: { overdue: 1, today: 0, upcoming: 1 },
          items: [
            { ...yogurt, expiry_date: '2020-01-01', bucket: 'overdue' },
            { ...tomatoes, bucket: 'upcoming' },
          ],
          total: 2,
          page: 1,
          page_size: 5,
        }),
      ),
      http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([fridge, freezer]))),
      // Counts: 12 in stock overall, 9 in the fridge, 3 in the freezer.
      http.get('/api/v1/inventory-items', ({ request }) => {
        const space = new URL(request.url).searchParams.get('storage_space_id')
        const total = space === fridge.id ? 9 : space === freezer.id ? 3 : 12
        return HttpResponse.json(page([tomatoes], total))
      }),
      http.get('/api/v1/inventory-operations', () =>
        HttpResponse.json(
          page([
            makeOperation({
              id: 'op-1',
              inventory_item_id: tomatoes.id,
              calculation_method: 'AI_ESTIMATED',
              applied_change_amount: '0.300',
              applied_change_unit: 'kg',
            }),
          ]),
        ),
      ),
      http.get('/api/v1/inventory-items/:id', () => HttpResponse.json(tomatoes)),
    )
    renderApp('/')

    const attention = await screen.findByRole('region', { name: 'Needs attention' })
    expect(await within(attention).findByText('Yogurt')).toBeInTheDocument()
    expect(within(attention).getByRole('button', { name: 'Discard Yogurt' })).toBeInTheDocument()
    expect(within(attention).getByRole('button', { name: 'Reconcile Tomatoes' })).toBeInTheDocument()

    expect(tile('Needs attention')).toHaveTextContent(/2\s*items/)
    expect(tile('Needs attention')).toHaveTextContent('1 already overdue')
    expect(await screen.findByText(/^Fridge 9 · Freezer 3$/)).toBeInTheDocument() // In stock tile, per space

    const spaces = screen.getByRole('region', { name: 'Storage spaces' })
    expect(await within(spaces).findByText('9 items')).toBeInTheDocument()
    expect(within(spaces).getByText('3 items')).toBeInTheDocument()

    expect(await screen.findByRole('link', { name: 'Tomatoes — used ≈ 0.3 kg' })).toBeInTheDocument()
  })
})
