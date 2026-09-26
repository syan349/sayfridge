import type { InventoryItem } from '../../api/inventory'
import { formatDayMonth } from '../../lib/dates'
import { formatAmount, isZeroAmount } from '../QuantityCell/formatAmount'
import styles from './QuantityStateTrio.module.css'

/**
 * The three amounts the backend stores for one batch, side by side:
 * - Initial: what was first added. Never changes.
 * - Confirmed: the last amount a person actually checked.
 * - Estimated: the AI's guess since that check (may be empty).
 * The page shows the estimate when there is one, otherwise the confirmed amount.
 */
export function QuantityStateTrio({ item }: { item: InventoryItem }) {
  const hasEstimate = item.estimated_current_amount !== null

  return (
    <dl className={styles.trio}>
      <div className={`${styles.card} ${styles.initial}`}>
        <dt className={styles.label}>Initial</dt>
        <dd className={styles.value}>
          {formatAmount(item.initial_amount)} {item.initial_unit}
        </dd>
        <dd className={styles.meta}>What was first added — never changes</dd>
      </div>

      <div className={`${styles.card} ${styles.confirmed}`}>
        <dt className={styles.label}>Confirmed</dt>
        <dd className={styles.value}>
          {formatAmount(item.confirmed_current_amount)} {item.confirmed_current_unit}
        </dd>
        <dd className={styles.meta}>Last amount a person checked · {formatDayMonth(item.confirmed_at)}</dd>
      </div>

      <div className={`${styles.card} ${hasEstimate ? styles.estimated : styles.noEstimate}`}>
        <dt className={styles.label}>
          <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={15} height={15} className={styles.aiIcon} />
          Estimated
        </dt>
        {hasEstimate ? (
          <>
            <dd className={styles.value}>
              <span aria-hidden="true">≈ </span>
              <span className="visually-hidden">about </span>
              {formatAmount(item.estimated_current_amount ?? '')} {item.estimated_current_unit}
            </dd>
            <dd className={styles.meta}>
              {isZeroAmount(item.estimated_current_amount ?? '') ? 'Possibly used up — ' : ''}
              AI estimate since the last check{item.estimated_at ? ` · ${formatDayMonth(item.estimated_at)}` : ''}
            </dd>
          </>
        ) : (
          <>
            <dd className={`${styles.value} ${styles.empty}`}>—</dd>
            <dd className={styles.meta}>No estimate: the confirmed amount is shown</dd>
          </>
        )}
      </div>
    </dl>
  )
}
