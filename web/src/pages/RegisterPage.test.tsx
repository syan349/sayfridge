import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { DASHBOARD_HEADING, loginResponse, testUser } from '../test/fixtures'
import { renderApp } from '../test/renderApp'
import { server } from '../test/server'

async function fillForm(email: string, password: string, confirmPassword: string) {
  const user = userEvent.setup()
  if (email) await user.type(screen.getByLabelText('Email'), email)
  if (password) await user.type(screen.getByLabelText('Password'), password)
  if (confirmPassword) await user.type(screen.getByLabelText('Confirm password'), confirmPassword)
  await user.click(screen.getByRole('button', { name: 'Create account' }))
}

describe('RegisterPage (W02)', () => {
  it('checks the email, the password length and the confirmation in the browser', async () => {
    let requests = 0
    server.use(
      http.post('/api/v1/auth/register', () => {
        requests += 1
        return HttpResponse.json(testUser, { status: 201 })
      }),
    )
    renderApp('/register')

    await fillForm('not-an-email', 'short', 'different')

    expect(screen.getByLabelText('Email')).toHaveAccessibleDescription(
      'Enter a valid email address, like name@example.com.',
    )
    expect(screen.getByLabelText('Password')).toHaveAccessibleDescription('Use at least 8 characters.')
    expect(screen.getByLabelText('Confirm password')).toHaveAccessibleDescription('Passwords do not match.')
    expect(requests).toBe(0)
  })

  it('sends only email and password, then signs in and opens the dashboard', async () => {
    let registerBody: unknown
    server.use(
      http.post('/api/v1/auth/register', async ({ request }) => {
        registerBody = await request.json()
        return HttpResponse.json(testUser, { status: 201 })
      }),
      http.post('/api/v1/auth/login', () => HttpResponse.json(loginResponse())),
    )
    renderApp('/register')

    await fillForm('tim@example.com', 'correct-horse', 'correct-horse')

    expect(await screen.findByRole('heading', { level: 1, name: DASHBOARD_HEADING })).toBeInTheDocument()
    // No name, no avatar, no confirmPassword: the backend rejects any extra field.
    expect(registerBody).toEqual({ email: 'tim@example.com', password: 'correct-horse' })
  })

  it('shows "Email is already registered" under the email field', async () => {
    server.use(
      http.post('/api/v1/auth/register', () =>
        HttpResponse.json({ detail: 'Email is already registered' }, { status: 409 }),
      ),
    )
    renderApp('/register')

    await fillForm('tim@example.com', 'correct-horse', 'correct-horse')

    expect(await screen.findByText('Email is already registered')).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toHaveAccessibleDescription('Email is already registered')
    expect(screen.getByLabelText('Email')).toHaveFocus()
  })

  it('goes to sign in with the email filled in if the automatic sign-in fails', async () => {
    server.use(
      http.post('/api/v1/auth/register', () => HttpResponse.json(testUser, { status: 201 })),
      http.post('/api/v1/auth/login', () => HttpResponse.json({ detail: 'Server error' }, { status: 500 })),
    )
    renderApp('/register')

    await fillForm('tim@example.com', 'correct-horse', 'correct-horse')

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent('Your account was created. Sign in to continue.')
    expect(screen.getByLabelText('Email')).toHaveValue('tim@example.com')
  })
})
