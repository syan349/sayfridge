import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { ApiError, isVersionConflict } from '../../api/client'
import {
  archiveItem,
  discardItem,
  getInventoryItem,
  listItemOperations,
  type InventoryItem,
  type OperationType,
} from '../../api/inventory'
import { listStorageSpaces } from '../../api/storageSpaces'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { Card } from '../../components/Card/Card'
import { ConfirmDialog } from '../../components/Dialog/ConfirmDialog'
import { ExpiryChip } from '../../components/ExpiryChip/ExpiryChip'
import { foodIconFor } from '../../components/ItemCell/foodIcon'
import { OperationTimeline } from '../../components/OperationTimeline/OperationTimeline'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { formatAmount } from '../../components/QuantityCell/formatAmount'
import { QuantityStateTrio } from '../../components/QuantityStateTrio/QuantityStateTrio'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { formatDate, todayLocal } from '../../lib/dates'
import { EditItemDialog } from './EditItemDialog'
import { RecordChangeDialog } from './RecordChangeDialog'
import { CHANGED_NOTICE, type ActionNotice } from './useItemActions'
import styles from './ItemDetailsPage.module.css'

type OpenDialog =
  | { kind: 'record'; type: OperationType }
  | { kind: 'edit' }
  | { kind: 'discard' }
  | { kind: 'archive' }
  | null

type Notice = ActionNotice

