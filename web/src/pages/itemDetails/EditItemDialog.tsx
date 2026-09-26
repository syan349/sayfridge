import { useId, useState, type FormEvent } from 'react'
import { ApiError, isVersionConflict } from '../../api/client'
import { updateItem, type InventoryItem, type ItemChanges } from '../../api/inventory'
import type { StorageSpace } from '../../api/storageSpaces'
import { Button } from '../../components/Button/Button'
import { Dialog } from '../../components/Dialog/Dialog'
import dialogStyles from '../../components/Dialog/Dialog.module.css'
import { FormError } from '../../components/FormError/FormError'
import { TextField } from '../../components/TextField/TextField'
import styles from './ItemDetailsPage.module.css'

interface EditItemDialogProps {
  item: InventoryItem
  spaces: StorageSpace[]
  open: boolean
  onClose: () => void
  onSaved: (message: string) => void
  onConflict: () => void
}

/** Edit where the item is kept, its dates and notes. Amounts can't be edited: they change through operations. */
export function EditItemDialog(props: EditItemDialogProps) {
  return (
    <Dialog title="Edit item" open={props.open} onClose={props.onClose}>
      <EditItemForm {...props} />
    </Dialog>
  )
}

function EditItemForm({ item, spaces, onClose, onSaved, onConflict }: EditItemDialogProps) {
  const [spaceId, setSpaceId] = useState(item.storage_space_id)
  const [purchaseDate, setPurchaseDate] = useState(item.purchase_date ?? '')
  const [expiryDate, setExpiryDate] = useState(item.expiry_date ?? '')
  const [notes, setNotes] = useState(item.notes ?? '')
  const [formError, setFormError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const spaceFieldId = useId()
  const notesFieldId = useId()

  // The item's current space may be archived (not in the list of active spaces): keep it as an option.
  const spaceOptions: { id: string; name: string }[] = spaces.some((space) => space.id === item.storage_space_id)
    ? spaces
    : [{ id: item.storage_space_id, name: item.storage_space_name }, ...spaces]

  /** Only what actually changed is sent. An emptied date or note is sent as null, which clears it. */
  function changes(): ItemChanges {
    const result: ItemChanges = {}
    if (spaceId !== item.storage_space_id) result.storage_space_id = spaceId
    if (purchaseDate !== (item.purchase_date ?? '')) result.purchase_date = purchaseDate || null
    if (expiryDate !== (item.expiry_date ?? '')) result.expiry_date = expiryDate || null
    if (notes.trim() !== (item.notes ?? '')) result.notes = notes.trim() || null
    return result
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setFormError(null)
    const changed = changes()
    if (Object.keys(changed).length === 0) {
      setFormError('Nothing has changed yet.')
      return
    }

    setSaving(true)
    try {
      await updateItem(item, changed)
      onSaved(changed.storage_space_id ? 'Saved. The item has moved.' : 'Saved your changes.')
    } catch (error) {
      setSaving(false)
      if (isVersionConflict(error)) {
        onConflict()
        return
      }
      setFormError(error instanceof ApiError ? error.message : 'Something went wrong. Please try again.')
    }
  }

  return (
    <form noValidate onSubmit={handleSubmit} className={styles.editForm}>
      <div className={styles.selectField}>
        <label htmlFor={spaceFieldId}>Storage space</label>
        <select id={spaceFieldId} value={spaceId} onChange={(event) => setSpaceId(event.target.value)} autoFocus>
          {spaceOptions.map((space) => (
            <option key={space.id} value={space.id}>
              {space.name}
            </option>
          ))}
        </select>
      </div>

      <div className={styles.amountRow}>
        <TextField
          label="Purchase date"
          type="date"
          value={purchaseDate}
          onChange={(event) => setPurchaseDate(event.target.value)}
        />
        <TextField
          label="Expiry date"
          type="date"
          value={expiryDate}
          onChange={(event) => setExpiryDate(event.target.value)}
        />
      </div>

      <div className={styles.selectField}>
        <label htmlFor={notesFieldId}>Notes</label>
        <textarea
          id={notesFieldId}
          rows={3}
          maxLength={1000}
          value={notes}
          onChange={(event) => setNotes(event.target.value)}
        />
      </div>

      <p className={styles.dialogHint}>Clear a date or the notes to remove them. Amounts change through “Record a change”.</p>

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
          {saving ? 'Saving…' : 'Save changes'}
        </Button>
      </div>
    </form>
  )
}
