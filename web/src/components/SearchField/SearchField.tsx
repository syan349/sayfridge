import { useId, type InputHTMLAttributes } from 'react'
import styles from './SearchField.module.css'

interface SearchFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> {
  /** Read by screen readers; the magnifier icon and placeholder show it visually. */
  label: string
}

/** A search box with a magnifier icon. Its label is hidden but still there for screen readers. */
export function SearchField({ label, className, ...inputProps }: SearchFieldProps) {
  const id = useId()
  return (
    <div className={[styles.field, className].filter(Boolean).join(' ')}>
      <svg className={styles.icon} width="15" height="15" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="11" cy="11" r="7" />
        <path d="m20 20-3.5-3.5" />
      </svg>
      <label htmlFor={id} className="visually-hidden">
        {label}
      </label>
      <input id={id} type="search" className={styles.input} {...inputProps} />
    </div>
  )
}
