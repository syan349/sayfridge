import { useId, useState, type ChangeEvent, type FormEvent } from 'react'
import { MAX_PHOTOS, PHOTO_ACCEPT, photoProblem, photosTooLarge, preparePhoto, type PreparedPhoto } from '../../lib/photos'
import styles from './Composer.module.css'

interface ComposerProps {
  onSend: (text: string, photos: PreparedPhoto[]) => void
  /** Blocks sending (e.g. while an answer is still arriving), but typing stays possible. */
  sending?: boolean
  /** Blocks the whole box, e.g. while the conversation is still loading. */
  disabled?: boolean
  placeholder?: string
}

/** The message box at the bottom of the assistant: text, and up to 4 photos (a shelf, a receipt, a label). */
export function Composer({
  onSend,
  sending = false,
  disabled = false,
  placeholder = 'Ask about your food, or say what you used…',
}: ComposerProps) {
  const [text, setText] = useState('')
  const [photos, setPhotos] = useState<PreparedPhoto[]>([])
  const [preparing, setPreparing] = useState(false)
  const [photoError, setPhotoError] = useState<string | null>(null)
  const inputId = useId()
  const fileId = useId()
  const errorId = useId()
  const canSend = !sending && !disabled && !preparing && (text.trim() !== '' || photos.length > 0)

  async function addPhotos(event: ChangeEvent<HTMLInputElement>) {
    const files = [...(event.target.files ?? [])]
    event.target.value = '' // so choosing the same file again fires this event again
    setPhotoError(null)
    if (files.length === 0) return

    const problem = files.map(photoProblem).find((found) => found !== null)
    if (problem) return setPhotoError(`${problem} Choose JPEG, PNG or WebP photos.`)
    if (photos.length + files.length > MAX_PHOTOS) return setPhotoError(`You can send at most ${MAX_PHOTOS} photos at a time.`)

    setPreparing(true)
    try {
      const added = await Promise.all(files.map(preparePhoto)) // shrinks each one in the browser
      if (photosTooLarge([...photos, ...added])) setPhotoError('These photos are too large to send together. Add fewer.')
      else setPhotos((current) => [...current, ...added])
    } catch {
      setPhotoError('That photo couldn’t be read. Try another one.')
    } finally {
      setPreparing(false)
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!canSend) return
    onSend(text.trim(), photos)
    setText('')
    setPhotos([])
    setPhotoError(null)
  }

  return (
    <form className={styles.composer} onSubmit={handleSubmit}>
      {photos.length > 0 && (
        <ul className={styles.photos} aria-label="Photos to send">
          {photos.map((photo, index) => (
            <li key={photo.image.image_id} className={styles.photo}>
              <img src={photo.previewUrl} alt={`Photo ${index + 1}: ${photo.name}`} />
              <button
                type="button"
                className={styles.remove}
                aria-label={`Remove photo ${index + 1}`}
                onClick={() => setPhotos((current) => current.filter((kept) => kept !== photo))}
              >
                <svg width="10" height="10" viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M5 5l14 14M19 5 5 19" />
                </svg>
              </button>
            </li>
          ))}
        </ul>
      )}
      {photoError && (
        <p id={errorId} role="alert" className={styles.photoError}>
          {photoError}
        </p>
      )}

      <div className={styles.pill}>
        {/* A real file input (so it works with the keyboard), drawn as a round button by its label. */}
        <input
          id={fileId}
          type="file"
          accept={PHOTO_ACCEPT}
          multiple
          className={`visually-hidden ${styles.fileInput}`}
          disabled={disabled || preparing || photos.length >= MAX_PHOTOS}
          aria-describedby={photoError ? errorId : undefined}
          onChange={(event) => void addPhotos(event)}
        />
        <label htmlFor={fileId} className={styles.attach} title="Attach photos">
          <img src="/assets/icons/assistant/photo.png" alt="" width={22} height={22} />
          <span className="visually-hidden">Attach photos</span>
        </label>

        <label htmlFor={inputId} className="visually-hidden">
          Message the assistant
        </label>
        <input
          id={inputId}
          className={styles.input}
          value={text}
          onChange={(event) => setText(event.target.value)}
          placeholder={preparing ? 'Preparing photos…' : placeholder}
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
      </div>
    </form>
  )
}
