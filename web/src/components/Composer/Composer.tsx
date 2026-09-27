import { useId, useState, type FormEvent } from 'react'
import styles from './Composer.module.css'

interface ComposerProps {
  onSend: (text: string) => void
  /** Blocks sending (e.g. while an answer is still arriving), but typing stays possible. */
  sending?: boolean
  /** Blocks the whole box, e.g. while the assistant waits for an answer to its proposal. */
  disabled?: boolean
  placeholder?: string
}

/** The message box at the bottom of the assistant: text only (the backend takes no photos yet). */
export function Composer({
  onSend,
  sending = false,
  disabled = false,
  placeholder = 'Ask about your food, or say what you used…',
}: ComposerProps) {
  const [text, setText] = useState('')
  const inputId = useId()
  const canSend = !sending && !disabled && text.trim() !== ''

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!canSend) return
    onSend(text.trim())
    setText('')
  }

  return (
    <form className={styles.composer} onSubmit={handleSubmit}>
      <label htmlFor={inputId} className="visually-hidden">
        Message the assistant
      </label>
      <input
        id={inputId}
        className={styles.input}
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        maxLength={8000}
        autoComplete="off"
      />
      <span className={styles.voice}>
        <img src="/assets/icons/assistant/microphone.png" alt="" width={15} height={15} />
        Voice is on the phone
      </span>
      <button type="submit" className={styles.send} aria-label="Send" disabled={!canSend}>
        <img src="/assets/icons/assistant/send.png" alt="" width={20} height={20} />
      </button>
    </form>
  )
}
