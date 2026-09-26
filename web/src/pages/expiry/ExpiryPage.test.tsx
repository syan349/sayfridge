import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { ExpiryItem } from '../../api/inventory'
import { signInAs, testUser } from '../../test/fixtures'
import { milk, tomatoes, yogurt } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

const items: ExpiryItem[] = [
  { ...yogurt, expiry_date: '2026-09-29', bucket: 'overdue' },
  { ...milk, expiry_date: '2026-09-30', bucket: 'today' },
  { ...tomatoes, expiry_date: '2026-10-02', bucket: 'upcoming' },
]

// Every expiry-summary request the page makes, newest last.
let requests: URLSearchParams[] = []
const lastRequest = () => requests[requests.length - 1]

beforeEach(() => {
  requests = []
  signInAs(testUser)
  server.use(
    http.get('/api/v1/inventory-items/expiry-summary', ({ request }) => {
      const params = new URL(request.url).searchParams
      if (params.get('page_size') === '20') requests.push(params) // the page's table, not the sidebar
      const bucket = params.get('bucket')
      const shown = bucket ? items.filter((item) => item.bucket === bucket) : items
      return HttpResponse.json({
        counts: { overdue: 1, today: 2, upcoming: 4 },
        items: shown,
        total: shown.length,
        page: 1,
        page_size: 20,
      })
    }),
  )
})

describe('ExpiryPage (W09)', () => {
  describe('in New Zealand, just after 9 am on 30 September (still 29 September in UTC)', () => {
    beforeEach(() => {
      vi.stubEnv('TZ', 'Pacific/Auckland') // NZDT = UTC+13, whatever the computer running the tests uses
      vi.useFakeTimers({ toFake: ['Date'] }) // only the clock; timers keep running
      vi.setSystemTime(new Date('2026-09-29T20:30:00Z'))
      signInAs(testUser) // again: the first token was made with the real clock and would count as expired now
    })
    afterEach(() => {
      vi.useRealTimers()
      vi.unstubAllEnvs() // back to the real time zone
    })

    it('sends the local date as as_of, not the UTC date', async () => {
      renderApp('/expiry')

      await waitFor(() => expect(lastRequest()?.get('as_of')).toBe('2026-09-30'))
      expect(lastRequest().get('days_before')).toBe('3')
      expect(screen.getByText(/^Wednesday 30 September 2026/)).toBeInTheDocument()
    })
  })

  it('shows the counts on the tiles, and a tile filters the table by bucket', async () => {
    const user = userEvent.setup()
    renderApp('/expiry')

    const tiles = await screen.findByRole('group', { name: 'Show only' })
    const overdue = within(tiles).getByRole('button', { name: /Overdue/ })
    const today = within(tiles).getByRole('button', { name: /Today/ })
    await waitFor(() => expect(overdue).toHaveTextContent('1'))
    expect(today).toHaveTextContent('2')
    expect(within(tiles).getByRole('button', { name: /Next 3 days/ })).toHaveTextContent('4')
    expect(await screen.findByText('Yogurt')).toBeInTheDocument()
    expect(lastRequest().get('bucket')).toBeNull()

    await user.click(today)
    expect(today).toHaveAttribute('aria-pressed', 'true')
    await waitFor(() => expect(lastRequest().get('bucket')).toBe('today'))
    await waitFor(() => expect(screen.queryByText('Yogurt')).not.toBeInTheDocument())
    expect(screen.getByText('Milk')).toBeInTheDocument()

    // Clicking the chosen tile again shows every group.
    await user.click(today)
    await waitFor(() => expect(lastRequest().get('bucket')).toBeNull())
  })

  it('looks further ahead with the day selector', async () => {
    const user = userEvent.setup()
    renderApp('/expiry')
    await screen.findByText('Yogurt')

    await user.selectOptions(screen.getByLabelText('Look ahead'), 'Next 7 days')

    await waitFor(() => expect(lastRequest().get('days_before')).toBe('7'))
    expect(screen.getByRole('button', { name: /Next 7 days/ })).toBeInTheDocument()
  })

  it('opens the same record dialog as the item page from a row', async () => {
    const user = userEvent.setup()
    renderApp('/expiry')

    // Milk is neither overdue nor estimated, so its main action is "Record use".
    await user.click(await screen.findByRole('button', { name: 'Record use for Milk' }))

    const dialog = screen.getByRole('dialog', { name: 'Record a change' })
    expect(within(dialog).getByLabelText('Used some')).toBeChecked()
    // Overdue Yogurt offers Discard first; estimated Tomatoes offer Reconcile.
    expect(screen.getByRole('button', { name: 'Discard Yogurt' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Reconcile Tomatoes' })).toBeInTheDocument()
  })

  it('says so when nothing is expiring', async () => {
    server.use(
      http.get('/api/v1/inventory-items/expiry-summary', () =>
        HttpResponse.json({ counts: { overdue: 0, today: 0, upcoming: 0 }, items: [], total: 0, page: 1, page_size: 20 }),
      ),
    )
    renderApp('/expiry')

    expect(await screen.findByText('Nothing is overdue or expiring in the next 3 days.')).toBeInTheDocument()
  })
})
