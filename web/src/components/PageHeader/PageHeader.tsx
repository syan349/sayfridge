import type { ReactNode } from 'react'
import styles from './PageHeader.module.css'

interface PageHeaderProps {
  title: string
  subtitle?: ReactNode
  /** Right-hand side: search box, primary button, … */
  actions?: ReactNode
}

/** White bar at the top of every signed-in page. Holds the page's only <h1>. */
export function PageHeader({ title, subtitle, actions }: PageHeaderProps) {
  return (
    <header className={styles.header}>
      {/* React puts <title> into the document head: the browser tab shows the page name. */}
      <title>{`${title} · SayFridge`}</title>
      <div className={styles.text}>
        <h1 className={styles.title}>{title}</h1>
        {subtitle && <p className={styles.subtitle}>{subtitle}</p>}
      </div>
      {actions && <div className={styles.actions}>{actions}</div>}
    </header>
  )
}
