// Calendar dates as the backend sends them: "YYYY-MM-DD" strings, with no time
// and no time zone. The helpers do the maths in UTC so daylight-saving changes
// can never make a "day" 23 or 25 hours long.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const MONTHS_LONG = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

function toUtc(isoDate: string): number {
  const [year, month, day] = isoDate.split('-').map(Number)
  return Date.UTC(year, month - 1, day)
}

/** Today's date where the user is (not in UTC: at 11 pm in Auckland it is still today). */
export function todayLocal(now: Date = new Date()): string {
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')
  return `${now.getFullYear()}-${month}-${day}`
}

/** "2026-09-26" + 3 → "2026-09-29" */
export function addDays(isoDate: string, days: number): string {
  return new Date(toUtc(isoDate) + days * 86_400_000).toISOString().slice(0, 10)
}

/** Whole days from `from` to `to`; negative when `to` is earlier. */
export function daysBetween(from: string, to: string): number {
  return Math.round((toUtc(to) - toUtc(from)) / 86_400_000)
}

/** "2026-09-27" → "27 Sep 2026" (built by hand: browsers disagree on "Sep" vs "Sept"). */
export function formatDate(isoDate: string): string {
  const [year, month, day] = isoDate.split('-').map(Number)
  return `${day} ${MONTHS[month - 1]} ${year}`
}

/** "2026-09-26" → "Saturday 26 September 2026" */
export function formatLongDate(isoDate: string): string {
  const date = new Date(toUtc(isoDate))
  return `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()} ${MONTHS_LONG[date.getUTCMonth()]} ${date.getUTCFullYear()}`
}

// Timestamps ("2026-09-22T07:32:00Z") are moments in time, so unlike the
// calendar dates above they are shown in the user's own time zone.

/** "2026-09-22T07:32:00Z" → "22 Sep" (local time) */
export function formatDayMonth(timestamp: string): string {
  const date = new Date(timestamp)
  return `${date.getDate()} ${MONTHS[date.getMonth()]}`
}

/** "2026-09-22T07:32:00Z" → "22 Sep, 7:32 PM" (local time) — the timeline format. */
export function formatDateTime(timestamp: string): string {
  const date = new Date(timestamp)
  const hours = date.getHours()
  const minutes = String(date.getMinutes()).padStart(2, '0')
  return `${formatDayMonth(timestamp)}, ${hours % 12 || 12}:${minutes} ${hours < 12 ? 'AM' : 'PM'}`
}

/** For activity lists: "just now", "5 min ago", "3 h ago", "Yesterday", then "22 Sep". */
export function formatRelative(timestamp: string, now: Date = new Date()): string {
  const then = new Date(timestamp)
  const minutes = Math.floor((now.getTime() - then.getTime()) / 60_000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes} min ago`
  const day = todayLocal(then)
  if (day === todayLocal(now)) return `${Math.floor(minutes / 60)} h ago`
  if (day === addDays(todayLocal(now), -1)) return 'Yesterday'
  return formatDayMonth(timestamp)
}

/** "Good morning" before 12, "Good afternoon" before 6 pm, then "Good evening" (local time). */
export function greeting(now: Date = new Date()): string {
  const hour = now.getHours()
  if (hour < 12) return 'Good morning'
  if (hour < 18) return 'Good afternoon'
  return 'Good evening'
}
