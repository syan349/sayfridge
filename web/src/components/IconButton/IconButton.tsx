import type { ButtonHTMLAttributes, ReactNode } from 'react'
import styles from './IconButton.module.css'

interface IconButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label'> {
  /** Required: an icon alone says nothing to a screen reader. "Rename Kitchen fridge". */
  label: string
  /** An inline SVG (decorative; the label is what gets read out). */
  children: ReactNode
}

/** A small square button with only an icon — pencil, archive box, ×. */
export function IconButton({ label, children, type = 'button', className, ...rest }: IconButtonProps) {
  return (
    <button type={type} aria-label={label} title={label} className={[styles.button, className].filter(Boolean).join(' ')} {...rest}>
      {children}
    </button>
  )
}
