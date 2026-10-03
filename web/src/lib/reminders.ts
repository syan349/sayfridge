// Reminder preferences. The backend has no place to store them and no push service,
// so (like the phone app, which keeps them on the phone) they live in this browser,
// one set per account. A browser notification can only appear while the app is open.
import type { ExpiryBucket } from '../api/inventory'

export interface ReminderPreferences {
  /** How many days ahead something counts as "expiring soon" (1–7, as in the phone app). */
  daysBefore: number
  /** Show a browser notification, at most once a day, when items need attention. */
  notify: boolean
}

export const DEFAULT_REMINDERS: ReminderPreferences = { daysBefore: 3, notify: false }
export const DAYS_BEFORE_OPTIONS = [1, 3, 5, 7]

const settingsKey = (userId: string) => `sayfridge.reminders.${userId}`
const remindedKey = (userId: string) => `sayfridge.reminded.${userId}`

/** The saved preferences, or the defaults when nothing (valid) is saved. */
export function loadReminders(userId: string): ReminderPreferences {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(settingsKey(userId)) ?? 'null')
    if (typeof saved === 'object' && saved !== null) {
      const { daysBefore, notify } = saved as Partial<ReminderPreferences>
      return {
        daysBefore: DAYS_BEFORE_OPTIONS.includes(daysBefore as number) ? (daysBefore as number) : DEFAULT_REMINDERS.daysBefore,
        notify: notify === true,
      }
    }
  } catch {
    // Storage blocked or the value is damaged: use the defaults.
  }
  return DEFAULT_REMINDERS
}

export function storeReminders(userId: string, preferences: ReminderPreferences): void {
  try {
    localStorage.setItem(settingsKey(userId), JSON.stringify(preferences))
  } catch {
    // Storage blocked: the choice still applies until the page is reloaded.
  }
}

/** Browsers without the Notification API (or the test environment) can't show reminders. */
export function notificationsSupported(): boolean {
  return typeof Notification !== 'undefined'
}

/** "3 items need attention: 1 overdue, 2 expiring within 3 days." — or null when nothing does. */
export function reminderText(counts: Record<ExpiryBucket, number>, daysBefore: number): string | null {
  const soon = counts.today + counts.upcoming
  const total = counts.overdue + soon
  if (total === 0) return null
  const parts = [
    counts.overdue > 0 ? `${counts.overdue} overdue` : null,
    soon > 0 ? `${soon} expiring within ${daysBefore} ${daysBefore === 1 ? 'day' : 'days'}` : null,
  ].filter(Boolean)
  return `${total} ${total === 1 ? 'item needs' : 'items need'} attention: ${parts.join(', ')}.`
}

/**
 * Shows today's reminder if the user allowed notifications and hasn't had one today.
 * `today` is the local date (YYYY-MM-DD). Returns true when a notification was shown.
 */
export function showDailyReminder(userId: string, today: string, text: string): boolean {
  if (!notificationsSupported() || Notification.permission !== 'granted') return false
  try {
    if (localStorage.getItem(remindedKey(userId)) === today) return false
    new Notification('SayFridge', { body: text, icon: '/assets/icons/assistant/ai_assistant.png' })
    localStorage.setItem(remindedKey(userId), today)
    return true
  } catch {
    return false // e.g. a browser that only allows notifications from a service worker
  }
}
