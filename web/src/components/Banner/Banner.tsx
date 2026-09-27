import type { AriaRole, ReactNode } from 'react'
import styles from './Banner.module.css'

type BannerTone = 'info' | 'estimate' | 'warning' | 'danger'

interface BannerProps {
  /** info = green · estimate = orange with the AI icon · warning = orange with ⚠ · danger = red with ⚠ */
  tone: BannerTone
  title?: string
  /** "alert" makes screen readers read it out as soon as it appears. */
  role?: AriaRole
  /** Button(s) at the right, e.g. Dismiss. */
  action?: ReactNode
  children?: ReactNode
}

const ICONS: Record<BannerTone, string> = {
  info: '/assets/icons/assistant/ai_assistant.png',
  estimate: '/assets/icons/assistant/ai_assistant.png',
  warning: '/assets/icons/assistant/warn.png',
  danger: '/assets/icons/assistant/warn.png',
}

/** A coloured message box: explanations, "this item changed" warnings, and the danger zone. */
export function Banner({ tone, title, role, action, children }: BannerProps) {
  return (
    <div role={role} className={`${styles.banner} ${styles[tone]}`}>
      <img src={ICONS[tone]} alt="" width={20} height={20} className={styles.icon} />
      <div className={styles.body}>
        {title && <p className={styles.title}>{title}</p>}
        {children && <div className={styles.text}>{children}</div>}
      </div>
      {action && <div className={styles.action}>{action}</div>}
    </div>
  )
}
