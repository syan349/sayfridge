import type { InventoryOperation } from '../../api/inventory'
import styles from './Tag.module.css'

const TYPE_TONES: Record<InventoryOperation['operation_type'], string> = {
  ADD: styles.fresh,
  CONSUME: styles.urgent,
  RECONCILE: styles.info,
}

/** ADD (green), CONSUME (orange), RECONCILE (blue). */
export function TypeTag({ type }: { type: InventoryOperation['operation_type'] }) {
  return <span className={`${styles.tag} ${TYPE_TONES[type]}`}>{type}</span>
}

/** How the change was entered: TEXT, VOICE, PHOTO, RECEIPT or MANUAL (always grey). */
export function MethodTag({ method }: { method: InventoryOperation['input_method'] }) {
  return <span className={`${styles.tag} ${styles.neutral}`}>{method}</span>
}
