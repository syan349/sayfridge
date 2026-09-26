import type { ReactNode } from 'react'
import styles from './EmptyState.module.css'

interface EmptyStateProps {
  /** One of the app's icons, e.g. '/assets/icons/assistant/warn.png'. */
  icon?: string
  /** One short line: what is (not) here. */
  title: string
  /** A sentence or two more, when needed. */
  children?: ReactNode
  /** The way forward, e.g. a button or link. */
  action?: ReactNode
}

/** "Nothing here" in one friendly block: an icon, one line, and one way forward. */
export function EmptyState({ icon = '/assets/icons/assistant/ai_assistant.png', title, children, action }: EmptyStateProps) {
  return (
    <div className={styles.empty}>
      <span className={styles.tile}>
        <img src={icon} alt="" width={40} height={40} />
      </span>
      <p className={styles.title}>{title}</p>
      {children && <div className={styles.text}>{children}</div>}
      {action && <div className={styles.action}>{action}</div>}
    </div>
  )
}
