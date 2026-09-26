import { useId, type SelectHTMLAttributes } from 'react'
import styles from './ChipButton.module.css'

interface ChipSelectProps extends SelectHTMLAttributes<HTMLSelectElement> {
  /** Read by screen readers; not shown, because the selected option already says what it is. */
  label: string
  options: { value: string; label: string }[]
}

/** A dropdown filter that looks like a chip ("All categories ▾"). It is a real <select>. */
export function ChipSelect({ label, options, className, ...rest }: ChipSelectProps) {
  const id = useId()
  return (
    <span className={styles.selectWrap}>
      <label htmlFor={id} className="visually-hidden">
        {label}
      </label>
      <select id={id} className={[styles.chip, styles.select, className].filter(Boolean).join(' ')} {...rest}>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      <svg className={styles.chevron} width="12" height="12" viewBox="0 0 24 24" aria-hidden="true">
        <path d="m6 9 6 6 6-6" />
      </svg>
    </span>
  )
}
