// Checks done in the browser before anything is sent. The backend checks the
// same rules again (backend/app/schemas/auth.py): these only give faster,
// friendlier messages.

export const PASSWORD_MIN = 8
export const PASSWORD_MAX = 128

// Deliberately simple: "something@something.something". The backend does the strict check.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export type FieldErrors<Field extends string> = Partial<Record<Field, string>>

export function emailError(email: string): string | undefined {
  if (!email.trim()) return 'Enter your email address.'
  if (!EMAIL_PATTERN.test(email.trim())) return 'Enter a valid email address, like name@example.com.'
  return undefined
}

export function validateSignIn(values: { email: string; password: string }): FieldErrors<'email' | 'password'> {
  return {
    email: emailError(values.email),
    password: values.password ? undefined : 'Enter your password.',
  }
}

export function validateRegister(values: {
  email: string
  password: string
  confirmPassword: string
}): FieldErrors<'email' | 'password' | 'confirmPassword'> {
  let password: string | undefined
  if (!values.password) password = 'Choose a password.'
  else if (values.password.length < PASSWORD_MIN) password = `Use at least ${PASSWORD_MIN} characters.`
  else if (values.password.length > PASSWORD_MAX) password = `Use at most ${PASSWORD_MAX} characters.`

  let confirmPassword: string | undefined
  if (!values.confirmPassword) confirmPassword = 'Type the password again.'
  else if (values.confirmPassword !== values.password) confirmPassword = 'Passwords do not match.'

  return { email: emailError(values.email), password, confirmPassword }
}

/** The first field that has an error, in the order given — used to move focus there. */
export function firstInvalidField<Field extends string>(errors: FieldErrors<Field>, order: Field[]): Field | undefined {
  return order.find((field) => errors[field])
}
