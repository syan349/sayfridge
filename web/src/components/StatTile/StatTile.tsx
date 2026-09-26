import type { ReactNode } from 'react'
import styles from './StatTile.module.css'

interface StatTileProps {
  label: string
  /** Small icon before the label. */
  icon?: string
  /** The big number; undefined while it's loading. */
  value: number | undefined
  /** Word after the number: "items". */
  unit?: string
  /** One line of detail underneath. */
  meta?: ReactNode
  /** attention = orange tile (something needs doing). */
  tone?: 'plain' | 'attention'
}

/** One number with a label — the row of tiles at the top of the dashboard. */
export function StatTile({ label, icon, value, unit, meta, tone = 'plain' }: StatTileProps) {
  return (
    // A plain box, not a named region: the dashboard also has a "Needs attention" card,
    // and two landmarks with the same name would confuse screen-reader users.
    <div className={`${styles.tile} ${styles[tone]}`}>
      <p className={styles.label}>
        {icon && <img src={icon} alt="" width={17} height={17} />}
        {label}
      </p>
      <p className={styles.value}>
        {value ?? '–'}
        {unit && <span className={styles.unit}>{unit}</span>}
      </p>
      {meta && <p className={styles.meta}>{meta}</p>}
    </div>
  )
}
