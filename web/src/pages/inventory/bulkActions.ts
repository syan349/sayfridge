// What happens when the user applies one action to many selected items.
//
// Two kinds of bulk action, because the backend offers two kinds of endpoint:
// - Move and Archive have a batch endpoint: ONE request for all items, and it
//   is all-or-nothing — if any item fails, nothing changes.
// - Record consumption and Discard have no batch endpoint: ONE request PER
//   item. Some can succeed while others fail, so we report each failure.

import { ApiError } from '../../api/client'
import { newIdempotencyKey } from '../../api/idempotencyKey'
import { batchArchive, batchMove, consumeFraction, discardItem, type InventoryItem } from '../../api/inventory'
import type { StorageSpace } from '../../api/storageSpaces'

export interface BulkFailure {
  name: string
  reason: string
}

export interface BulkOutcome {
  /** success: everything worked · partial: some items failed · error: nothing changed */
  kind: 'success' | 'partial' | 'error'
  message: string
  failures: BulkFailure[]
}

/** The choices offered for "Record consumption": a share of what is left of each item. */
export const CONSUME_CHOICES = [
  { fraction: '1/1', label: 'All of it' },
  { fraction: '3/4', label: 'Three quarters' },
  { fraction: '1/2', label: 'Half' },
  { fraction: '1/4', label: 'A quarter' },
]

function itemCount(count: number): string {
  return count === 1 ? '1 item' : `${count} items`
}

function reasonFor(error: unknown): string {
  if (!(error instanceof ApiError)) return 'Something went wrong.'
  // 409 VERSION_CONFLICT: someone (or the phone app) changed the item after the list loaded.
  if (error.code === 'VERSION_CONFLICT') return 'It changed since the list was loaded. The list has been refreshed — try again.'
  return error.message
}

/** Sends one request per item (all at once) and reports which ones failed. */
async function runForEach(
  items: InventoryItem[],
  request: (item: InventoryItem) => Promise<unknown>,
  doneText: string, // "Recorded consumption for"
  failText: string, // "record consumption for"
): Promise<BulkOutcome> {
  // allSettled waits for every request, even when some fail (Promise.all would stop at the first failure).
  const results = await Promise.allSettled(items.map((item) => request(item)))
  const failures: BulkFailure[] = []
  results.forEach((result, index) => {
    if (result.status === 'rejected') {
      failures.push({ name: items[index].item_definition_name, reason: reasonFor(result.reason) })
    }
  })

  const succeeded = items.length - failures.length
  if (failures.length === 0) {
    return { kind: 'success', message: `${doneText} ${itemCount(succeeded)}.`, failures }
  }
  if (succeeded === 0) {
    const which = items.length === 1 ? 'the item' : `any of the ${items.length} items`
    return { kind: 'error', message: `Couldn’t ${failText} ${which}:`, failures }
  }
  return {
    kind: 'partial',
    message: `${doneText} ${succeeded} of ${items.length} items. These didn’t work:`,
    failures,
  }
}

/**
 * CONSUME the same share of every selected item. Each request gets its OWN
 * idempotency key: they are separate actions on separate items, and the key
 * is what lets the backend recognise a repeat of that one action.
 */
export function consumeEach(items: InventoryItem[], fraction: string): Promise<BulkOutcome> {
  return runForEach(
    items,
    (item) => consumeFraction(item, fraction, newIdempotencyKey()),
    'Recorded consumption for',
    'record consumption for',
  )
}

export function discardEach(items: InventoryItem[]): Promise<BulkOutcome> {
  return runForEach(items, discardItem, 'Discarded', 'discard')
}

/** A failed batch changed nothing. The backend may say which item caused it (item_index). */
function batchFailure(error: unknown, items: InventoryItem[], verb: string): BulkOutcome {
  const index = error instanceof ApiError ? error.itemIndex : undefined
  const culprit = index !== undefined ? items[index] : undefined
  if (culprit) {
    return {
      kind: 'error',
      message: `Nothing was ${verb}, because one item couldn’t be:`,
      failures: [{ name: culprit.item_definition_name, reason: reasonFor(error) }],
    }
  }
  return { kind: 'error', message: `Nothing was ${verb}. ${reasonFor(error)}`, failures: [] }
}

export async function moveAll(items: InventoryItem[], space: StorageSpace): Promise<BulkOutcome> {
  try {
    await batchMove(items, space.id)
    return { kind: 'success', message: `Moved ${itemCount(items.length)} to ${space.name}.`, failures: [] }
  } catch (error) {
    return batchFailure(error, items, 'moved')
  }
}

export async function archiveAll(items: InventoryItem[]): Promise<BulkOutcome> {
  try {
    await batchArchive(items)
    return { kind: 'success', message: `Archived ${itemCount(items.length)}.`, failures: [] }
  } catch (error) {
    return batchFailure(error, items, 'archived')
  }
}
