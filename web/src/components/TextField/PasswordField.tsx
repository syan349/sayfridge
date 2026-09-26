import { useState } from 'react'
import { TextField, type TextFieldProps } from './TextField'
import styles from './PasswordField.module.css'

type PasswordFieldProps = Omit<TextFieldProps, 'type' | 'trailing'>

/** A TextField for passwords, with an eye button that shows or hides what was typed. */
export function PasswordField(props: PasswordFieldProps) {
  const [visible, setVisible] = useState(false)

  return (
    <TextField
      {...props}
      type={visible ? 'text' : 'password'}
      trailing={
        // A toggle button: the label stays the same and aria-pressed says whether it's on.
        <button
          type="button"
          className={styles.toggle}
          aria-label="Show password"
          aria-pressed={visible}
          onClick={() => setVisible((current) => !current)}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true">
            <path d="M2 12s3.8-6.5 10-6.5S22 12 22 12s-3.8 6.5-10 6.5S2 12 2 12Z" />
            <circle cx="12" cy="12" r="2.6" />
            {visible && <path d="M4 4l16 16" />}
          </svg>
        </button>
      }
    />
  )
}
