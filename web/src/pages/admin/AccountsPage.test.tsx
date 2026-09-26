import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { AdminUser } from '../../api/admin'
import { signInAs, testAdmin } from '../../test/fixtures'
import { page } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

const aroha: AdminUser = {
  id: '10000000-0000-4000-8000-000000000001',
  email: 'aroha@example.com',
  role: 'USER',
  status: 'ACTIVE',
  created_at: '2026-09-20T00:00:00Z',
  updated_at: '2026-09-20T00:00:00Z',
}
const lena: AdminUser = { ...aroha, id: '10000000-0000-4000-8000-000000000002', email: 'lena@example.com', status: 'SUSPENDED' }
const admin: AdminUser = { ...aroha, id: testAdmin.id, email: testAdmin.email, role: 'ADMIN' }

let accounts: AdminUser[]

beforeEach(() => {
  accounts = [admin, aroha, lena]
  signInAs(testAdmin)
  server.use(
    http.get('/api/v1/admin/users', ({ request }) => {
      const params = new URL(request.url).searchParams
      const status = params.get('status')
      const role = params.get('role')
      const shown = accounts.filter(
        (account) => (status === 'ALL' || account.status === status) && (role === 'ALL' || account.role === role),
      )
      return HttpResponse.json(page(shown))
    }),
  )
})

describe('AccountsPage (W11)', () => {
  it('lists accounts with their role and status, and counts per status', async () => {
    renderApp('/admin/accounts')

    const table = await screen.findByRole('table', { name: 'Accounts' })
    expect(await within(table).findByText('aroha@example.com')).toBeInTheDocument()
    expect(within(table).getByText('Suspended')).toBeInTheDocument()
    // Administrators can't be changed from here (the backend refuses it too).
    expect(within(table).getByText('Admins can’t be changed here')).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: 'Suspended · 1' })).toBeInTheDocument()
    expect(await screen.findByText('3 accounts · 1 administrator · 1 suspended')).toBeInTheDocument()
  })

  it('asks for confirmation before suspending an account', async () => {
    let patches = 0
    let body: unknown
    server.use(
      http.patch('/api/v1/admin/users/:id/status', async ({ request, params }) => {
        patches += 1
        body = await request.json()
        accounts = accounts.map((account) => (account.id === params.id ? { ...account, status: 'SUSPENDED' } : account))
        return HttpResponse.json(accounts.find((account) => account.id === params.id))
      }),
    )
    const user = userEvent.setup()
    renderApp('/admin/accounts')

    await user.click(await screen.findByRole('button', { name: 'Suspend aroha@example.com' }))

    const dialog = screen.getByRole('dialog', { name: 'Suspend aroha@example.com?' })
    expect(dialog).toHaveTextContent('Nothing is deleted.')
    expect(patches).toBe(0) // only the question so far

    await user.click(within(dialog).getByRole('button', { name: 'Suspend' }))

    expect(await screen.findByText('Suspended aroha@example.com.')).toBeInTheDocument()
    expect(patches).toBe(1)
    expect(body).toEqual({ status: 'SUSPENDED' })
    // The list reloads: Aroha now offers Reactivate instead of Suspend.
    expect(await screen.findByRole('button', { name: 'Reactivate aroha@example.com' })).toBeInTheDocument()
  })

  it('filters by status with the chips', async () => {
    const user = userEvent.setup()
    renderApp('/admin/accounts')
    await screen.findByText('aroha@example.com')

    await user.click(screen.getByRole('button', { name: /^Suspended/ }))

    await waitFor(() => expect(screen.queryByText('aroha@example.com')).not.toBeInTheDocument())
    expect(screen.getByText('lena@example.com')).toBeInTheDocument()
  })

  it('shows the no-permission state when the backend answers 403', async () => {
    server.use(
      http.get('/api/v1/admin/users', () =>
        HttpResponse.json({ detail: { code: 'FORBIDDEN', message: 'Administrator role required' } }, { status: 403 }),
      ),
    )
    renderApp('/admin/accounts')

    expect(await screen.findByRole('heading', { name: 'You don’t have permission to manage accounts' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Back to the dashboard' })).toBeInTheDocument()
  })
})
