import { useRef, useState, type FormEvent } from 'react'
import { ApiError, isVersionConflict } from '../../api/client'
import { fieldMessages } from '../../api/fieldMessages'
import { newIdempotencyKey } from '../../api/idempotencyKey'
import { recordOperation, type InventoryItem, type OperationType } from '../../api/inventory'
import { Button } from '../../components/Button/Button'
import { Dialog } from '../../components/Dialog/Dialog'
import dialogStyles from '../../components/Dialog/Dialog.module.css'
import { FormError } from '../../components/FormError/FormError'
import { TextField } from '../../components/TextField/TextField'
import styles from './ItemDetailsPage.module.css'

const CHOICES: { type: OperationType; label: string; amountLabel: string; submit: string }[] = [
  { type: 'CONSUME', label: 'Used some', amountLabel: 'How much was used?', submit: 'Record use' },
  { type: 'ADD', label: 'Added more', amountLabel: 'How much was added?', submit: 'Add stock' },
  { type: 'RECONCILE', label: 'Counted it', amountLabel: 'How much is there now?', submit: 'Confirm count' },
]

// Same rule as the backend: digits, optionally a point and up to three decimals.
const AMOUNT_PATTERN = /^[0-9]+(\.[0-9]{1,3})?$/

interface RecordChangeDialogProps {
  item: InventoryItem
  open: boolean
  /** Which choice is ticked when the dialog opens. */
  initialType: OperationType
  onClose: () => void
  /** Saved: the page shows `message` and reloads the item and its history. */
  onSaved: (message: string) => void
  /** 409 VERSION_CONFLICT: the page explains it and reloads. */
  onConflict: () => void
}

/** "Record a change": every change to an amount is an operation (ADD, CONSUME or RECONCILE). */
export function RecordChangeDialog(props: RecordChangeDialogProps) {
  return (
    <Dialog title="Record a change" open={props.open} onClose={props.onClose}>
      <RecordChangeForm {...props} />
    </Dialog>
  )
}

function RecordChangeForm({ item, initialType, onClose, onSaved, onConflict }: RecordChangeDialogProps) {
  const [type, setType] = useState<OperationType>(initialType)
  const [amount, setAmount] = useState('')
  const [unit, setUnit] = useState(item.display_unit)
  const [errors, setErrors] = useState<{ amount?: string; unit?: string }>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  // One idempotency key per exact input. Pressing Save again with the same input
  // (e.g. after a network error) reuses the key, so the backend can't apply it
  // twice. Changing the input is a new action, so it gets a new key.
  const keyRef = useRef<{ input: string; key: string } | null>(null)

  const choice = CHOICES.find((c) => c.type === type) ?? CHOICES[0]
  // CONSUME needs stock; ADD and RECONCILE also work on an EMPTY item.
  const allowed = (option: OperationType) => item.status === 'IN_STOCK' || (item.status === 'EMPTY' && option !== 'CONSUME')

  function validate() {
    const found: { amount?: string; unit?: string } = {}
    const value = amount.trim()
    if (!value) found.amount = 'Enter an amount.'
    else if (!AMOUNT_PATTERN.test(value)) found.amount = 'Use a number like 2 or 0.25 (up to 3 decimals).'
    else if (type !== 'RECONCILE' && Number(value) === 0) found.amount = 'Enter an amount above zero.'
    if (!unit.trim()) found.unit = 'Enter a unit, e.g. g, kg or each.'
    else if (unit.trim().length > 16) found.unit = 'Use at most 16 characters.'
    return found
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setFormError(null)
    const found = validate()
    setErrors(found)
    if (found.amount || found.unit) return

    const input = { type, kind: 'AMOUNT' as const, value: amount.trim(), unit: unit.trim() }
    const signature = `${input.type}|${input.value}|${input.unit}`
    if (keyRef.current?.input !== signature) keyRef.current = { input: signature, key: newIdempotencyKey() }

    setSaving(true)
    try {
      await recordOperation(item, input, keyRef.current.key)
      const verb = type === 'CONSUME' ? 'Recorded: used' : type === 'ADD' ? 'Added' : 'Confirmed'
      onSaved(`${verb} ${input.value} ${input.unit}.`)
    } catch (error) {
      setSaving(false)
      if (isVersionConflict(error)) {
        onConflict()
        return
      }
      if (error instanceof ApiError) {
        // 422 VALIDATION_ERROR names the field; other codes (e.g. INSUFFICIENT_QUANTITY,
        // UNIT_NOT_CONVERTIBLE) come with a message for the whole form.
        const messages = fieldMessages(error)
        if (messages.quantity_value || messages.quantity_unit) {
          setErrors({ amount: messages.quantity_value, unit: messages.quantity_unit })
        } else {
          setFormError(error.message)
        }
      } else {
        setFormError('Something went wrong. Please try again.')
      }
    }
  }

  return (
    <form noValidate onSubmit={handleSubmit}>
      <fieldset className={styles.choices}>
        <legend className={styles.legend}>What happened?</legend>
        {CHOICES.map((option) => (
          <label key={option.type} className={styles.choice}>
            <input
              type="radio"
              name="operation-type"
              value={option.type}
              checked={type === option.type}
              disabled={!allowed(option.type)}
              onChange={() => setType(option.type)}
            />
            {option.label}
          </label>
        ))}
      </fieldset>

      <div className={styles.amountRow}>
        <TextField
          label={choice.amountLabel}
          inputMode="decimal"
          autoComplete="off"
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
          error={errors.amount}
          autoFocus
        />
        <TextField
          label="Unit"
          autoComplete="off"
          value={unit}
          onChange={(event) => setUnit(event.target.value)}
          error={errors.unit}
          className={styles.unitField}
        />
      </div>

      <p className={styles.dialogHint}>
        {type === 'RECONCILE'
          ? 'This becomes the confirmed amount and clears any AI estimate.'
          : 'g and kg, ml and l are converted for you; other units must match the item’s unit.'}
      </p>

      {formError && (
        <div className={dialogStyles.errorSlot}>
          <FormError message={formError} />
        </div>
      )}

      <div className={dialogStyles.buttons}>
        <Button variant="secondary" onClick={onClose} disabled={saving}>
          Cancel
        </Button>
        <Button type="submit" disabled={saving}>
          {saving ? 'Saving…' : choice.submit}
        </Button>
      </div>
    </form>
  )
}
