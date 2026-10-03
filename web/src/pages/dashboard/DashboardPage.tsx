import { useQueries, useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { getInventoryItem, listInventory, listRecentOperations, type InventoryOperation } from '../../api/inventory'
import { IN_STOCK_COUNT, attentionQuery, inventoryCountQuery, storageSpacesQuery } from '../../api/queries'
import { useAuth } from '../../auth/AuthContext'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { Card } from '../../components/Card/Card'
import { ExpiryChip } from '../../components/ExpiryChip/ExpiryChip'
import { ItemCell } from '../../components/ItemCell/ItemCell'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { formatAmount } from '../../components/QuantityCell/formatAmount'
import { QuantityCell } from '../../components/QuantityCell/QuantityCell'
import { StatTile } from '../../components/StatTile/StatTile'
import { TypeTag } from '../../components/Tag/Tag'
import { formatLongDate, formatRelative, greeting, todayLocal } from '../../lib/dates'
import { useReminders } from '../../lib/useReminders'
import { useItemActions } from '../itemDetails/useItemActions'
import styles from './DashboardPage.module.css'

const ESTIMATE_SAMPLE = 100 // the backend's largest page

/** "used 0.3 kg", "added 500 g", "confirmed 10 kg" */
function describe(operation: InventoryOperation): string {
  const approx = operation.calculation_method === 'AI_ESTIMATED' ? '≈ ' : ''
  if (operation.operation_type === 'RECONCILE') return `confirmed ${operation.quantity_value} ${operation.quantity_unit ?? ''}`
  const amount =
    operation.applied_change_amount !== null
      ? `${formatAmount(operation.applied_change_amount)} ${operation.applied_change_unit ?? ''}`
      : `${operation.quantity_value} ${operation.quantity_unit ?? ''}`
  return `${operation.operation_type === 'ADD' ? 'added' : 'used'} ${approx}${amount}`
}

/** Home page: the household at a glance, with what needs doing first. */
export function DashboardPage() {
  const { user } = useAuth()
  const today = todayLocal()
  const name = user?.email.split('@')[0] ?? ''
  const { actionsFor, dialogs, notice, clearNotice } = useItemActions()
  const { reminders } = useReminders() // how many days ahead counts as "expiring soon"
  const soonDays = `${reminders.daysBefore} ${reminders.daysBefore === 1 ? 'day' : 'days'}`

  // ---------- Data (the same query keys as the sidebar and W03, so answers are shared) ----------
  const inStock = useQuery(inventoryCountQuery(IN_STOCK_COUNT))
  const attention = useQuery(attentionQuery(today, reminders.daysBefore))
  const spaces = useQuery(storageSpacesQuery)
  const spaceList = spaces.data?.items ?? []
  const spaceCounts = useQueries({
    queries: spaceList.map((space) => inventoryCountQuery({ ...IN_STOCK_COUNT, storageSpaceId: space.id })),
  })
  // There is no "only estimates" filter, so count them among (up to) the first 100 items in stock.
  const sample = useQuery({
    queryKey: ['inventory', 'list', { ...IN_STOCK_COUNT, pageSize: ESTIMATE_SAMPLE }],
    queryFn: ({ signal }) => listInventory({ ...IN_STOCK_COUNT, pageSize: ESTIMATE_SAMPLE }, signal),
  })
  const activity = useQuery({
    queryKey: ['inventory', 'operations', 'recent'],
    queryFn: ({ signal }) => listRecentOperations(5, signal),
  })
  // Operations only carry an item id; look the names up (the item page uses the same cache).
  const activityItemIds = [...new Set((activity.data?.items ?? []).map((op) => op.inventory_item_id))]
  const activityItems = useQueries({
    queries: activityItemIds.map((id) => ({
      queryKey: ['inventory', 'item', id],
      queryFn: ({ signal }: { signal: AbortSignal }) => getInventoryItem(id, signal),
    })),
  })
  const nameOf = (id: string) => activityItems[activityItemIds.indexOf(id)]?.data?.item_definition_name ?? 'An item'

  const counts = attention.data?.counts
  const needsAttention = counts ? counts.overdue + counts.today + counts.upcoming : undefined
  const estimatedCount = sample.data?.items.filter((item) => item.is_estimated).length
  const largestSpace = Math.max(1, ...spaceCounts.map((count) => count.data ?? 0))

  const subtitleParts = [formatLongDate(today)]
  if (inStock.data !== undefined && spaces.data) {
    subtitleParts.push(`${inStock.data} items across ${spaceList.length} ${spaceList.length === 1 ? 'space' : 'spaces'}`)
  }
  if (counts && counts.overdue > 0) subtitleParts.push(`${counts.overdue} overdue`)

  return (
    <>
      <PageHeader
        title={`${greeting()}, ${name}`}
        documentTitle="Dashboard"
        subtitle={subtitleParts.join(' · ')}
        leading={
          <span className={styles.avatar} aria-hidden="true">
            <img src="/assets/avatars/default_avatar.png" alt="" width={34} height={34} />
          </span>
        }
        actions={
          <>
            <ButtonLink to="/inventory/new" variant="secondary" icon="/assets/icons/assistant/add.png">
              Add items
            </ButtonLink>
            {/* The chat icon, not the round AI mark: icons on green buttons are turned white, and the mark would become a blank disc. */}
            <ButtonLink to="/assistant" icon="/assets/icons/assistant/chat.png">
              Ask the assistant
            </ButtonLink>
          </>
        }
      />

      <div className={styles.page}>
        {notice && (
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
        )}

        <div className={styles.tiles}>
          <StatTile
            label="In stock"
            icon="/assets/icons/assistant/report.png"
            value={inStock.data}
            unit="items"
            meta={spaceList.map((space, index) => `${space.name} ${spaceCounts[index]?.data ?? '…'}`).join(' · ') || 'No storage spaces yet'}
          />
          <StatTile
            label="Needs attention"
            icon="/assets/icons/assistant/warn.png"
            value={needsAttention}
            unit="items"
            tone={needsAttention ? 'attention' : 'plain'}
            meta={
              counts && counts.overdue > 0
                ? `${counts.overdue} already overdue`
                : `Nothing overdue — expiring within ${soonDays}`
            }
          />
          <StatTile
            label="AI estimated"
            icon="/assets/icons/assistant/ai_assistant.png"
            value={estimatedCount}
            unit="items"
            meta={estimatedCount ? 'Reconcile to confirm exact amounts' : 'All amounts are confirmed'}
          />
        </div>

        <div className={styles.columns}>
          <Card title="Needs attention" action={<Link to="/expiry">All expiry →</Link>}>
            {attention.isPending && <p role="status">Loading…</p>}
            {attention.isError && (
              <p role="alert" className={styles.error}>
                We couldn’t load this. {attention.error.message}{' '}
                <Button variant="secondary" size="sm" onClick={() => void attention.refetch()}>
                  Try again
                </Button>
              </p>
            )}
            {attention.data && attention.data.items.length === 0 && (
              <p className={styles.empty}>Nothing is overdue or expiring in the next {soonDays}.</p>
            )}
            {attention.data && attention.data.items.length > 0 && (
              <ul className={styles.attentionList}>
                {attention.data.items.map((item) => (
                  <li key={item.id} className={styles.attentionRow}>
                    <div className={styles.attentionItem}>
                      <ItemCell name={item.item_definition_name} to={`/inventory/${item.id}`} />
                      <span className={styles.rowMeta}>
                        {item.category_name} · {item.storage_space_name}
                      </span>
                    </div>
                    <QuantityCell item={item} />
                    <ExpiryChip expiryDate={item.expiry_date} today={today} showDate={false} />
                    {actionsFor(item, true)}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          <div className={styles.sideColumn}>
            <Card title="Storage spaces" action={<Link to="/spaces">Manage →</Link>}>
              {spaces.isPending && <p role="status">Loading…</p>}
              {spaces.isError && (
                <p role="alert" className={styles.error}>
                  We couldn’t load your spaces. {spaces.error.message}
                </p>
              )}
              {spaces.data && spaceList.length === 0 && (
                <p className={styles.empty}>
                  No storage spaces yet. <Link to="/spaces">Add your fridge</Link> to start.
                </p>
              )}
              {spaceList.length > 0 && (
                <ul className={styles.spaceList}>
                  {spaceList.map((space, index) => {
                    const count = spaceCounts[index]?.data
                    return (
                      <li key={space.id} className={styles.spaceRow}>
                        <span className={styles.spaceName}>{space.name}</span>
                        {/* The bar is decoration; the number next to it says the same thing. */}
                        <span className={styles.bar} aria-hidden="true">
                          <span style={{ width: `${((count ?? 0) / largestSpace) * 100}%` }} />
                        </span>
                        <span className={styles.spaceCount}>
                          {count === undefined ? '…' : count === 0 ? 'empty' : `${count} ${count === 1 ? 'item' : 'items'}`}
                        </span>
                      </li>
                    )
                  })}
                </ul>
              )}
            </Card>

            <Card title="Recent activity">
              {activity.isPending && <p role="status">Loading…</p>}
              {activity.isError && (
                <p role="alert" className={styles.error}>
                  We couldn’t load the activity. {activity.error.message}
                </p>
              )}
              {activity.data && activity.data.items.length === 0 && (
                <p className={styles.empty}>No changes recorded yet.</p>
              )}
              {activity.data && activity.data.items.length > 0 && (
                <ul className={styles.activityList}>
                  {activity.data.items.map((operation) => (
                    <li key={operation.id} className={styles.activityRow}>
                      <TypeTag type={operation.operation_type} />
                      <Link to={`/inventory/${operation.inventory_item_id}`} className={styles.activityText}>
                        {nameOf(operation.inventory_item_id)} — {describe(operation)}
                      </Link>
                      <time dateTime={operation.created_at} className={styles.activityTime}>
                        {formatRelative(operation.created_at)}
                      </time>
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          </div>
        </div>
      </div>

      {dialogs}
    </>
  )
}
