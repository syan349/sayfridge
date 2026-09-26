import { useState, type FormEvent } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { ApiError } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import { Button } from '../components/Button/Button'
import styles from './LoginPlaceholderPage.module.css'

/**
 * Temporary, unstyled sign-in so the protected pages can be reached during
 * development. Replaced by the designed W01 page (issue #15).
 */
export function LoginPlaceholderPage() {
  const { status, login } = useAuth()
  const location = useLocation()
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  // RequireAuth stores the page the user was trying to open.
  const from = (location.state as { from?: string } | null)?.from ?? '/'
  if (status === 'authenticated') return <Navigate to={from} replace />

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    setSubmitting(true)
    setError(null)
    try {
      await login({ email: String(form.get('email')), password: String(form.get('password')) })
      // Success changes the auth status, and the redirect above takes over.
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Sign in failed. Please try again.')
      setSubmitting(false)
    }
  }

  return (
    <main className={styles.page}>
      <form className={styles.card} onSubmit={handleSubmit}>
        <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={48} height={48} className={styles.mark} />
        <h1 className={styles.title}>Sign in to SayFridge</h1>
        <p className={styles.note}>Temporary sign-in page. The designed version comes with W01 (issue #15).</p>

        <label className={styles.field}>
          Email
          <input name="email" type="email" autoComplete="email" required className={styles.input} />
        </label>
        <label className={styles.field}>
          Password
          <input
            name="password"
            type="password"
            autoComplete="current-password"
            required
            minLength={8}
            className={styles.input}
          />
        </label>

        {error && (
          <p role="alert" className={styles.error}>
            {error}
          </p>
        )}

        <Button type="submit" disabled={submitting}>
          {submitting ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>
    </main>
  )
}
