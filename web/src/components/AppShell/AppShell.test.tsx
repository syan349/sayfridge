import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { getToken } from '../../api/tokenStore'
import { signInAs, testAdmin, testUser } from '../../test/fixtures'
import { freezer, fridge, page } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

describe('AppShell', () => {
  it('shows who is signed in at the bottom of the sidebar', async () => {
    signInAs(testUser)
    renderApp('/')

    const sidebar = await screen.findByRole('navigation', { name: 'Main' })
    // No display name on the backend: the name is the part of the email before "@".
    expect(within(sidebar).getByText('tim')).toBeInTheDocument()
    expect(within(sidebar).getByText('tim@example.com')).toBeInTheDocument()
    expect(within(sidebar).queryByText('Admin')).not.toBeInTheDocument()
  })

  it('marks administrators in the account card', async () => {
    signInAs(testAdmin)
    renderApp('/')

    const sidebar = await screen.findByRole('navigation', { name: 'Main' })
    expect(within(sidebar).getByText('Admin')).toBeInTheDocument()
  })

  it('shows counts next to Inventory, Expiry overview and Storage spaces', async () => {
    signInAs(testUser)
    server.use(
      http.get('/api/v1/inventory-items', () => HttpResponse.json(page([], 16))),
      http.get('/api/v1/inventory-items/expiry-summary', () =>
        HttpResponse.json({ ...page([], 0), counts: { overdue: 1, today: 1, upcoming: 2 } }),
      ),
      http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([fridge, freezer, fridge], 3))),
    )
    renderApp('/')

    const sidebar = await screen.findByRole('navigation', { name: 'Main' })
    expect(await within(within(sidebar).getByRole('link', { name: /Inventory/ })).findByText('16')).toBeInTheDocument()
    // Expiry = overdue + today + the next 3 days.
    expect(await within(within(sidebar).getByRole('link', { name: /Expiry overview/ })).findByText('4')).toBeInTheDocument()
    expect(await within(within(sidebar).getByRole('link', { name: /Storage spaces/ })).findByText('3')).toBeInTheDocument()
  })

  it('logs out: forgets the token and goes to sign in', async () => {
    signInAs(testUser)
    const user = userEvent.setup()
    renderApp('/')

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(getToken()).toBeNull()
  })
})
