import type { InventoryItem, InventoryOperation } from '../../api/inventory'
import { formatDateTime } from '../../lib/dates'
import { AiBadge } from '../AiBadge/AiBadge'
import { formatAmount } from '../QuantityCell/formatAmount'
import { StatusPill } from '../StatusPill/StatusPill'
import { MethodTag, TypeTag } from '../Tag/Tag'
import styles from './OperationTimeline.module.css'

/** "Added 500 g", "Used ≈ 0.3 kg", "Confirmed 10 kg" */
function titleFor(operation: InventoryOperation): string {
  const applied =
    operation.applied_change_amount !== null
      ? `${formatAmount(operation.applied_change_amount)} ${operation.applied_change_unit ?? ''}`.trim()
      : `${operation.quantity_value} ${operation.quantity_unit ?? ''}`.trim()
  const approx = operation.calculation_method === 'AI_ESTIMATED' ? '≈ ' : ''

  switch (operation.operation_type) {
    case 'ADD':
      return `Added ${approx}${applied}`
    case 'CONSUME':
      return `Used ${approx}${applied}`
    case 'RECONCILE':
      // A stock check stores the new total, not a change.
      return `Confirmed ${operation.quantity_value} ${operation.quantity_unit ?? ''}`.trim()
  }
}

/** The user's own words, as the design asks: "“1/2 of what was left”", "“500 g”". */
function wordsFor(operation: InventoryOperation): string {
  const words =
    operation.quantity_kind === 'FRACTION'
      ? `“${operation.quantity_value} of what was left”`
      : `“${operation.quantity_value}${operation.quantity_unit ? ` ${operation.quantity_unit}` : ''}”`

  const notes: string[] = []
  if (operation.status !== 'SUCCESS') notes.push('not applied to the amount')
  if (operation.operation_type === 'RECONCILE') notes.push('replaced the confirmed amount and cleared any estimate')
  if (operation.calculation_method === 'CONVERTED') notes.push(`converted to ${operation.applied_change_unit}`)
  return notes.length ? `${words} — ${notes.join(', ')}` : words
}

function dotClass(operation: InventoryOperation): string {
  if (operation.status !== 'SUCCESS') return styles.dotInactive
  if (operation.calculation_method === 'AI_ESTIMATED') return styles.dotEstimated
  if (operation.operation_type === 'RECONCILE') return styles.dotConfirmed
  return styles.dotExact
}

interface OperationTimelineProps {
  /** Newest first, as the backend sends them. */
  operations: InventoryOperation[]
  /** Used for the last entry: when and how much the batch was created with. */
  item: InventoryItem
}

/** Every change to one item, newest first, ending with the moment the batch was created. */
export function OperationTimeline({ operations, item }: OperationTimelineProps) {
  return (
    <ol className={styles.timeline}>
      {operations.map((operation) => (
        <li key={operation.id} className={operation.status === 'SUCCESS' ? styles.entry : `${styles.entry} ${styles.inactive}`}>
          <span className={`${styles.dot} ${dotClass(operation)}`} aria-hidden="true" />
          <div className={styles.main}>
            <div className={styles.titleRow}>
              <span className={styles.title}>{titleFor(operation)}</span>
              <TypeTag type={operation.operation_type} />
              <MethodTag method={operation.input_method} />
              {operation.calculation_method === 'AI_ESTIMATED' && <AiBadge />}
              {operation.status !== 'SUCCESS' && <StatusPill status={operation.status} />}
            </div>
            <p className={styles.meta}>{wordsFor(operation)}</p>
          </div>
          <time dateTime={operation.created_at} className={styles.time}>
            {formatDateTime(operation.created_at)}
          </time>
        </li>
      ))}

      {/* Creating a batch writes no operation, so this last entry comes from the item itself. */}
      <li className={styles.entry}>
        <span className={`${styles.dot} ${styles.dotBatch}`} aria-hidden="true" />
        <div className={styles.main}>
          <div className={styles.titleRow}>
            <span className={styles.title}>
              Batch created with {formatAmount(item.initial_amount)} {item.initial_unit}
            </span>
          </div>
          <p className={styles.meta}>The starting amount of this batch</p>
        </div>
        <time dateTime={item.created_at} className={styles.time}>
          {formatDateTime(item.created_at)}
        </time>
      </li>
    </ol>
  )
}
