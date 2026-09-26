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
 * Turns an assistant item into words for the page. The backend's `preview` says what
 * would happen; once saved, `result.inventory` is the real stock item, so that wins.
 */
export function describeAgentItem(item: AgentItem): AgentItemSummary {
  const draft = item.preview?.draft
  const stock = item.result?.inventory ?? item.preview?.before ?? null

  const name = stock?.item_definition_name ?? draft?.new_definition?.name ?? (draft?.item_query || item.original_text)
  const where = [stock?.category_name, stock?.storage_space_name ?? draft?.new_space?.name].filter(Boolean).join(' · ')

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
