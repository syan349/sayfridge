import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { foodIconFor } from './foodIcon'
import styles from './ItemCell.module.css'

interface ItemCellProps {
  name: string
  /** When given, the name is a link (e.g. to the item's page). */
  to?: string
  /** A small grey line under the name, e.g. "Dairy · Fridge · consume 2 each". */
  detail?: ReactNode
}

/** Food icon in a small tile, then the item name. Unknown foods get the first letter instead. */
export function ItemCell({ name, to, detail }: ItemCellProps) {
  const icon = foodIconFor(name)
  const nameElement = to ? (
    <Link to={to} className={`${styles.name} ${styles.link}`}>
      {name}
    </Link>
  ) : (
    <span className={styles.name}>{name}</span>
  )

  return (
    <div className={styles.cell}>
      <span className={styles.tile} aria-hidden="true">
        {icon ? (
          <img src={icon} alt="" width={28} height={28} />
        ) : (
          <span className={styles.letter}>{name.trim().charAt(0).toUpperCase()}</span>
        )}
      </span>
      {detail ? (
        <span className={styles.text}>
          {nameElement}
          <span className={styles.detail}>{detail}</span>
        </span>
      ) : (
        nameElement
      )}
    </div>
  )
}
