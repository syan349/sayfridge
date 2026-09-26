// Inventory endpoints (docs/API_REFERENCE.md §6–7, backend/app/schemas/inventory.py).
import { apiFetch } from './client'
import type { Page } from './types'

export type InventoryStatus = 'IN_STOCK' | 'EMPTY' | 'DISCARDED' | 'ARCHIVED'

/** InventoryItemRead. Amounts are decimal strings ("2.500"); dates are YYYY-MM-DD. */
export interface InventoryItem {
  id: string
  storage_space_id: string
  storage_space_name: string
  item_definition_id: string
  item_definition_name: string
  category_id: string
  category_name: string
  purchase_date: string | null
  expiry_date: string | null
  notes: string | null
  status: InventoryStatus
  initial_amount: string
  initial_unit: string
  confirmed_current_amount: string
  confirmed_current_unit: string
  confirmed_at: string
  estimated_current_amount: string | null
  estimated_current_unit: string | null
  estimated_at: string | null
  /** What to show: the estimate if there is one (even zero), otherwise the confirmed amount. */
  display_amount: string
  display_unit: string
  is_estimated: boolean
  /** Goes up by one on every change. Writes send it back as expected_version. */
  version: number
  created_at: string
  updated_at: string
}

export interface InventoryQuery {
  status: InventoryStatus | 'ALL'
  /** Search in the item name. */
  q: string
  storageSpaceId: string | null
  categoryId: string | null
  /** Only items expiring on or before this date. Items without an expiry date are left out. */
  expiryTo: string | null
  page: number
  pageSize: number
}

/** GET /inventory-items — one page, sorted by expiry date (soonest first, no date last). */
export function listInventory(query: InventoryQuery, signal?: AbortSignal): Promise<Page<InventoryItem>> {
  return apiFetch<Page<InventoryItem>>('/inventory-items', {
    query: {
      status: query.status,
      q: query.q,
      storage_space_id: query.storageSpaceId,
      category_id: query.categoryId,
      expiry_to: query.expiryTo,
      page: query.page,
      page_size: query.pageSize,
    },
    signal,
  })
}

/** The item as the user last saw it. If someone changed it since, the backend answers 409 VERSION_CONFLICT. */
function versionRef(item: InventoryItem) {
  return { id: item.id, expected_version: item.version }
}

/**
 * POST /inventory-items/{id}/operations — CONSUME a fraction of what is left
 * ("1/2" = half). A fraction works whatever the item's unit is.
 */
export function consumeFraction(item: InventoryItem, fraction: string, idempotencyKey: string) {
  return apiFetch<{ inventory: InventoryItem; replayed: boolean }>(`/inventory-items/${item.id}/operations`, {
    method: 'POST',
    headers: { 'Idempotency-Key': idempotencyKey },
    body: {
      expected_version: item.version,
      operation_type: 'CONSUME',
      quantity_kind: 'FRACTION',
      quantity_value: fraction,
      quantity_unit: 'remaining',
    },
  })
}

/** POST /inventory-items/{id}/discard — only for IN_STOCK items. Keeps the item's history. */
export function discardItem(item: InventoryItem): Promise<InventoryItem> {
  return apiFetch<InventoryItem>(`/inventory-items/${item.id}/discard`, {
    method: 'POST',
    body: { expected_version: item.version },
  })
}

interface BatchResult {
  items: InventoryItem[]
  count: number
}

/** POST /inventory-items/batch-move — all or nothing: if one item fails, none move. */
export function batchMove(items: InventoryItem[], targetSpaceId: string): Promise<BatchResult> {
  return apiFetch<BatchResult>('/inventory-items/batch-move', {
    method: 'POST',
    body: { target_storage_space_id: targetSpaceId, items: items.map(versionRef) },
  })
}

/** POST /inventory-items/batch-archive — all or nothing, like batch-move. */
export function batchArchive(items: InventoryItem[]): Promise<BatchResult> {
  return apiFetch<BatchResult>('/inventory-items/batch-archive', {
    method: 'POST',
    body: { items: items.map(versionRef) },
  })
}
