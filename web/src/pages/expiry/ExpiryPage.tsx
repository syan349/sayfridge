import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { useState, type ReactNode } from 'react'
import type { ExpiryBucket, ExpiryItem, ExpiryQuery } from '../../api/inventory'
import { expirySummaryQuery, storageSpacesQuery } from '../../api/queries'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { ChipSelect } from '../../components/ChipButton/ChipSelect'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { ExpiryChip } from '../../components/ExpiryChip/ExpiryChip'
import { ItemCell } from '../../components/ItemCell/ItemCell'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { Pagination } from '../../components/Pagination/Pagination'
import { QuantityCell } from '../../components/QuantityCell/QuantityCell'
import { formatLongDate, todayLocal } from '../../lib/dates'
import { useReminders } from '../../lib/useReminders'
import { useItemActions } from '../itemDetails/useItemActions'
import styles from './ExpiryPage.module.css'

const PAGE_SIZE = 20
const DAY_CHOICES = [3, 7, 14]

/** "3 days", "1 day" */
const daysText = (days: number) => `${days} ${days === 1 ? 'day' : 'days'}`

/** W09 — Expiry overview: what is overdue, expires today, or expires soon, with quick actions. */
export function ExpiryPage() {
  // "Today" comes from the browser: the server doesn't know the user's time zone
  // (New Zealand is up to 13 hours ahead of UTC).
  const today = todayLocal()
  // The look-ahead starts at the user's reminder preference (Profile & settings).
  const { reminders } = useReminders()
  const [daysBefore, setDaysBefore] = useState(reminders.daysBefore)
  const dayChoices = [...new Set([reminders.daysBefore, ...DAY_CHOICES])].sort((a, b) => a - b)
  const [bucket, setBucket] = useState<ExpiryBucket | null>(null)
  const [spaceId, setSpaceId] = useState<string | null>(null)
  const [page, setPage] = useState(1)
  const { actionsFor, dialogs, notice, clearNotice } = useItemActions()

  const query: ExpiryQuery = { asOf: today, daysBefore, storageSpaceId: spaceId, bucket, page, pageSize: PAGE_SIZE }
  const summary = useQuery({ ...expirySummaryQuery(query), placeholderData: keepPreviousData })
  const spaces = useQuery(storageSpacesQuery)

  // The counts always cover all three groups; `bucket` only narrows the table.
  const counts = summary.data?.counts
  const tiles: { bucket: ExpiryBucket; label: string; tone: string }[] = [
    { bucket: 'overdue', label: 'Overdue', tone: styles.overdue },
    { bucket: 'today', label: 'Today', tone: styles.today },
    { bucket: 'upcoming', label: `Next ${daysText(daysBefore)}`, tone: styles.upcoming },
  ]

  function toggleBucket(next: ExpiryBucket) {
    setBucket((current) => (current === next ? null : next)) // clicking the chosen tile again shows everything
    setPage(1)
  }

  const columns: Column<ExpiryItem>[] = [
    {
      key: 'item',
      header: 'Item',
      render: (item) => <ItemCell name={item.item_definition_name} to={`/inventory/${item.id}`} />,
    },
    { key: 'category', header: 'Category', width: '120px', render: (item) => item.category_name },
    { key: 'space', header: 'Space', width: '110px', render: (item) => item.storage_space_name },
    { key: 'quantity', header: 'Quantity', width: '170px', render: (item) => <QuantityCell item={item} /> },
    {
      key: 'expires',
      header: 'Expires',
      width: '150px',
      render: (item) => <ExpiryChip expiryDate={item.expiry_date} today={today} />,
    },
    {
      key: 'actions',
      header: 'Actions',
      width: '230px',
      render: (item) => <div className={styles.actions}>{actionsFor(item)}</div>,
    },
  ]

  const total = summary.data?.total ?? 0
  const rows = summary.data?.items ?? []

  let message: ReactNode = null
  if (summary.isPending) {
    message = <p role="status">Loading what’s expiring…</p>
  } else if (summary.isError) {
    message = (
      <div role="alert" className={styles.stateBox}>
        <p className={styles.stateTitle}>We couldn’t load the expiry overview.</p>
        <p>{summary.error.message}</p>
        <Button variant="secondary" size="sm" onClick={() => void summary.refetch()}>
          Try again
        </Button>
      </div>
    )
  } else if (total === 0) {
    message = (
      <div className={styles.stateBox}>
        <p className={styles.stateTitle}>
          {bucket ? 'Nothing in this group.' : `Nothing is overdue or expiring in the next ${daysText(daysBefore)}.`}
        </p>
        <p>Items without an expiry date aren’t listed here.</p>
      </div>
    )
  }

  return (
    <>
      <PageHeader
        title="Expiry overview"
        subtitle={`${formatLongDate(today)} · sorted by soonest expiry`}
        actions={
          <>
            <ChipSelect
              label="Storage space"
              value={spaceId ?? ''}
              onChange={(event) => {
                setSpaceId(event.target.value || null)
                setPage(1)
              }}
              options={[
                { value: '', label: 'All spaces' },
                ...(spaces.data?.items ?? []).map((space) => ({ value: space.id, label: space.name })),
              ]}
            />
            <ChipSelect
              label="Look ahead"
              value={String(daysBefore)}
              onChange={(event) => {
                setDaysBefore(Number(event.target.value))
                setPage(1)
              }}
              options={dayChoices.map((days) => ({ value: String(days), label: `Next ${daysText(days)}` }))}
            />
          </>
        }
      />

      <div className={styles.tileBar}>
        <div role="group" aria-label="Show only" className={styles.tiles}>
          {tiles.map((tile) => (
            <button
              key={tile.bucket}
              type="button"
              className={`${styles.tile} ${tile.tone}`}
              aria-pressed={bucket === tile.bucket}
              onClick={() => toggleBucket(tile.bucket)}
            >
              <span className={styles.tileValue}>
                {tile.bucket === 'overdue' && (
                  <img src="/assets/icons/assistant/warn.png" alt="" width={20} height={20} />
                )}
                {counts ? counts[tile.bucket] : '–'}
              </span>
              <span className={styles.tileLabel}>{tile.label}</span>
            </button>
          ))}
        </div>
        <p className={styles.tileHint}>
          {bucket ? 'Click the highlighted tile again to show everything.' : 'Click a tile to show only that group.'}
        </p>
      </div>

      <div className={styles.content}>
        {notice && (
          <div className={styles.notice}>
            <Banner
              tone={notice.tone}
              title={notice.title}
              role={notice.tone === 'warning' ? 'alert' : 'status'}
              action={
                <Button variant="secondary" size="sm" onClick={clearNotice}>
                  Dismiss
                </Button>
              }
            >
              {notice.text}
            </Banner>
          </div>
        )}

        <DataTable
          caption="Items by expiry date"
          columns={columns}
          rows={rows}
          getRowId={(item) => item.id}
          getRowLabel={(item) => item.item_definition_name}
          message={message}
          busy={summary.isFetching && !summary.isPending}
        />

        {total > 0 && rows.length > 0 && (
          <Pagination page={page} pageSize={PAGE_SIZE} total={total} noun="items" onPageChange={setPage} />
        )}
      </div>

      {dialogs}
    </>
  )
}
