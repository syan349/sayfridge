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

export type ExpiryBucket = 'overdue' | 'today' | 'upcoming'

/** An in-stock item plus which expiry group it falls in. */
export interface ExpiryItem extends InventoryItem {
  bucket: ExpiryBucket
}

/** GET /inventory-items/expiry-summary: counts for all three groups, plus one page of items. */
export interface ExpirySummary extends Page<ExpiryItem> {
  counts: Record<ExpiryBucket, number>
}

export interface ExpiryQuery {
  /** "Today" as the user sees it (YYYY-MM-DD). The server doesn't know the user's time zone. */
  asOf: string
  /** How many days after today count as "upcoming". */
  daysBefore: number
  storageSpaceId: string | null
  /** Only this group in `items` (the counts always cover all three). */
  bucket: ExpiryBucket | null
  page: number
  pageSize: number
}

/**
 * GET /inventory-items/expiry-summary — IN_STOCK items that are overdue, expire
 * today, or expire within `daysBefore` days, soonest first. Items without a date,
 * or expiring later, are left out.
 */
export function getExpirySummary(query: ExpiryQuery, signal?: AbortSignal): Promise<ExpirySummary> {
  return apiFetch<ExpirySummary>('/inventory-items/expiry-summary', {
    query: {
      as_of: query.asOf,
      days_before: query.daysBefore,
      storage_space_id: query.storageSpaceId,
      bucket: query.bucket,
      page: query.page,
      page_size: query.pageSize,
    },
    signal,
  })
}

/** GET /inventory-items/{id} — one item, in any status. */
export function getInventoryItem(id: string, signal?: AbortSignal): Promise<InventoryItem> {
  return apiFetch<InventoryItem>(`/inventory-items/${id}`, { signal })
}

export type OperationType = 'ADD' | 'CONSUME' | 'RECONCILE'

/** InventoryOperationRead (backend/app/schemas/inventory_operations.py). */
export interface InventoryOperation {
  id: string
  inventory_item_id: string
  operation_type: OperationType
  quantity_kind: 'AMOUNT' | 'FRACTION' | 'QUALITATIVE'
  /** What the user entered, word for word: "500", "1/2". */
  quantity_value: string
  quantity_unit: string | null
  input_method: 'TEXT' | 'VOICE' | 'PHOTO' | 'RECEIPT' | 'MANUAL'
  calculation_method: 'EXACT' | 'CONVERTED' | 'AI_ESTIMATED'
  affects_state: 'CONFIRMED' | 'ESTIMATED'
  /** How much was actually added or taken away, in the item's unit. Null for RECONCILE. */
  applied_change_amount: string | null
  applied_change_unit: string | null
  /** Only SUCCESS changed the quantity; the other states are history. */
  status: 'PENDING_CONFIRMATION' | 'SUCCESS' | 'FAILED' | 'UNDONE'
  created_at: string
  updated_at: string
  undone_at: string | null
}

/** GET /inventory-items/{id}/operations — the item's whole history, newest first. */
export function listItemOperations(id: string, signal?: AbortSignal): Promise<InventoryOperation[]> {
  return apiFetch<InventoryOperation[]>(`/inventory-items/${id}/operations`, { signal })
}

/** GET /inventory-operations — the newest changes across all of the user's items. */
export function listRecentOperations(pageSize: number, signal?: AbortSignal): Promise<Page<InventoryOperation>> {
  return apiFetch<Page<InventoryOperation>>('/inventory-operations', { query: { page_size: pageSize }, signal })
}

/** The item as the user last saw it. If someone changed it since, the backend answers 409 VERSION_CONFLICT. */
function versionRef(item: InventoryItem) {
  return { id: item.id, expected_version: item.version }
}

export interface OperationInput {
  type: OperationType
  kind: 'AMOUNT' | 'FRACTION'
  /** Decimal text ("0.5", at most 3 decimals) or a fraction ("1/2"). */
  value: string
  /** A unit such as "g" or "L"; "remaining" for fractions. */
  unit: string
}

/**
 * POST /inventory-items/{id}/operations — the only way a quantity changes.
 * The Idempotency-Key makes a repeat of the same action (a retry) count once.
 */
export function recordOperation(item: InventoryItem, input: OperationInput, idempotencyKey: string) {
  return apiFetch<{ operation: InventoryOperation; inventory: InventoryItem; replayed: boolean }>(
    `/inventory-items/${item.id}/operations`,
    {
      method: 'POST',
      headers: { 'Idempotency-Key': idempotencyKey },
      body: {
        expected_version: item.version,
        operation_type: input.type,
        quantity_kind: input.kind,
        quantity_value: input.value,
        quantity_unit: input.unit,
      },
    },
  )
}

/** CONSUME a fraction of what is left ("1/2" = half). A fraction works whatever the item's unit is. */
export function consumeFraction(item: InventoryItem, fraction: string, idempotencyKey: string) {
  return recordOperation(item, { type: 'CONSUME', kind: 'FRACTION', value: fraction, unit: 'remaining' }, idempotencyKey)
}

/** The fields PATCH may change. null clears a date or the notes. */
export interface ItemChanges {
  storage_space_id?: string
  purchase_date?: string | null
  expiry_date?: string | null
  notes?: string | null
}

/** PATCH /inventory-items/{id} — only the fields sent change; quantities can't be changed here. */
export function updateItem(item: InventoryItem, changes: ItemChanges): Promise<InventoryItem> {
  return apiFetch<InventoryItem>(`/inventory-items/${item.id}`, {
    method: 'PATCH',
    body: { expected_version: item.version, ...changes },
  })
}

/** POST /inventory-items/{id}/discard — only for IN_STOCK items. Keeps the item's history. */
export function discardItem(item: InventoryItem): Promise<InventoryItem> {
  return apiFetch<InventoryItem>(`/inventory-items/${item.id}/discard`, {
    method: 'POST',
    body: { expected_version: item.version },
  })
}

/** POST /inventory-items/{id}/archive — for IN_STOCK or EMPTY items. Keeps the item's history. */
export function archiveItem(item: InventoryItem): Promise<InventoryItem> {
  return apiFetch<InventoryItem>(`/inventory-items/${item.id}/archive`, {
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
