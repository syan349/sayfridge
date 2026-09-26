import type { BulkOutcome } from './bulkActions'
import styles from './BulkResult.module.css'

/** What a bulk action did: all done (green), some failed (yellow) or nothing changed (red). */
export function BulkResult({ outcome, onDismiss }: { outcome: BulkOutcome; onDismiss: () => void }) {
  return (
    // status = read out politely; alert = read out straight away (nothing was changed).
    <div role={outcome.kind === 'error' ? 'alert' : 'status'} className={`${styles.result} ${styles[outcome.kind]}`}>
      <div className={styles.text}>
        <p className={styles.message}>{outcome.message}</p>
        {outcome.failures.length > 0 && (
          <ul className={styles.list}>
            {outcome.failures.map((failure, index) => (
              <li key={index}>
                <strong>{failure.name}</strong>: {failure.reason}
              </li>
            ))}
          </ul>
        )}
      </div>
      <button type="button" className={styles.dismiss} aria-label="Dismiss message" onClick={onDismiss}>
        <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M6 6l12 12M18 6 6 18" />
        </svg>
      </button>
    </div>
  )
}
