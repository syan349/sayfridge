import { ButtonLink } from '../components/Button/ButtonLink'
import styles from './GuestPage.module.css'

/**
 * "Continue as guest" lands here. The backend has no guest access, so there is
 * no data to show yet: this page explains what guest mode will be and offers
 * the way back to signing in.
 */
export function GuestPage() {
  return (
    <main className={styles.page}>
      <title>Guest mode · SayFridge</title>
      <div className={styles.card}>
        <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={56} height={56} className={styles.mark} />
        <h1 className={styles.title}>Guest mode</h1>
        <p className={styles.text}>
          Guest mode is read-only: you can look around, but you can’t add items, record what you used, or let the
          assistant update an inventory.
        </p>
        <p className={styles.note}>
          <strong>Not connected yet.</strong> The server has no guest access, so there is nothing to show here yet.
        </p>
        <div className={styles.actions}>
          <ButtonLink to="/login" size="lg">
            Sign in
          </ButtonLink>
          <ButtonLink to="/register" variant="secondary" size="lg">
            Create an account
          </ButtonLink>
        </div>
      </div>
    </main>
  )
}
