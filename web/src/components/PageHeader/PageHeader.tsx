import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import styles from './PageHeader.module.css'

interface Crumb {
  label: string
  /** Leave out for the current page (the last crumb). */
  to?: string
}

interface PageHeaderProps {
  title: string
  subtitle?: ReactNode
  /** Right-hand side: search box, primary button, … */
  actions?: ReactNode
  /** The path above the title: Inventory / Fridge / Tomatoes. */
  breadcrumb?: Crumb[]
  /** A picture before the title, e.g. the food icon. */
  leading?: ReactNode
  /** Small chips right after the title, e.g. status and expiry. */
  titleExtras?: ReactNode
}

/** White bar at the top of every signed-in page. Holds the page's only <h1>. */
export function PageHeader({ title, subtitle, actions, breadcrumb, leading, titleExtras }: PageHeaderProps) {
  return (
    <header className={styles.header}>
      {/* React puts <title> into the document head: the browser tab shows the page name. */}
      <title>{`${title} · SayFridge`}</title>

      {breadcrumb && (
        <nav aria-label="Breadcrumb">
          <ol className={styles.breadcrumb}>
            {breadcrumb.map((crumb, index) => (
              <li key={index}>
                {crumb.to ? (
                  <Link to={crumb.to}>{crumb.label}</Link>
                ) : (
                  <span aria-current="page">{crumb.label}</span>
                )}
              </li>
            ))}
          </ol>
        </nav>
      )}

      <div className={styles.row}>
        {leading}
        <div className={styles.text}>
          <div className={styles.titleRow}>
            <h1 className={styles.title}>{title}</h1>
            {titleExtras}
          </div>
          {subtitle && <p className={styles.subtitle}>{subtitle}</p>}
        </div>
        {actions && <div className={styles.actions}>{actions}</div>}
      </div>
    </header>
  )
}
