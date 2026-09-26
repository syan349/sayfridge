// Calendar dates as the backend sends them: "YYYY-MM-DD" strings, with no time
// and no time zone. The helpers do the maths in UTC so daylight-saving changes
// can never make a "day" 23 or 25 hours long.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

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
