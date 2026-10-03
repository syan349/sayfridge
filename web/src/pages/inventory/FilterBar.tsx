import type { ItemCategory } from '../../api/categories'
import type { InventoryStatus } from '../../api/inventory'
import type { StorageSpace } from '../../api/storageSpaces'
import { ChipButton } from '../../components/ChipButton/ChipButton'
import { ChipSelect } from '../../components/ChipButton/ChipSelect'
import styles from './FilterBar.module.css'

export interface InventoryFilters {
  spaceId: string | null
  categoryId: string | null
  status: InventoryStatus | 'ALL'
  /** Expiring within the user's "expiring soon" window, including items already past their date. */
  expiringSoon: boolean
}

export interface FilterCounts {
  allSpaces?: number
  bySpace: Record<string, number | undefined>
  expiringSoon?: number
}

const STATUS_OPTIONS = [
  { value: 'IN_STOCK', label: 'In stock' },
  { value: 'EMPTY', label: 'Empty' },
  { value: 'DISCARDED', label: 'Discarded' },
  { value: 'ARCHIVED', label: 'Archived' },
  { value: 'ALL', label: 'All statuses' },
]

interface FilterBarProps {
  filters: InventoryFilters
  spaces: StorageSpace[]
  categories: ItemCategory[]
  /** How many days ahead "expiring soon" looks (the user's reminder preference). */
  soonDays: number
  /** How many items each chip would show; undefined while still loading. */
  counts: FilterCounts
  onChange: (change: Partial<InventoryFilters>) => void
  /** Set when the category list couldn't be loaded: says so, with a retry button. */
  onRetryCategories?: () => void
}

/** "Label · 12", or just "Label" while the number is loading. */
function withCount(label: string, count: number | undefined) {
  return count === undefined ? label : `${label} · ${count}`
}

/** The row of filters under the page header. */
export function FilterBar({ filters, spaces, categories, soonDays, counts, onChange, onRetryCategories }: FilterBarProps) {
  return (
    <div className={styles.bar}>
      <div role="group" aria-label="Storage space" className={styles.group}>
        <ChipButton selected={filters.spaceId === null} onClick={() => onChange({ spaceId: null })}>
          {withCount('All spaces', counts.allSpaces)}
        </ChipButton>
        {spaces.map((space) => (
          <ChipButton key={space.id} selected={filters.spaceId === space.id} onClick={() => onChange({ spaceId: space.id })}>
            {withCount(space.name, counts.bySpace[space.id])}
          </ChipButton>
        ))}
      </div>

      <span className={styles.divider} aria-hidden="true" />

      <ChipSelect
        label="Category"
        value={filters.categoryId ?? ''}
        onChange={(event) => onChange({ categoryId: event.target.value || null })}
        options={[{ value: '', label: 'All categories' }, ...categories.map((c) => ({ value: c.id, label: c.name }))]}
      />
      {onRetryCategories && (
        <span role="alert" className={styles.problem}>
          Categories couldn’t load.{' '}
          <button type="button" className={styles.retry} onClick={onRetryCategories}>
            Try again
          </button>
        </span>
      )}
      <ChipSelect
        label="Status"
        value={filters.status}
        onChange={(event) => onChange({ status: event.target.value as InventoryFilters['status'] })}
        options={STATUS_OPTIONS}
      />
      <ChipButton
        tone="urgent"
        icon="/assets/icons/assistant/warn.png"
        selected={filters.expiringSoon}
        onClick={() => onChange({ expiringSoon: !filters.expiringSoon })}
      >
        {withCount(`Expiring ≤ ${soonDays} ${soonDays === 1 ? 'day' : 'days'}`, counts.expiringSoon)}
      </ChipButton>
    </div>
  )
}
