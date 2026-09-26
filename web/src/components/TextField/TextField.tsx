import { useId, type InputHTMLAttributes, type ReactNode } from 'react'
import styles from './TextField.module.css'

export interface TextFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string
  /** Help text under the field, e.g. "At least 8 characters". Hidden while there is an error. */
  hint?: string
  /** Error message under the field. Also marks the input as invalid for screen readers. */
  error?: string
  /** Something inside the right edge of the input, e.g. the show-password button. */
  trailing?: ReactNode
}

/** A labelled input with an optional hint and error message. */
export function TextField({ label, hint, error, trailing, id, className, ...inputProps }: TextFieldProps) {
  const generatedId = useId()
  const inputId = id ?? generatedId
  const messageId = `${inputId}-message`
  const message = error ?? hint

  const inputClasses = [styles.input, trailing ? styles.withTrailing : '', error ? styles.invalid : '']
    .filter(Boolean)
    .join(' ')

  return (
    <div className={[styles.field, className].filter(Boolean).join(' ')}>
      <label htmlFor={inputId} className={styles.label}>
        {label}
      </label>
      <div className={styles.control}>
        <input
          id={inputId}
          className={inputClasses}
          aria-invalid={error ? true : undefined}
          // Screen readers read the hint or error after the label.
          aria-describedby={message ? messageId : undefined}
          {...inputProps}
        />
        {trailing && <div className={styles.trailing}>{trailing}</div>}
      </div>
      {error ? (
        <p id={messageId} className={styles.error}>
          <ErrorIcon />
          {error}
        </p>
      ) : (
        hint && (
          <p id={messageId} className={styles.hint}>
            {hint}
          </p>
        )
      )}
    </div>
  )
}

function ErrorIcon() {
  return (
    <svg className={styles.errorIcon} width="15" height="15" viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="9" />
      <path d="M9 9l6 6M15 9l-6 6" />
    </svg>
  )
}
