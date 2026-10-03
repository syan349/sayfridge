import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { formatDate, todayLocal } from '../../lib/dates'
import { signInAs, testUser } from '../../test/fixtures'
import { page } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

beforeEach(() => signInAs(testUser))

afterEach(() => {
  localStorage.clear() // reminder preferences live there
  vi.unstubAllGlobals()
})

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

  it('saves the “expiring soon” preference in the browser, and the sidebar count uses it at once', async () => {
    const asked: (string | null)[] = []
    server.use(
      http.get('/api/v1/inventory-items/expiry-summary', ({ request }) => {
        asked.push(new URL(request.url).searchParams.get('days_before'))
        return HttpResponse.json({ ...page([]), counts: { overdue: 0, today: 0, upcoming: 0 } })
      }),
    )
    const user = userEvent.setup()
    renderApp('/settings')

    const reminders = await screen.findByRole('region', { name: 'Reminders' })
    await waitFor(() => expect(asked).toContain('3')) // the default, asked by the sidebar
    await user.selectOptions(within(reminders).getByLabelText(/expiring soon/), '7 days')

    await waitFor(() => expect(asked.at(-1)).toBe('7'))
    expect(within(reminders).getByRole('status')).toHaveTextContent('Saved.')
    expect(JSON.parse(localStorage.getItem(`sayfridge.reminders.${testUser.id}`)!)).toEqual({ daysBefore: 7, notify: false })
  })

  it('turns the daily notification on only with the browser’s permission', async () => {
    let answer: NotificationPermission = 'denied'
    class FakeNotification {
      static permission: NotificationPermission = 'default'
      static requestPermission = async () => answer
    }
    vi.stubGlobal('Notification', FakeNotification)
    const user = userEvent.setup()
    renderApp('/settings')

    const reminders = await screen.findByRole('region', { name: 'Reminders' })
    const checkbox = within(reminders).getByRole('checkbox', { name: /browser notification once a day/ })
    await user.click(checkbox)
    expect(await within(reminders).findByText(/Notifications are blocked for this site/)).toBeInTheDocument()
    expect(checkbox).not.toBeChecked()

    answer = 'granted'
    await user.click(checkbox)
    await waitFor(() => expect(checkbox).toBeChecked())
    expect(within(reminders).getByRole('status')).toHaveTextContent('one notification a day')
  })

  it('explains that there are no notifications in this browser, and no voice quota', async () => {
    renderApp('/settings') // the test browser has no Notification support

    const reminders = await screen.findByRole('region', { name: 'Reminders' })
    expect(within(reminders).getByRole('checkbox')).toBeDisabled()
    expect(within(reminders).getByText(/This browser can’t show notifications/)).toBeInTheDocument()
    expect(within(screen.getByRole('region', { name: 'Voice input' })).getByText(/no voice quota/)).toBeInTheDocument()
  })

  it('logs out', async () => {
    const user = userEvent.setup()
    renderApp('/settings')

    const signOut = await screen.findByRole('region', { name: 'Sign out' })
    await user.click(within(signOut).getByRole('button', { name: 'Log out' }))

    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
  })
})
