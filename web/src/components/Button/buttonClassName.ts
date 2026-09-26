import styles from './Button.module.css'

export type ButtonVariant = 'primary' | 'secondary' | 'soft' | 'danger'
/** sm = table row actions (31px) · md = page header (40px) · lg = auth forms (50px) */
export type ButtonSize = 'sm' | 'md' | 'lg'

export interface ButtonStyleProps {
  variant?: ButtonVariant
  size?: ButtonSize
  /** Optional icon before the label, e.g. '/assets/icons/assistant/add.png'. */
  icon?: string
}

/** Class names shared by <Button> and <ButtonLink>, so a link can look exactly like a button. */
export function buttonClassName({ variant = 'primary', size = 'md' }: ButtonStyleProps, extra?: string): string {
  return [styles.button, styles[variant], styles[size], extra].filter(Boolean).join(' ')
}

export const buttonIconClassName = styles.icon
