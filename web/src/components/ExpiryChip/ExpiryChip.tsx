import { daysBetween, formatDate } from '../../lib/dates'
import { expiryLabel, expiryTone } from './expiry'
import styles from './ExpiryChip.module.css'

interface ExpiryChipProps {
  /** YYYY-MM-DD, or null when the item has no expiry date. */
  expiryDate: string | null
  /** Today's date (YYYY-MM-DD) — passed in so tests can fix "today". */
  today: string
}

/** A coloured chip with the time left ("2 days left"), and the date underneath. */
export function ExpiryChip({ expiryDate, today }: ExpiryChipProps) {
  if (!expiryDate) return <span className={styles.none}>No date</span>

  const daysLeft = daysBetween(today, expiryDate)
  const tone = expiryTone(daysLeft)

  return (
    <div>
      <span className={`${styles.chip} ${styles[tone]}`} data-tone={tone}>
        {/* Overdue also gets the warning icon, so it isn't shown by colour alone. */}
        {tone === 'overdue' && (
          <img src="/assets/icons/assistant/warn.png" alt="" width={14} height={14} className={styles.icon} />
        )}
        {expiryLabel(daysLeft)}
      </span>
      <div className={styles.date}>{formatDate(expiryDate)}</div>
    </div>
  )
}
