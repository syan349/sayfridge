import { afterEach, describe, expect, it, vi } from 'vitest'
import { DEFAULT_REMINDERS, loadReminders, reminderText, showDailyReminder, storeReminders } from './reminders'

afterEach(() => {
  localStorage.clear()
  vi.unstubAllGlobals()
})

describe('reminder preferences', () => {
  it('starts with the defaults and remembers a change per account', () => {
    expect(loadReminders('user-1')).toEqual(DEFAULT_REMINDERS)

    storeReminders('user-1', { daysBefore: 7, notify: true })

    expect(loadReminders('user-1')).toEqual({ daysBefore: 7, notify: true })
    expect(loadReminders('user-2')).toEqual(DEFAULT_REMINDERS) // another account on the same computer
  })

  it('falls back to the defaults when the saved value is damaged', () => {
    localStorage.setItem('sayfridge.reminders.user-1', '{"daysBefore": 99, "notify": "yes"}')
    expect(loadReminders('user-1')).toEqual(DEFAULT_REMINDERS)

    localStorage.setItem('sayfridge.reminders.user-1', 'not json')
    expect(loadReminders('user-1')).toEqual(DEFAULT_REMINDERS)
  })
})

describe('reminderText', () => {
  it('says how many items need attention, and why', () => {
    expect(reminderText({ overdue: 1, today: 1, upcoming: 1 }, 3)).toBe(
      '3 items need attention: 1 overdue, 2 expiring within 3 days.',
    )
    expect(reminderText({ overdue: 0, today: 0, upcoming: 1 }, 1)).toBe('1 item needs attention: 1 expiring within 1 day.')
    expect(reminderText({ overdue: 2, today: 0, upcoming: 0 }, 3)).toBe('2 items need attention: 2 overdue.')
  })

  it('has nothing to say when nothing is due', () => {
    expect(reminderText({ overdue: 0, today: 0, upcoming: 0 }, 3)).toBeNull()
  })
})

describe('showDailyReminder', () => {
  /** A stand-in for the browser's Notification class that records what was shown. */
  function stubNotifications(permission: NotificationPermission) {
    const shown: { title: string; body?: string }[] = []
    class FakeNotification {
      static permission = permission
      constructor(title: string, options?: NotificationOptions) {
        shown.push({ title, body: options?.body })
      }
    }
    vi.stubGlobal('Notification', FakeNotification)
    return shown
  }

  it('shows one notification a day, not one per page load', () => {
    const shown = stubNotifications('granted')

    expect(showDailyReminder('user-1', '2026-10-03', '2 items need attention: 2 overdue.')).toBe(true)
    expect(showDailyReminder('user-1', '2026-10-03', '2 items need attention: 2 overdue.')).toBe(false)
    expect(showDailyReminder('user-1', '2026-10-04', '1 item needs attention: 1 overdue.')).toBe(true)

    expect(shown).toEqual([
      { title: 'SayFridge', body: '2 items need attention: 2 overdue.' },
      { title: 'SayFridge', body: '1 item needs attention: 1 overdue.' },
    ])
  })

  it('shows nothing without the browser’s permission', () => {
    const shown = stubNotifications('denied')

    expect(showDailyReminder('user-1', '2026-10-03', '2 items need attention: 2 overdue.')).toBe(false)
    expect(shown).toEqual([])
  })
})
