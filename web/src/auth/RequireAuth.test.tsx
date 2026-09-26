import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { setToken } from '../api/tokenStore'
import { DASHBOARD_HEADING, loginResponse, signInAs, testAdmin, testUser } from '../test/fixtures'
import { renderApp } from '../test/renderApp'
import { server } from '../test/server'

describe('RequireAuth (route guard)', () => {
  it('sends a signed-out visitor to sign in, then back to the page they wanted', async () => {
    server.use(http.post('/api/v1/auth/login', () => HttpResponse.json(loginResponse())))
    const user = userEvent.setup()
    const { router } = renderApp('/inventory')

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/login')

    await user.type(screen.getByLabelText('Email'), 'tim@example.com')
    await user.type(screen.getByLabelText('Password'), 'correct-horse')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await screen.findByRole('heading', { name: 'Inventory' })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/inventory')
  })

  it('keeps ordinary users out of admin pages', async () => {
    signInAs(testUser)
    const { router } = renderApp('/admin/accounts')

    expect(await screen.findByRole('heading', { level: 1, name: DASHBOARD_HEADING })).toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/')
  })

  it('lets administrators open admin pages', async () => {
    signInAs(testAdmin)
    renderApp('/admin/accounts')

    expect(await screen.findByRole('heading', { name: 'Accounts' })).toBeInTheDocument()
  })

  it('shows an error with "Try again" when the account cannot be loaded', async () => {
    setToken('test-token', 900)
    let calls = 0
    server.use(
      http.get('/api/v1/auth/me', () => {
        calls += 1
        return calls === 1
          ? HttpResponse.json({ detail: 'Internal Server Error' }, { status: 500 })
          : HttpResponse.json(testUser)
      }),
    )
    const user = userEvent.setup()
    renderApp('/')

    expect(await screen.findByRole('alert')).toHaveTextContent('We couldn’t load your account')
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByRole('heading', { level: 1, name: DASHBOARD_HEADING })).toBeInTheDocument()
  })
})
