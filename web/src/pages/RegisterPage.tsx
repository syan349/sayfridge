import { useState, type ChangeEvent, type FormEvent } from 'react'
import { Link, Navigate, useNavigate } from 'react-router-dom'
import * as authApi from '../api/auth'
import { ApiError } from '../api/client'
import { fieldMessages } from '../api/fieldMessages'
import { useAuth } from '../auth/AuthContext'
import type { LoginLocationState } from '../auth/loginState'
import { PASSWORD_MIN, firstInvalidField, validateRegister, type FieldErrors } from '../auth/validation'
import { AuthLayout } from '../components/AuthLayout/AuthLayout'
import { PanelSteps } from '../components/AuthLayout/PanelList'
import { Button } from '../components/Button/Button'
import { ButtonLink } from '../components/Button/ButtonLink'
import { FormError } from '../components/FormError/FormError'
import { PasswordField } from '../components/TextField/PasswordField'
import { TextField } from '../components/TextField/TextField'
import styles from './authPages.module.css'

type Field = 'email' | 'password' | 'confirmPassword'
const FIELD_ORDER: Field[] = ['email', 'password', 'confirmPassword']

/**
 * W02 — Create account. Sends only email + password: the backend has no name
 * or avatar, and the team decided (26 Sep) to keep it that way for now.
 * After POST /auth/register it signs in straight away with the same details.
 */
export function RegisterPage() {
  const { status, login } = useAuth()
  const navigate = useNavigate()

  const [values, setValues] = useState({ email: '', password: '', confirmPassword: '' })
  const [errors, setErrors] = useState<FieldErrors<Field>>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  if (status === 'authenticated') return <Navigate to="/" replace />

  function handleChange(field: Field) {
    return (event: ChangeEvent<HTMLInputElement>) => {
      setValues((current) => ({ ...current, [field]: event.target.value }))
      setErrors((current) => ({ ...current, [field]: undefined }))
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setFormError(null)

    // The confirm-password check happens only here, in the browser: the backend never sees it.
    const found = validateRegister(values)
    setErrors(found)
    const firstInvalid = firstInvalidField(found, FIELD_ORDER)
    if (firstInvalid) {
      document.getElementById(`register-${firstInvalid}`)?.focus()
      return
    }

    const credentials = { email: values.email.trim(), password: values.password }
    setSubmitting(true)

    try {
      await authApi.register(credentials)
    } catch (error) {
      setSubmitting(false)
      showServerError(error)
      return
    }

    try {
      await login(credentials)
      // Signed in: the auth status changes and the <Navigate> above goes to the dashboard.
    } catch {
      // The account exists but automatic sign-in failed: let the user sign in by hand.
      const state: LoginLocationState = {
        email: credentials.email,
        notice: 'Your account was created. Sign in to continue.',
      }
      navigate('/login', { replace: true, state })
    }
  }

  function showServerError(error: unknown) {
    if (!(error instanceof ApiError)) {
      setFormError('Could not create the account. Please try again.')
      return
    }
    if (error.status === 409) {
      setErrors({ email: error.message }) // "Email is already registered"
      document.getElementById('register-email')?.focus()
      return
    }
    const messages = fieldMessages(error)
    if (messages.email || messages.password) {
      setErrors({ email: messages.email, password: messages.password })
      return
    }
    setFormError(error.message)
  }

  return (
    <AuthLayout
      panelSize="narrow"
      headline={
        <>
          Start tracking
          <br />
          what’s in your fridge.
        </>
      }
      lead="One account works on the phone and here. Set it up on whichever you have to hand."
      panelContent={
        <PanelSteps
          steps={[
            { title: 'Create your account', text: 'Email and a password. That is all we ask for.' },
            { title: 'Add a storage space', text: 'Fridge, freezer or pantry — you can add more later.' },
            { title: 'Put something in it', text: 'Scan a receipt on the phone, or type the first few items here.' },
          ]}
        />
      }
      panelFooter={
        <>
          Already have an account? <Link to="/login">Sign in instead</Link>
        </>
      }
    >
      <title>Create account · SayFridge</title>
      <div className={`${styles.form} ${styles.wideForm}`}>
        <h1 className={styles.title}>Create your account</h1>
        <p className={styles.subtitle}>Email and password only — no verification code needed at this stage.</p>

        <form noValidate onSubmit={handleSubmit}>
          <div className={styles.grid}>
            <TextField
              id="register-email"
              className={styles.span2}
              label="Email"
              type="email"
              autoComplete="email"
              value={values.email}
              onChange={handleChange('email')}
              error={errors.email}
            />
            <PasswordField
              id="register-password"
              label="Password"
              autoComplete="new-password"
              hint={`At least ${PASSWORD_MIN} characters.`}
              value={values.password}
              onChange={handleChange('password')}
              error={errors.password}
            />
            <PasswordField
              id="register-confirmPassword"
              label="Confirm password"
              autoComplete="new-password"
              value={values.confirmPassword}
              onChange={handleChange('confirmPassword')}
              error={errors.confirmPassword}
            />
          </div>

          {formError && (
            <div className={styles.errorSlot}>
              <FormError message={formError} />
            </div>
          )}

          <div className={styles.actions}>
            <Button type="submit" size="lg" disabled={submitting}>
              {submitting ? 'Creating account…' : 'Create account'}
            </Button>
            <ButtonLink to="/login" variant="secondary" size="lg">
              Cancel
            </ButtonLink>
          </div>
        </form>
      </div>
    </AuthLayout>
  )
}
