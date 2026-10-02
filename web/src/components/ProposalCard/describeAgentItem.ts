import type { AgentItem } from '../../api/agent'
import { formatAmount } from '../QuantityCell/formatAmount'

export interface AgentItemSummary {
  /** "Tomatoes" (or the user's own words while the item isn't known yet). */
  name: string
  /** "Vegetables · Kitchen fridge" */
  where: string
  /** "consume 2 each", "new item 2 L" */
  change: string
  /** How much is left afterwards: "9.7 kg", and whether that is an AI estimate. */
  left: { text: string; estimated: boolean } | null
}

/** Is the assistant waiting for the user to act on this item? */
export function isWaiting(item: AgentItem): boolean {
  return item.status === 'NEEDS_CONFIRMATION' || item.status === 'NEEDS_INPUT'
}

/**
 * The save may or may not have happened (the connection broke at the wrong moment).
 * Such an item can only be confirmed again, which checks first and never saves twice.
 */
export function isUncertain(item: AgentItem): boolean {
  return item.error?.code === 'EXECUTION_UNCERTAIN'
}

/**
 * What to ask the user about a waiting item. The backend's `display.question` is
 * written for people ("Where would you like to store the milk?"); `error.message`
 * is only the fallback, because it is often internal ("Select a storage space").
 */
export function itemQuestion(item: AgentItem): string | null {
  if (isUncertain(item)) return 'It isn’t certain this was saved. Confirm to check — it won’t be saved twice.'
  return item.display?.question || item.error?.message || null
}

/**
 * Turns an assistant item into words for the page. The backend's `preview` says what
 * would happen; once saved, `result.inventory` is the real stock item, so that wins.
 */
export function describeAgentItem(item: AgentItem): AgentItemSummary {
  const draft = item.preview?.draft
  const stock = item.result?.inventory ?? item.preview?.before ?? null
  const display = item.display

  const name =
    stock?.item_definition_name ??
    draft?.new_definition?.name ??
    (display?.item_name || draft?.item_query || item.original_text)
  // A new item has no stock row yet; the backend's display still knows its category and space.
  const category = stock?.category_name ?? display?.category_name
  const space = stock?.storage_space_name ?? draft?.new_space?.name ?? display?.space_name
  const where = [category, space].filter(Boolean).join(' · ')

  let change = ''
  if (draft) {
    const action = draft.action === 'CREATE_STOCK' ? 'new item' : draft.action.toLowerCase()
    const amount = draft.quantity_value ? `${formatAmount(draft.quantity_value)} ${draft.quantity_unit ?? ''}` : ''
    change = `${action} ${amount}`.trim()
  }

  return { name, where, change, left: amountLeft(item) }
}

function amountLeft(item: AgentItem): AgentItemSummary['left'] {
  const saved = item.result?.inventory
  if (saved) return { text: `${formatAmount(saved.display_amount)} ${saved.display_unit}`, estimated: saved.is_estimated }

  const after = item.preview?.after
  if (after?.confirmed_current_amount) {
    return { text: `${formatAmount(after.confirmed_current_amount)} ${after.confirmed_current_unit ?? ''}`.trim(), estimated: false }
  }
  if (after?.amount) {
    return { text: `${formatAmount(after.amount)} ${after.unit ?? ''}`.trim(), estimated: after.is_estimated ?? false }
  }
  return null
}
