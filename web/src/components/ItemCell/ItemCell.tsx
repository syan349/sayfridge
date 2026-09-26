import { foodIconFor } from './foodIcon'
import styles from './ItemCell.module.css'

/** Food icon in a small tile, then the item name. Unknown foods get the first letter instead. */
export function ItemCell({ name }: { name: string }) {
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
      <span className={styles.name}>{name}</span>
    </div>
  )
}
