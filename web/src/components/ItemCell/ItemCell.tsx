import { Link } from 'react-router-dom'
import { foodIconFor } from './foodIcon'
import styles from './ItemCell.module.css'

interface ItemCellProps {
  name: string
  /** When given, the name is a link (e.g. to the item's page). */
  to?: string
}

/** Food icon in a small tile, then the item name. Unknown foods get the first letter instead. */
export function ItemCell({ name, to }: ItemCellProps) {
  const icon = foodIconFor(name)

  return (
    <div className={styles.cell}>
      <span className={styles.tile} aria-hidden="true">
        {icon ? (
          <img src={icon} alt="" width={28} height={28} />
        ) : (
          <span className={styles.letter}>{name.trim().charAt(0).toUpperCase()}</span>
        )}
      </span>
      {to ? (
        <Link to={to} className={`${styles.name} ${styles.link}`}>
          {name}
        </Link>
      ) : (
        <span className={styles.name}>{name}</span>
      )}
    </div>
  )
}
