import type { ReactNode } from 'react'
import styles from './Card.module.css'

interface CardProps {
  title: string
  /** Small grey text or a pill next to the title. */
  aside?: ReactNode
  /** Something at the right end of the title row, e.g. a link. */
  action?: ReactNode
  className?: string
  children: ReactNode
}

/** A white rounded box with a title — the building block of the detail and dashboard pages. */
export function Card({ title, aside, action, className, children }: CardProps) {
  return (
    <section className={[styles.card, className].filter(Boolean).join(' ')} aria-label={title}>
      <div className={styles.head}>
        <h2 className={styles.title}>{title}</h2>
        {aside && <span className={styles.aside}>{aside}</span>}
        {action && <span className={styles.action}>{action}</span>}
      </div>
      {children}
    </section>
  )
}
