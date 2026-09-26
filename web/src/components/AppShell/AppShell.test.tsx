import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { getToken } from '../../api/tokenStore'
import { signInAs, testAdmin, testUser } from '../../test/fixtures'
import { renderApp } from '../../test/renderApp'

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

  it('logs out: forgets the token and goes to sign in', async () => {
    signInAs(testUser)
    const user = userEvent.setup()
    renderApp('/')

    await user.click(await screen.findByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(getToken()).toBeNull()
  })
})
