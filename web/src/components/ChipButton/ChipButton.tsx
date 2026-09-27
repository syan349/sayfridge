import type { ButtonHTMLAttributes } from 'react'
import styles from './ChipButton.module.css'

interface ChipButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /** Filled in green when on. Screen readers hear it as a toggle ("pressed"). */
  selected?: boolean
  /** "urgent" = the orange "Expiring ≤ 3 days" chip. */
  tone?: 'default' | 'urgent'
  /** Optional icon before the label. */
  icon?: string
}

/** A small filter button that is either on or off. */
export function ChipButton({ selected = false, tone = 'default', icon, className, children, ...rest }: ChipButtonProps) {
  const classes = [styles.chip, tone === 'urgent' ? styles.urgent : '', selected ? styles.selected : '', className]
    .filter(Boolean)
    .join(' ')
  return (
    <button type="button" aria-pressed={selected} className={classes} {...rest}>
      {icon && <img src={icon} alt="" width={17} height={17} className={styles.icon} />}
      {children}
    </button>
  )
}
