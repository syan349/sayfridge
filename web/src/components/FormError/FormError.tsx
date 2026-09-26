import styles from './FormError.module.css'

/**
 * A message about the whole form (e.g. "Invalid email or password"), shown
 * above the submit button. role="alert" makes screen readers read it out
 * as soon as it appears.
 */
export function FormError({ message }: { message: string }) {
  return (
    <p role="alert" className={styles.error}>
      <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" className={styles.icon}>
        <path d="M12 3 2.5 20h19L12 3Z" />
        <path d="M12 10v4.5M12 17.2v.3" />
      </svg>
      {message}
    </p>
  )
}
