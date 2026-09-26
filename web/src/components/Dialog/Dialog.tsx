import { useEffect, useId, useRef, type ReactNode } from 'react'
import styles from './Dialog.module.css'

interface DialogProps {
  title: string
  open: boolean
  /** Called for Cancel, the × button and the Escape key. */
  onClose: () => void
  children: ReactNode
}

/**
 * A modal window built on the browser's own <dialog>. showModal() gives us for
 * free: the page behind can't be clicked or tabbed into, Escape closes it, and
 * focus returns to the button that opened it.
 */
export function Dialog({ title, open, onClose, children }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const titleId = useId()

  // <dialog> is opened and closed with methods, not attributes, so sync it with `open`.
  useEffect(() => {
    const dialog = ref.current
    if (!dialog) return
    if (open && !dialog.open) dialog.showModal()
    if (!open && dialog.open) dialog.close()
  }, [open])

  return (
    <dialog ref={ref} aria-labelledby={titleId} className={styles.dialog} onClose={onClose}>
      <div className={styles.head}>
        <h2 id={titleId} className={styles.title}>
          {title}
        </h2>
        <button type="button" className={styles.close} aria-label="Close" onClick={onClose}>
          <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true">
            <path d="M6 6l12 12M18 6 6 18" />
          </svg>
        </button>
      </div>
      {/* Only rendered while open, so every opening starts with a fresh form. */}
      {open && <div className={styles.body}>{children}</div>}
    </dialog>
  )
}
