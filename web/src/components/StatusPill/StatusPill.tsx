import styles from './StatusPill.module.css'

type Tone = 'fresh' | 'urgent' | 'soon' | 'overdue' | 'neutral' | 'info'

// Every status (and account role) the backend uses, with its label and colour (design handoff: StatusPill).
const STATUSES: Record<string, { label: string; tone: Tone }> = {
  ADMIN: { label: 'Admin', tone: 'info' },
  USER: { label: 'User', tone: 'neutral' },
  IN_STOCK: { label: 'In stock', tone: 'fresh' },
  ACTIVE: { label: 'Active', tone: 'fresh' },
  EMPTY: { label: 'Empty', tone: 'neutral' },
  DISCARDED: { label: 'Discarded', tone: 'neutral' },
  ARCHIVED: { label: 'Archived', tone: 'neutral' },
  DISABLED: { label: 'Disabled', tone: 'neutral' },
  UNDONE: { label: 'Undone', tone: 'neutral' },
  SUSPENDED: { label: 'Suspended', tone: 'urgent' },
  PENDING_CONFIRMATION: { label: 'Needs confirmation', tone: 'soon' },
  FAILED: { label: 'Failed', tone: 'overdue' },
}

/** A small coloured label for a status such as IN_STOCK or ARCHIVED. */
export function StatusPill({ status }: { status: string }) {
  const { label, tone } = STATUSES[status] ?? { label: status, tone: 'neutral' }
  return <span className={`${styles.pill} ${styles[tone]}`}>{label}</span>
}
