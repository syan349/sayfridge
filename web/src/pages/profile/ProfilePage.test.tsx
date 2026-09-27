import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import { formatDate, todayLocal } from '../../lib/dates'
import { signInAs, testUser } from '../../test/fixtures'
import { page } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

beforeEach(() => signInAs(testUser))

describe('ProfilePage (W10)', () => {
  it('shows the account from /auth/me, read-only, with counts of the user’s data', async () => {
    server.use(
      http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([], 3))),
      http.get('/api/v1/inventory-items', () => HttpResponse.json(page([], 16))),
      http.get('/api/v1/inventory-operations', () => HttpResponse.json(page([], 248))),
    )
    renderApp('/settings')

    expect(await screen.findByRole('heading', { level: 1, name: 'Profile and settings' })).toBeInTheDocument()
    const personal = screen.getByRole('region', { name: 'Personal information' })
    expect(within(personal).getByText('tim@example.com')).toBeInTheDocument()
    expect(within(personal).getByText('User')).toBeInTheDocument() // role pill
    expect(within(personal).getByText('Active')).toBeInTheDocument() // status pill
    expect(within(personal).getByText(formatDate(todayLocal(new Date(testUser.created_at))))).toBeInTheDocument()
    expect(within(personal).getByText(/can’t be changed here yet/)).toBeInTheDocument()
    expect(within(personal).queryByRole('textbox')).not.toBeInTheDocument() // nothing to edit

    const data = screen.getByRole('region', { name: 'Your data' })
    expect(await within(data).findByText('248')).toBeInTheDocument()
    expect(within(data).getByText('3')).toBeInTheDocument()
    expect(within(data).getByText('16')).toBeInTheDocument()
  })

  it('logs out', async () => {
    const user = userEvent.setup()
    renderApp('/settings')

    const signOut = await screen.findByRole('region', { name: 'Sign out' })
    await user.click(within(signOut).getByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
  })
})
