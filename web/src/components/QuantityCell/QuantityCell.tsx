import type { InventoryItem } from '../../api/inventory'
import { AiBadge } from '../AiBadge/AiBadge'
import { formatAmount, isZeroAmount } from './formatAmount'
import styles from './QuantityCell.module.css'

type QuantityFields = Pick<
  InventoryItem,
  'display_amount' | 'display_unit' | 'is_estimated' | 'confirmed_current_amount' | 'confirmed_current_unit'
>

/**
 * How much is left, always in the user's own unit (never converted).
 * - Confirmed: "2 L".
 * - AI estimate: "≈ 9.7 kg" in orange + the AI badge, with the last confirmed
 *   amount underneath. An estimate of zero reads "Possibly used up" — the row
 *   is never hidden, because the estimate may be wrong.
 */
export function QuantityCell({ item }: { item: QuantityFields }) {
  const amount = `${formatAmount(item.display_amount)} ${item.display_unit}`

  if (!item.is_estimated) {
    return <span className={styles.amount}>{amount}</span>
  }

  return (
    <div>
      <div className={styles.line}>
        <span className={`${styles.amount} ${styles.estimated}`}>
          {isZeroAmount(item.display_amount) ? (
            'Possibly used up'
          ) : (
            <>
              <span aria-hidden="true">≈ </span>
              <span className="visually-hidden">about </span>
              {amount}
            </>
          )}
        </span>
        <AiBadge />
      </div>
      <div className={styles.meta}>
        confirmed {formatAmount(item.confirmed_current_amount)} {item.confirmed_current_unit}
      </div>
    </div>
  )
}