/** W05 — one inventory item: its three amounts, its full history, and every change you can make to it. */
export function ItemDetailsPage() {
  const { id = '' } = useParams()
  const queryClient = useQueryClient()
  const [dialog, setDialog] = useState<OpenDialog>(null)
  const [notice, setNotice] = useState<Notice | null>(null)

  // All keys start with 'inventory', so one invalidation after a change refreshes this page
  // and the inventory list (W03) together.
  const itemQuery = useQuery({
    queryKey: ['inventory', 'item', id],
    queryFn: ({ signal }) => getInventoryItem(id, signal),
  })
  const operationsQuery = useQuery({
    queryKey: ['inventory', 'item', id, 'operations'],
    queryFn: ({ signal }) => listItemOperations(id, signal),
  })
  const spaces = useQuery({ queryKey: ['storage-spaces'], queryFn: ({ signal }) => listStorageSpaces(signal) })

  function refresh() {
    void queryClient.invalidateQueries({ queryKey: ['inventory'] })
  }

  /** After any successful write: close the dialog, say what happened, reload. */
  function saved(title: string, text?: string) {
    setDialog(null)
    setNotice({ tone: 'info', title, text })
    refresh()
  }

  /** After a 409 VERSION_CONFLICT: close the dialog, explain, and load the latest version. */
  function changedElsewhere() {
    setDialog(null)
    setNotice(CHANGED_NOTICE)
    refresh()
  }

  /** Discard and archive: a version conflict goes to the page banner; other errors stay in the dialog. */
  async function changeState(item: InventoryItem, action: 'discard' | 'archive') {
    try {
      if (action === 'discard') await discardItem(item)
      else await archiveItem(item)
      saved(action === 'discard' ? 'Discarded.' : 'Archived.', 'The item and its history are kept.')
    } catch (error) {
      if (isVersionConflict(error)) {
        changedElsewhere()
        return
      }
      throw error
    }
  }

  const breadcrumbStart = { label: 'Inventory', to: '/inventory' }

  // ---------- Loading and error states for the item itself ----------
  if (itemQuery.isPending) {
    return (
      <>
        <PageHeader title="Item" breadcrumb={[breadcrumbStart]} />
        <p role="status" className={styles.pageState}>
          Loading the item…
        </p>
      </>
    )
  }

  if (itemQuery.isError) {
    const notFound = itemQuery.error instanceof ApiError && itemQuery.error.status === 404
    return (
      <>
        <PageHeader title={notFound ? 'Item not found' : 'Item'} breadcrumb={[breadcrumbStart]} />
        <div role="alert" className={styles.pageState}>
          <p className={styles.stateTitle}>
            {notFound ? 'This item doesn’t exist, or it isn’t in your inventory.' : 'We couldn’t load this item.'}
          </p>
          {!notFound && <p>{itemQuery.error.message}</p>}
          <div className={styles.stateButtons}>
            {!notFound && (
              <Button variant="secondary" size="sm" onClick={() => void itemQuery.refetch()}>
                Try again
              </Button>
            )}
            <ButtonLink to="/inventory" variant="secondary" size="sm">
              Back to inventory
            </ButtonLink>
          </div>
        </div>
      </>
    )
  }

  // ---------- The item ----------
  const item = itemQuery.data
  const icon = foodIconFor(item.item_definition_name)
  // Only IN_STOCK and EMPTY items can still change; DISCARDED and ARCHIVED are history.
  const canChange = item.status === 'IN_STOCK' || item.status === 'EMPTY'
  const inStock = item.status === 'IN_STOCK'
  const operationCount = operationsQuery.data?.length

  return (
    <>
      <PageHeader
        title={item.item_definition_name}
        breadcrumb={[breadcrumbStart, { label: item.storage_space_name }, { label: item.item_definition_name }]}
        leading={
          <span className={styles.iconTile} aria-hidden="true">
            {icon ? (
              <img src={icon} alt="" width={42} height={42} />
            ) : (
              <span className={styles.iconLetter}>{item.item_definition_name.charAt(0).toUpperCase()}</span>
            )}
          </span>
        }
        titleExtras={
          <>
            <StatusPill status={item.status} />
            <ExpiryChip expiryDate={item.expiry_date} today={todayLocal()} showDate={false} />
          </>
        }
        subtitle={`${item.category_name} · batch created ${formatDate(todayLocal(new Date(item.created_at)))}`}
        actions={
          canChange && (
            <>
              <Button variant="secondary" onClick={() => setDialog({ kind: 'edit' })}>
                Edit item
              </Button>
              <Button icon="/assets/icons/assistant/update.png" onClick={() => setDialog({ kind: 'record', type: 'RECONCILE' })}>
                Reconcile count
              </Button>
            </>
          )
        }
      />

      <div className={styles.layout}>
        <div className={styles.mainColumn}>
          {notice && (
            <Banner
              tone={notice.tone}
              title={notice.title}
              role={notice.tone === 'warning' ? 'alert' : 'status'}
              action={
                <Button variant="secondary" size="sm" onClick={() => setNotice(null)}>
                  Dismiss
                </Button>
              }
            >
              {notice.text}
            </Banner>
          )}

          <Card title="Quantity state" aside="three stored amounts, one shown">
            <QuantityStateTrio item={item} />
            {item.is_estimated && (
              <div className={styles.explain}>
                <Banner tone="estimate">
                  Shown as{' '}
                  <strong>
                    ≈ {formatAmount(item.display_amount)} {item.display_unit}
                  </strong>{' '}
                  because an AI estimate exists. Reconciling (counting it) replaces the estimate with a confirmed
                  amount.
                </Banner>
              </div>
            )}
          </Card>

          <Card
            title="Operation history"
            aside={
              operationCount !== undefined && (
                <span className={styles.countPill}>
                  {operationCount} {operationCount === 1 ? 'operation' : 'operations'}
                </span>
              )
            }
          >
            {operationsQuery.isPending && <p role="status">Loading the history…</p>}
            {operationsQuery.isError && (
              <div role="alert" className={styles.inlineError}>
                <p>We couldn’t load the history. {operationsQuery.error.message}</p>
                <Button variant="secondary" size="sm" onClick={() => void operationsQuery.refetch()}>
                  Try again
                </Button>
              </div>
            )}
            {operationsQuery.data && <OperationTimeline operations={operationsQuery.data} item={item} />}
          </Card>
        </div>

        <div className={styles.sideColumn}>
          <Card title="Details">
            <dl className={styles.details}>
              <div>
                <dt>Storage space</dt>
                <dd>{item.storage_space_name}</dd>
              </div>
              <div>
                <dt>Category</dt>
                <dd>{item.category_name}</dd>
              </div>
              <div>
                <dt>Purchase date</dt>
                <dd>{item.purchase_date ? formatDate(item.purchase_date) : '—'}</dd>
              </div>
              <div>
                <dt>Expiry date</dt>
                <dd>{item.expiry_date ? formatDate(item.expiry_date) : '—'}</dd>
              </div>
              <div>
                <dt>Status</dt>
                <dd>
                  <StatusPill status={item.status} />
                </dd>
              </div>
              <div>
                <dt>Notes</dt>
                <dd>{item.notes || '—'}</dd>
              </div>
              <div>
                <dt>Record version</dt>
                <dd>v{item.version}</dd>
              </div>
            </dl>
          </Card>

          {canChange ? (
            <Card title="Record a change">
              <p className={styles.cardText}>Every change to an amount is saved as an operation in the history.</p>
              <div className={styles.actionList}>
                {inStock && (
                  <Button
                    variant="secondary"
                    icon="/assets/icons/assistant/send.png"
                    className={styles.actionButton}
                    onClick={() => setDialog({ kind: 'record', type: 'CONSUME' })}
                  >
                    Record consumption
                  </Button>
                )}
                <Button
                  variant="secondary"
                  icon="/assets/icons/assistant/add.png"
                  className={styles.actionButton}
                  onClick={() => setDialog({ kind: 'record', type: 'ADD' })}
                >
                  Add more stock
                </Button>
                <Button
                  variant="soft"
                  icon="/assets/icons/assistant/update.png"
                  className={styles.actionButton}
                  onClick={() => setDialog({ kind: 'record', type: 'RECONCILE' })}
                >
                  Reconcile to exact count
                </Button>
                <Button
                  variant="secondary"
                  icon="/assets/icons/assistant/report.png"
                  className={styles.actionButton}
                  onClick={() => setDialog({ kind: 'edit' })}
                >
                  Move to another space
                </Button>
              </div>
            </Card>
          ) : (
            <Card title="Read-only">
              <p className={styles.cardText}>
                This item is {item.status === 'DISCARDED' ? 'discarded' : 'archived'}. Its history is kept, but it can’t
                change any more.
              </p>
            </Card>
          )}

          {canChange && (
            <section className={styles.dangerZone} aria-label="Remove this batch">
              <h2 className={styles.dangerTitle}>
                <img src="/assets/icons/assistant/warn.png" alt="" width={18} height={18} />
                Remove this batch
              </h2>
              <p className={styles.cardText}>
                <strong>Archive</strong> when it’s used up or you don’t want to track it.{' '}
                {inStock && (
                  <>
                    <strong>Discard</strong> when it was thrown away.{' '}
                  </>
                )}
                Either way, it stays in the history.
              </p>
              <div className={styles.dangerButtons}>
                <Button variant="secondary" onClick={() => setDialog({ kind: 'archive' })}>
                  Archive
                </Button>
                {inStock && (
                  <Button variant="danger" onClick={() => setDialog({ kind: 'discard' })}>
                    Discard
                  </Button>
                )}
              </div>
            </section>
          )}
        </div>
      </div>

      <RecordChangeDialog
        item={item}
        open={dialog?.kind === 'record'}
        initialType={dialog?.kind === 'record' ? dialog.type : 'CONSUME'}
        onClose={() => setDialog(null)}
        onSaved={(message) => saved(message)}
        onConflict={changedElsewhere}
      />
      <EditItemDialog
        item={item}
        spaces={spaces.data?.items ?? []}
        open={dialog?.kind === 'edit'}
        onClose={() => setDialog(null)}
        onSaved={(message) => saved(message)}
        onConflict={changedElsewhere}
      />
      <ConfirmDialog
        title={`Discard ${item.item_definition_name}?`}
        open={dialog?.kind === 'discard'}
        onClose={() => setDialog(null)}
        confirmLabel="Discard"
        tone="danger"
        onConfirm={() => changeState(item, 'discard')}
      >
        <p>Use this when the food was thrown away. Its status becomes Discarded.</p>
        <p>The item and its whole history stay in the log.</p>
      </ConfirmDialog>
      <ConfirmDialog
        title={`Archive ${item.item_definition_name}?`}
        open={dialog?.kind === 'archive'}
        onClose={() => setDialog(null)}
        confirmLabel="Archive"
        onConfirm={() => changeState(item, 'archive')}
      >
        <p>It leaves the in-stock list. The item and its whole history are kept.</p>
      </ConfirmDialog>
    </>
  )
}
