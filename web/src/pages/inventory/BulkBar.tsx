import { useId, useState } from 'react'
import type { InventoryItem } from '../../api/inventory'
import type { StorageSpace } from '../../api/storageSpaces'
import { Button } from '../../components/Button/Button'
import { CONSUME_CHOICES, archiveAll, consumeEach, discardEach, moveAll, type BulkOutcome } from './bulkActions'
import styles from './BulkBar.module.css'

type Action = 'consume' | 'move' | 'archive' | 'discard'

const ACTIONS: { action: Action; label: string }[] = [
  { action: 'consume', label: 'Record consumption' },
  { action: 'move', label: 'Move to space' },
  { action: 'archive', label: 'Archive' },
  { action: 'discard', label: 'Discard' },
]

interface BulkBarProps {
  /** The selected items (only shown when at least one is selected). */
  items: InventoryItem[]
  spaces: StorageSpace[]
  onClear: () => void
  /** Called once the requests are done; the page shows the outcome and reloads the list. */
  onFinished: (outcome: BulkOutcome) => void
}

/**
 * The green bar that appears when rows are selected. Each action opens a small
 * panel underneath to choose details and confirm, so nothing happens on one click.
 */
export function BulkBar({ items, spaces, onClear, onFinished }: BulkBarProps) {
  const [open, setOpen] = useState<Action | null>(null)
  const [fraction, setFraction] = useState(CONSUME_CHOICES[0].fraction)
  const [targetSpaceId, setTargetSpaceId] = useState('')
  const [working, setWorking] = useState(false)
  const panelId = useId()

  const count = items.length
  const itemsText = count === 1 ? '1 item' : `${count} items`
  const targetSpace = spaces.find((space) => space.id === targetSpaceId) ?? spaces[0]

  async function run(action: () => Promise<BulkOutcome>) {
    setWorking(true)
    const outcome = await action()
    setWorking(false)
    setOpen(null)
    onFinished(outcome)
  }

  const cancel = (
    <Button variant="secondary" size="sm" onClick={() => setOpen(null)} disabled={working}>
      Cancel
    </Button>
  )

  return (
    <section aria-label="Bulk actions" className={styles.bar}>
      <div className={styles.row}>
        <span className={styles.count}>{itemsText} selected</span>
        <span className={styles.divider} aria-hidden="true" />
        {ACTIONS.map(({ action, label }) => (
          <button
            key={action}
            type="button"
            className={open === action ? `${styles.action} ${styles.open}` : styles.action}
            aria-expanded={open === action}
            aria-controls={panelId}
            onClick={() => setOpen(open === action ? null : action)}
          >
            {label}
          </button>
        ))}
        <button type="button" className={styles.clear} onClick={onClear}>
          Clear selection
        </button>
        <span className={styles.note}>Bulk edits are web-only — the phone changes one item at a time</span>
      </div>

      {open && (
        <div id={panelId} className={styles.panel}>
          {open === 'consume' && (
            <>
              <fieldset className={styles.fieldset}>
                <legend className={styles.legend}>How much of each item was used?</legend>
                {CONSUME_CHOICES.map((choice, index) => (
                  <label key={choice.fraction} className={styles.radio}>
                    <input
                      type="radio"
                      name="consume-fraction"
                      value={choice.fraction}
                      checked={fraction === choice.fraction}
                      onChange={() => setFraction(choice.fraction)}
                      autoFocus={index === 0}
                    />
                    {choice.label}
                  </label>
                ))}
              </fieldset>
              <p className={styles.hint}>Taken from what is left of each item, whatever its unit.</p>
              <div className={styles.buttons}>
                <Button size="sm" disabled={working} onClick={() => run(() => consumeEach(items, fraction))}>
                  {working ? 'Saving…' : `Record for ${itemsText}`}
                </Button>
                {cancel}
              </div>
            </>
          )}

          {open === 'move' && (
            <>
              <label className={styles.inline}>
                Move {itemsText} to
                <select
                  className={styles.select}
                  value={targetSpace?.id ?? ''}
                  onChange={(event) => setTargetSpaceId(event.target.value)}
                  autoFocus
                >
                  {spaces.map((space) => (
                    <option key={space.id} value={space.id}>
                      {space.name}
                    </option>
                  ))}
                </select>
              </label>
              <div className={styles.buttons}>
                <Button
                  size="sm"
                  disabled={working || !targetSpace}
                  onClick={() => targetSpace && run(() => moveAll(items, targetSpace))}
                >
                  {working ? 'Moving…' : 'Move'}
                </Button>
                {cancel}
              </div>
            </>
          )}

          {open === 'archive' && (
            <>
              <p className={styles.question}>
                Archive {itemsText}? They leave the in-stock list, but they and their history are kept.
              </p>
              <div className={styles.buttons}>
                <Button size="sm" disabled={working} onClick={() => run(() => archiveAll(items))} autoFocus>
                  {working ? 'Archiving…' : `Archive ${itemsText}`}
                </Button>
                {cancel}
              </div>
            </>
          )}

          {open === 'discard' && (
            <>
              <p className={styles.question}>
                Discard {itemsText}? Use this for food that was thrown away. The items and their history are kept.
              </p>
              <div className={styles.buttons}>
                <Button
                  variant="danger"
                  size="sm"
                  disabled={working}
                  onClick={() => run(() => discardEach(items))}
                  autoFocus
                >
                  {working ? 'Discarding…' : `Discard ${itemsText}`}
                </Button>
                {cancel}
              </div>
            </>
          )}
        </div>
      )}
    </section>
  )
}
