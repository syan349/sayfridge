import { keepPreviousData, useQueries, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { listCategories } from '../../api/categories'
import { listInventory, type InventoryItem, type InventoryQuery } from '../../api/inventory'
import { listStorageSpaces } from '../../api/storageSpaces'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { ExpiryChip } from '../../components/ExpiryChip/ExpiryChip'
import { ItemCell } from '../../components/ItemCell/ItemCell'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { QuantityCell } from '../../components/QuantityCell/QuantityCell'
import { SearchField } from '../../components/SearchField/SearchField'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { addDays, todayLocal } from '../../lib/dates'
import { useDebouncedValue } from '../../lib/useDebouncedValue'
import { BulkBar } from './BulkBar'
import { BulkResult } from './BulkResult'
import type { BulkOutcome } from './bulkActions'
import { FilterBar, type InventoryFilters } from './FilterBar'
import styles from './InventoryPage.module.css'

export const PAGE_SIZE = 20
const EXPIRING_SOON_DAYS = 3
const DEFAULT_FILTERS: InventoryFilters = { spaceId: null, categoryId: null, status: 'IN_STOCK', expiringSoon: false }

/** Turns what the user picked into the request for GET /inventory-items. */
function toQuery(filters: InventoryFilters, search: string, page: number, pageSize: number, today: string): InventoryQuery {
  return {
    status: filters.status,
    q: search.trim(),
    storageSpaceId: filters.spaceId,
    categoryId: filters.categoryId,
    // "Expiring ≤ 3 days" = expiry date up to 3 days from today (already expired included).
    expiryTo: filters.expiringSoon ? addDays(today, EXPIRING_SOON_DAYS) : null,
    page,
    pageSize,
  }
}

/** A request that only wants the number of matches: one row per page, and we read `total`. */
function countQuery(query: InventoryQuery) {
  return {
    queryKey: ['inventory', 'count', query],
    queryFn: ({ signal }: { signal: AbortSignal }) => listInventory(query, signal).then((page) => page.total),
  }
}

/** W03 — Inventory workspace: filters, a paged table, and bulk actions on selected rows. */
export function InventoryPage() {
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const today = todayLocal()

  const [filters, setFilters] = useState(DEFAULT_FILTERS)
  const [searchText, setSearchText] = useState('')
  const search = useDebouncedValue(searchText) // wait for a pause in typing before searching
  const [page, setPage] = useState(1)
  // Selected rows, by id. We keep the whole item because writes need its current version.
  const [selected, setSelected] = useState<Map<string, InventoryItem>>(new Map())
  const [outcome, setOutcome] = useState<BulkOutcome | null>(null)

  // ---------- Data ----------
  const listQuery = toQuery(filters, search, page, PAGE_SIZE, today)
  const inventory = useQuery({
    // React Query caches by this key: any change in the filters is a new key, so a new request.
    queryKey: ['inventory', 'list', listQuery],
    queryFn: ({ signal }) => listInventory(listQuery, signal),
    placeholderData: keepPreviousData, // keep showing the old rows while the next page loads
  })
  const spaces = useQuery({ queryKey: ['storage-spaces'], queryFn: ({ signal }) => listStorageSpaces(signal) })
  const categories = useQuery({ queryKey: ['item-categories'], queryFn: ({ signal }) => listCategories(signal) })
  const spaceList = spaces.data?.items ?? []

  // The number on each chip = what that chip would show, with the other filters kept.
  const countWith = (change: Partial<InventoryFilters>) => toQuery({ ...filters, ...change }, search, 1, 1, today)
  const chipQueries = {
    allSpaces: countWith({ spaceId: null }),
    expiringSoon: countWith({ expiringSoon: true }),
    bySpace: spaceList.map((space) => countWith({ spaceId: space.id })),
  }
  // Two chips can ask the very same question (e.g. "All spaces" while "Expiring" is already on),
  // so each distinct question is sent once and the chips look their answer up by key.
  const keyOf = (query: InventoryQuery) => JSON.stringify(query)
  const distinctQueries = [
    ...new Map(
      [chipQueries.allSpaces, chipQueries.expiringSoon, ...chipQueries.bySpace].map((query) => [keyOf(query), query]),
    ).values(),
  ]
  const countResults = useQueries({ queries: distinctQueries.map(countQuery) })
  const countFor = (query: InventoryQuery) =>
    countResults[distinctQueries.findIndex((distinct) => keyOf(distinct) === keyOf(query))]?.data

  const rows = inventory.data?.items ?? []
  const total = inventory.data?.total ?? 0

  // ---------- Changing filters, pages and the selection ----------
  // Any change of what is listed clears the selection, so hidden rows are never acted on.
  function changeFilters(change: Partial<InventoryFilters>) {
    setFilters((current) => ({ ...current, ...change }))
    setPage(1)
    setSelected(new Map())
  }

  function changeSearch(value: string) {
    setSearchText(value)
    setPage(1)
    setSelected(new Map())
  }

  function clearFilters() {
    setFilters(DEFAULT_FILTERS)
    changeSearch('')
  }

  function goToPage(nextPage: number) {
    setPage(nextPage)
    setSelected(new Map())
  }

  function toggleRow(id: string) {
    const row = rows.find((item) => item.id === id)
    setSelected((current) => {
      const next = new Map(current)
      if (next.has(id)) next.delete(id)
      else if (row) next.set(id, row)
      return next
    })
  }

  function toggleAll() {
    setSelected((current) => {
      const allOn = rows.every((item) => current.has(item.id))
      const next = new Map(current)
      for (const item of rows) {
        if (allOn) next.delete(item.id)
        else next.set(item.id, item)
      }
      return next
    })
  }

  function handleBulkFinished(result: BulkOutcome) {
    setOutcome(result)
    setSelected(new Map())
    // Reload the list and every count: items may have moved, changed or disappeared.
    void queryClient.invalidateQueries({ queryKey: ['inventory'] })
  }

  // ---------- Table ----------
  const columns: Column<InventoryItem>[] = [
    {
      key: 'item',
      header: 'Item',
      render: (item) => <ItemCell name={item.item_definition_name} to={`/inventory/${item.id}`} />,
    },
    { key: 'category', header: 'Category', width: '130px', render: (item) => item.category_name },
    { key: 'space', header: 'Space', width: '120px', render: (item) => item.storage_space_name },
    { key: 'quantity', header: 'Quantity', width: '200px', render: (item) => <QuantityCell item={item} /> },
    {
      key: 'expires',
      header: 'Expires',
      width: '150px',
      render: (item) => <ExpiryChip expiryDate={item.expiry_date} today={today} />,
    },
    { key: 'status', header: 'Status', width: '112px', render: (item) => <StatusPill status={item.status} /> },
  ]

  const isFiltered =
    filters.spaceId !== null ||
    filters.categoryId !== null ||
    filters.status !== 'IN_STOCK' ||
    filters.expiringSoon ||
    search.trim() !== ''

  // Loading, error and empty states all appear inside the table.
  let message: ReactNode = null
  if (inventory.isPending) {
    message = <p role="status">Loading your inventory…</p>
  } else if (inventory.isError) {
    message = (
      <div role="alert" className={styles.stateBox}>
        <p className={styles.stateTitle}>We couldn’t load your inventory.</p>
        <p className={styles.stateText}>{inventory.error.message}</p>
        <Button variant="secondary" size="sm" onClick={() => void inventory.refetch()}>
          Try again
        </Button>
      </div>
    )
  } else if (total === 0 && isFiltered) {
    message = (
      <div className={styles.stateBox}>
        <p className={styles.stateTitle}>No items match these filters.</p>
        <Button variant="secondary" size="sm" onClick={clearFilters}>
          Clear filters
        </Button>
      </div>
    )
  } else if (total === 0) {
    message = (
      <div className={styles.stateBox}>
        <p className={styles.stateTitle}>Your inventory is empty.</p>
        <p className={styles.stateText}>Add what’s in your fridge here, or by voice or a receipt photo in the phone app.</p>
        <ButtonLink to="/inventory/new" size="sm">
          Add items
        </ButtonLink>
      </div>
    )
  } else if (rows.length === 0) {
    // E.g. the last item on page 3 was just archived.
    message = (
      <div className={styles.stateBox}>
        <p className={styles.stateTitle}>Nothing on this page any more.</p>
        <Button variant="secondary" size="sm" onClick={() => goToPage(1)}>
          Back to the first page
        </Button>
      </div>
    )
  }

  const firstShown = (page - 1) * PAGE_SIZE + 1
  const lastShown = Math.min(page * PAGE_SIZE, total)
  const allSpacesTotal = countFor(chipQueries.allSpaces)

  return (
    <>
      <PageHeader
        title="Inventory"
        subtitle={
          allSpacesTotal !== undefined && spaces.data
            ? `${allSpacesTotal} ${allSpacesTotal === 1 ? 'item' : 'items'} across ${spaceList.length} storage ${spaceList.length === 1 ? 'space' : 'spaces'}`
            : undefined
        }
        actions={
          <>
            <SearchField
              label="Search inventory"
              placeholder="Search by item name…"
              value={searchText}
              onChange={(event) => changeSearch(event.target.value)}
            />
            <ButtonLink to="/inventory/new" icon="/assets/icons/assistant/add.png">
              Add items
            </ButtonLink>
          </>
        }
      />

      <FilterBar
        filters={filters}
        spaces={spaceList}
        categories={categories.data?.items ?? []}
        counts={{
          allSpaces: allSpacesTotal,
          expiringSoon: countFor(chipQueries.expiringSoon),
          bySpace: Object.fromEntries(spaceList.map((space, index) => [space.id, countFor(chipQueries.bySpace[index])])),
        }}
        onChange={changeFilters}
      />

      {selected.size > 0 && (
        <BulkBar
          items={[...selected.values()]}
          spaces={spaceList}
          onClear={() => setSelected(new Map())}
          onFinished={handleBulkFinished}
        />
      )}

      <div className={styles.content}>
        {outcome && <BulkResult outcome={outcome} onDismiss={() => setOutcome(null)} />}

        <div className={styles.tableArea}>
          <DataTable
            caption="Inventory items"
            columns={columns}
            rows={rows}
            getRowId={(item) => item.id}
            getRowLabel={(item) => item.item_definition_name}
            selection={{ selectedIds: new Set(selected.keys()), onToggleRow: toggleRow, onToggleAll: toggleAll }}
            message={message}
            busy={inventory.isFetching && !inventory.isPending}
            onRowClick={(item) => navigate(`/inventory/${item.id}`)}
          />
        </div>

        {total > 0 && rows.length > 0 && (
          <nav aria-label="Pages" className={styles.pagination}>
            <span className={styles.showing}>
              Showing {firstShown}–{lastShown} of {total} items
            </span>
            <Button variant="secondary" size="sm" disabled={page === 1} onClick={() => goToPage(page - 1)}>
              Previous
            </Button>
            <Button variant="secondary" size="sm" disabled={lastShown >= total} onClick={() => goToPage(page + 1)}>
              Next
            </Button>
          </nav>
        )}
      </div>
    </>
  )
}
