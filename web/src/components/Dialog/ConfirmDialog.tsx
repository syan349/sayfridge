import { useState, type ReactNode } from 'react'
import { ApiError } from '../../api/client'
import { Button } from '../Button/Button'
import { FormError } from '../FormError/FormError'
import { Dialog } from './Dialog'
import styles from './Dialog.module.css'

interface ConfirmDialogProps {
  title: string
  open: boolean
  onClose: () => void
  /** What will happen, and what is kept. */
  children: ReactNode
  confirmLabel: string
  /** danger = red button, for things like Discard. */
  tone?: 'primary' | 'danger'
  /** Does the work. If it throws, the error is shown in the dialog. */
  onConfirm: () => Promise<void>
}

/** "Are you sure?" before an action that can't simply be undone. */
export function ConfirmDialog({ title, open, onClose, children, confirmLabel, tone = 'primary', onConfirm }: ConfirmDialogProps) {
  const [working, setWorking] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function confirm() {
    setWorking(true)
    setError(null)
    try {
      await onConfirm()
    } catch (caught) {
      setError(caught instanceof ApiError ? caught.message : 'Something went wrong. Please try again.')
    } finally {
      setWorking(false)
    }
  }

  function close() {
    setError(null)
    onClose()
  }

  return (
    <Dialog title={title} open={open} onClose={close}>
      <div className={styles.text}>{children}</div>
      {error && (
        <div className={styles.errorSlot}>
          <FormError message={error} />
        </div>
      )}
      <div className={styles.buttons}>
        <Button variant="secondary" onClick={close} disabled={working}>
          Cancel
        </Button>
        <Button variant={tone} onClick={confirm} disabled={working} autoFocus>
          {working ? 'Working…' : confirmLabel}
        </Button>
      </div>
    </Dialog>
  )
}
