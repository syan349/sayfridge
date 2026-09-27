import styles from './AiBadge.module.css'

interface AiBadgeProps {
  /** Icon only, for tight spots. The full badge adds the "AI EST." label. */
  compact?: boolean
}

/**
 * Marks a number as an AI estimate. Colour alone isn't enough (the estimated
 * orange and the confirmed green look alike to colour-blind users), so an
 * estimate always shows this badge and the "≈" sign too.
 */
export function AiBadge({ compact = false }: AiBadgeProps) {
  if (compact) {
    return (
      <img src="/assets/icons/assistant/ai_assistant.png" alt="AI estimate" width={15} height={15} className={styles.icon} />
    )
  }
  return (
    <span className={styles.badge}>
      <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={14} height={14} className={styles.icon} />
      <span aria-hidden="true" className={styles.label}>
        AI EST.
      </span>
      <span className="visually-hidden">AI estimate</span>
    </span>
  )
}
