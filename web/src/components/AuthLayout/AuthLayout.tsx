import type { ReactNode } from 'react'
import styles from './AuthLayout.module.css'

interface AuthLayoutProps {
  /** Big line at the top of the green panel. */
  headline: ReactNode
  /** Paragraph under the headline. */
  lead: string
  /** Anything below the lead: a checklist on W01, the numbered steps on W02. */
  panelContent?: ReactNode
  /** The line at the very bottom of the panel. */
  panelFooter: ReactNode
  /** W01 uses the wide panel (580px), W02 the narrow one (500px). */
  panelSize?: 'wide' | 'narrow'
  /** The form column. */
  children: ReactNode
}

/** Layout for the sign-in and create-account pages: green brand panel on the left, form on the right. No sidebar. */
export function AuthLayout({ headline, lead, panelContent, panelFooter, panelSize = 'wide', children }: AuthLayoutProps) {
  return (
    <div className={styles.layout}>
      <section aria-label="About SayFridge" className={`${styles.panel} ${styles[panelSize]}`}>
        <div className={styles.brand}>
          <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={52} height={52} className={styles.brandMark} />
          <span className={styles.brandName}>SayFridge</span>
        </div>

        <div className={styles.intro}>
          {/* Styled like a heading, but the page's real <h1> is the form title. */}
          <p className={styles.headline}>{headline}</p>
          <p className={styles.lead}>{lead}</p>
        </div>

        {panelContent}

        <div className={styles.panelFooter}>{panelFooter}</div>
      </section>

      <main className={panelSize === 'narrow' ? `${styles.formColumn} ${styles.formColumnStart}` : styles.formColumn}>
        {children}
      </main>
    </div>
  )
}
