import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { getToken } from '../api/tokenStore'
import { DASHBOARD_HEADING, loginResponse } from '../test/fixtures'
import { renderApp } from '../test/renderApp'
import { server } from '../test/server'

describe('LoginPage (W01)', () => {
  it('signs in and opens the dashboard', async () => {
    let sentBody: unknown
    server.use(
      http.post('/api/v1/auth/login', async ({ request }) => {
        sentBody = await request.json()
        return HttpResponse.json(loginResponse())
      }),
    )
    const user = userEvent.setup()
    renderApp('/login')

    await user.type(screen.getByLabelText('Email'), ' tim@example.com ')
    await user.type(screen.getByLabelText('Password'), 'correct-horse')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await screen.findByRole('heading', { level: 1, name: DASHBOARD_HEADING })).toBeInTheDocument()
    expect(sentBody).toEqual({ email: 'tim@example.com', password: 'correct-horse' }) // email trimmed
    expect(getToken()).toBe('test-token')
  })

  it('shows the backend message when the password is wrong', async () => {
    server.use(
      http.post('/api/v1/auth/login', () =>
        HttpResponse.json({ detail: 'Invalid email or password' }, { status: 401 }),
      ),
    )
    const user = userEvent.setup()
    renderApp('/login')

    await user.type(screen.getByLabelText('Email'), 'tim@example.com')
    await user.type(screen.getByLabelText('Password'), 'wrong-password')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Invalid email or password')
    expect(screen.getByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(getToken()).toBeNull()
  })

  it('checks the fields in the browser before sending anything', async () => {
    let requests = 0
    server.use(
      http.post('/api/v1/auth/login', () => {
        requests += 1
        return HttpResponse.json(loginResponse())
      }),
    )
    const user = userEvent.setup()
    renderApp('/login')

    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    const email = screen.getByLabelText('Email')
    expect(email).toHaveAccessibleDescription('Enter your email address.')
    expect(email).toHaveAttribute('aria-invalid', 'true')
    expect(email).toHaveFocus() // focus moves to the first problem
    expect(screen.getByLabelText('Password')).toHaveAccessibleDescription('Enter your password.')

    await user.type(email, 'tim')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(email).toHaveAccessibleDescription('Enter a valid email address, like name@example.com.')

    expect(requests).toBe(0)
  })

  it('shows a backend validation message under the field it belongs to', async () => {
    server.use(
      http.post('/api/v1/auth/login', () =>
        HttpResponse.json(
          { detail: [{ type: 'value_error', loc: ['body', 'email'], msg: 'The domain name example.invalid does not exist.' }] },
          { status: 422 },
        ),
      ),
    )
    const user = userEvent.setup()
    renderApp('/login')

    await user.type(screen.getByLabelText('Email'), 'tim@example.invalid')
    await user.type(screen.getByLabelText('Password'), 'correct-horse')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await screen.findByText('The domain name example.invalid does not exist.')).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toHaveAccessibleDescription('The domain name example.invalid does not exist.')
  })

  it('shows and hides the password', async () => {
    const user = userEvent.setup()
    renderApp('/login')
    const password = screen.getByLabelText('Password')
    const toggle = screen.getByRole('button', { name: 'Show password' })

    expect(password).toHaveAttribute('type', 'password')
    await user.click(toggle)
    expect(password).toHaveAttribute('type', 'text')
    expect(toggle).toHaveAttribute('aria-pressed', 'true')
    await user.click(toggle)
    expect(password).toHaveAttribute('type', 'password')
  })

  it('opens the guest placeholder from "Continue as guest"', async () => {
    const user = userEvent.setup()
    renderApp('/login')

    await user.click(screen.getByRole('link', { name: 'Continue as guest' }))

    expect(await screen.findByRole('heading', { name: 'Guest mode' })).toBeInTheDocument()
    expect(screen.getByText(/Not connected yet/)).toBeInTheDocument()
  })
})
