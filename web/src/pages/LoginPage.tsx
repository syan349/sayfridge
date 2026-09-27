import { useState, type ChangeEvent, type FormEvent } from 'react'
import { Link, Navigate, useLocation } from 'react-router-dom'
import { ApiError } from '../api/client'
import { fieldMessages } from '../api/fieldMessages'
import { useAuth } from '../auth/AuthContext'
import type { LoginLocationState } from '../auth/loginState'
import { firstInvalidField, validateSignIn, type FieldErrors } from '../auth/validation'
import { AuthLayout } from '../components/AuthLayout/AuthLayout'
import { PanelChecklist } from '../components/AuthLayout/PanelList'
import { Button } from '../components/Button/Button'
import { ButtonLink } from '../components/Button/ButtonLink'
import { FormError } from '../components/FormError/FormError'
import { PasswordField } from '../components/TextField/PasswordField'
import { TextField } from '../components/TextField/TextField'
import styles from './authPages.module.css'

type Field = 'email' | 'password'
const FIELD_ORDER: Field[] = ['email', 'password']

/** W01 — Sign in. POST /auth/login, then back to the page the user wanted (or the dashboard). */
export function LoginPage() {
  const { status, login } = useAuth()
  const location = useLocation()
  const state = location.state as LoginLocationState | null

  const [values, setValues] = useState({ email: state?.email ?? '', password: '' })
  const [errors, setErrors] = useState<FieldErrors<Field>>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  // Already signed in (or just signed in): leave this page.
  if (status === 'authenticated') return <Navigate to={state?.from ?? '/'} replace />

  function handleChange(field: Field) {
    return (event: ChangeEvent<HTMLInputElement>) => {
      setValues((current) => ({ ...current, [field]: event.target.value }))
      setErrors((current) => ({ ...current, [field]: undefined })) // typing clears that field's error
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setFormError(null)

    const found = validateSignIn(values)
    setErrors(found)
    const firstInvalid = firstInvalidField(found, FIELD_ORDER)
    if (firstInvalid) {
      document.getElementById(`login-${firstInvalid}`)?.focus()
      return
    }

    setSubmitting(true)
    try {
      await login({ email: values.email.trim(), password: values.password })
      // Success changes the auth status, and the <Navigate> above takes over.
    } catch (error) {
      setSubmitting(false)
      showServerError(error)
    }
  }

  function showServerError(error: unknown) {
    if (!(error instanceof ApiError)) {
      setFormError('Sign in failed. Please try again.')
      return
    }
    // 422: the backend says which field is wrong, so show it under that field.
    const messages = fieldMessages(error)
    if (messages.email || messages.password) {
      setErrors({ email: messages.email, password: messages.password })
      return
    }
    // 401 "Invalid email or password", a server error, or no connection.
    setFormError(error.message)
  }

  return (
    <AuthLayout
      headline={
        <>
          The desk view of
          <br />
          your kitchen.
        </>
      }
      lead="Bulk edits, expiry reports and the full operation history — everything that is awkward to do on a phone while standing at the fridge."
      panelContent={
        <PanelChecklist
          items={[
            'Select many items at once and record what you used in a single action.',
            'See every add, consume and reconcile, with the words you actually said.',
            'Tell confirmed amounts apart from AI estimates before you trust a number.',
          ]}
        />
      }
      panelFooter="The mobile app stays the place for voice, camera and receipt capture."
    >
      <title>Sign in · SayFridge</title>
      <div className={styles.form}>
        <h1 className={styles.title}>Sign in</h1>
        <p className={styles.subtitle}>Use the same account as the SayFridge app.</p>

        {state?.notice && (
          <p role="status" className={styles.notice}>
            {state.notice}
          </p>
        )}

        {/* noValidate: show our own messages instead of the browser's pop-ups. */}
        <form noValidate onSubmit={handleSubmit}>
          <div className={styles.fields}>
            <TextField
              id="login-email"
              label="Email"
              type="email"
              autoComplete="email"
              value={values.email}
              onChange={handleChange('email')}
              error={errors.email}
            />
            <PasswordField
              id="login-password"
              label="Password"
              autoComplete="current-password"
              value={values.password}
              onChange={handleChange('password')}
              error={errors.password}
            />
          </div>

          {formError && (
            <div className={styles.errorSlot}>
              <FormError message={formError} />
            </div>
          )}

          <Button type="submit" size="lg" className={styles.fullWidth} disabled={submitting}>
            {submitting ? 'Signing in…' : 'Sign in'}
          </Button>
        </form>

        <div className={styles.divider}>or</div>

        <ButtonLink
          to="/guest"
          variant="secondary"
          size="lg"
          icon="/assets/icons/assistant/profile.png"
          className={styles.fullWidth}
        >
          Continue as guest
        </ButtonLink>

        <p className={styles.switch}>
          New to SayFridge? <Link to="/register">Create an account</Link>
        </p>

        <p className={styles.guestNote}>
          <img src="/assets/icons/assistant/ai_assistant.png" alt="" width={24} height={24} />
          Guest mode is read-only. Sign in to add items, record use, or let the assistant update your inventory.
        </p>
      </div>
    </AuthLayout>
  )
}
