// Query definitions used by more than one screen. The same key means the same
// cache entry: the sidebar count, the dashboard and the inventory page all read
// "how many items are in stock" from ONE request, not three.
import { listCategories } from './categories'
import { getExpirySummary, listInventory, type ExpiryQuery, type InventoryQuery } from './inventory'
import { listStorageSpaces } from './storageSpaces'

/** Every IN_STOCK item, no filters. Used with page size 1 when only the total is needed. */
export const IN_STOCK_COUNT: InventoryQuery = {
  status: 'IN_STOCK',
  q: '',
  storageSpaceId: null,
  categoryId: null,
  expiryTo: null,
  page: 1,
  pageSize: 1,
}

/** How many items match a query: one row per page, and we read `total`. */
export function inventoryCountQuery(query: InventoryQuery) {
  return {
    queryKey: ['inventory', 'count', query],
    queryFn: ({ signal }: { signal: AbortSignal }) => listInventory(query, signal).then((page) => page.total),
  }
}

export function expirySummaryQuery(query: ExpiryQuery) {
  return {
    queryKey: ['inventory', 'expiry-summary', query],
    queryFn: ({ signal }: { signal: AbortSignal }) => getExpirySummary(query, signal),
  }
}

/** "Needs attention": overdue, today and the next 3 days — the first 5, for the dashboard and the sidebar. */
export function attentionQuery(today: string) {
  return expirySummaryQuery({ asOf: today, daysBefore: 3, storageSpaceId: null, bucket: null, page: 1, pageSize: 5 })
}

export const storageSpacesQuery = {
  queryKey: ['storage-spaces'],
  queryFn: ({ signal }: { signal: AbortSignal }) => listStorageSpaces(signal),
}

// All visible categories (every page). Used by the inventory filter and by "create
// your own item". Users can add their own categories (e.g. from the phone or the
// assistant), so the list is refreshed after 5 minutes instead of never.
export const categoriesQuery = {
  queryKey: ['item-categories'],
  queryFn: ({ signal }: { signal: AbortSignal }) => listCategories(signal),
  staleTime: 5 * 60 * 1000,
}
