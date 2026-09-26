import { useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { isVersionConflict } from '../../api/client'
import { discardItem, type ExpiryBucket, type InventoryItem, type OperationType } from '../../api/inventory'
import { Button } from '../../components/Button/Button'
import { ConfirmDialog } from '../../components/Dialog/ConfirmDialog'
import { RecordChangeDialog } from './RecordChangeDialog'

export interface ActionNotice {
  tone: 'info' | 'warning'
  title: string
  text?: string
}

/** Shown after a 409 VERSION_CONFLICT, on every page that changes items. */
export const CHANGED_NOTICE: ActionNotice = {
  tone: 'warning',
  title: 'This item changed since you opened it',
  text: 'Someone (or the phone app) changed it first, so nothing was saved. The latest version is shown now — check it and try again.',
}

type Action = { kind: 'record'; type: OperationType; item: InventoryItem } | { kind: 'discard'; item: InventoryItem }

/**
 * Quick actions on items in a list (expiry overview, dashboard): the row buttons,
 * plus ONE record dialog and ONE discard dialog for the whole page. It reuses the
 * item page's RecordChangeDialog, so every screen changes amounts the same way.
 */
export function useItemActions() {
  const queryClient = useQueryClient()
  const [action, setAction] = useState<Action | null>(null)
  const [open, setOpen] = useState(false)
  const [notice, setNotice] = useState<ActionNotice | null>(null)

  function start(next: Action) {
    setAction(next)
    setOpen(true)
  }

  function finish(result: ActionNotice) {
    setOpen(false)
    setNotice(result)
    // Every inventory query (lists, counts, summaries, the sidebar) starts with 'inventory'.
    void queryClient.invalidateQueries({ queryKey: ['inventory'] })
  }

  async function discard(item: InventoryItem) {
    try {
      await discardItem(item)
      finish({ tone: 'info', title: `Discarded ${item.item_definition_name}.`, text: 'It stays in the history.' })
    } catch (error) {
      if (isVersionConflict(error)) {
        finish(CHANGED_NOTICE)
        return
      }
      throw error // shown inside the confirm dialog
    }
  }

  /**
   * The buttons for one row, most useful first: Discard for something already
   * overdue, Reconcile for an AI estimate, otherwise Record use.
   * `compact` shows only the first one.
   */
  function actionsFor(item: InventoryItem & { bucket?: ExpiryBucket }, compact = false) {
    const name = item.item_definition_name
    const recordUse = (variant: 'primary' | 'secondary') => (
      <Button
        key="use"
        size="sm"
        variant={variant}
        aria-label={`Record use for ${name}`}
        onClick={() => start({ kind: 'record', type: 'CONSUME', item })}
      >
        Record use
      </Button>
    )
    const reconcile = (
      <Button key="reconcile" size="sm" aria-label={`Reconcile ${name}`} onClick={() => start({ kind: 'record', type: 'RECONCILE', item })}>
        Reconcile
      </Button>
    )
    const discardButton = (variant: 'danger' | 'secondary') => (
      <Button key="discard" size="sm" variant={variant} aria-label={`Discard ${name}`} onClick={() => start({ kind: 'discard', item })}>
        Discard
      </Button>
    )

    let buttons
    if (item.bucket === 'overdue') buttons = [discardButton('danger'), recordUse('secondary')]
    else if (item.is_estimated) buttons = [reconcile, recordUse('secondary')]
    else buttons = [recordUse('primary'), discardButton('secondary')]

    return compact ? buttons[0] : buttons
  }

  const dialogs = action && (
    <>
      <RecordChangeDialog
        item={action.item}
        open={open && action.kind === 'record'}
        initialType={action.kind === 'record' ? action.type : 'CONSUME'}
        onClose={() => setOpen(false)}
        onSaved={(message) => finish({ tone: 'info', title: `${action.item.item_definition_name}: ${message}` })}
        onConflict={() => finish(CHANGED_NOTICE)}
      />
      <ConfirmDialog
        title={`Discard ${action.item.item_definition_name}?`}
        open={open && action.kind === 'discard'}
        onClose={() => setOpen(false)}
        confirmLabel="Discard"
        tone="danger"
        onConfirm={() => discard(action.item)}
      >
        <p>Use this when the food was thrown away. Its status becomes Discarded.</p>
        <p>The item and its whole history stay in the log.</p>
      </ConfirmDialog>
    </>
  )

  return { actionsFor, dialogs, notice, clearNotice: () => setNotice(null) }
}
