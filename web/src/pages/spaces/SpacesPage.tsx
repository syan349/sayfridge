import { useQueries, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, type FormEvent, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { ApiError } from '../../api/client'
import { IN_STOCK_COUNT, expirySummaryQuery, inventoryCountQuery } from '../../api/queries'
import {
  archiveStorageSpace,
  createStorageSpace,
  listAllStorageSpaces,
  restoreStorageSpace,
  setDefaultStorageSpace,
  updateStorageSpace,
  type SpaceType,
  type StorageSpace,
} from '../../api/storageSpaces'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { Card } from '../../components/Card/Card'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { ConfirmDialog } from '../../components/Dialog/ConfirmDialog'
import { Dialog } from '../../components/Dialog/Dialog'
import dialogStyles from '../../components/Dialog/Dialog.module.css'
import { FormError } from '../../components/FormError/FormError'
import { IconButton } from '../../components/IconButton/IconButton'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { SpaceIcon } from '../../components/SpaceIcon/SpaceIcon'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { TextField } from '../../components/TextField/TextField'
import { formatDate, todayLocal } from '../../lib/dates'
import { useReminders } from '../../lib/useReminders'
import { SpaceTypePicker } from './SpaceTypePicker'
import { spaceTypeLabel } from './spaceTypes'
import styles from './SpacesPage.module.css'

/** The backend's NAME_CONFLICT, in words for this page. */
function spaceError(error: unknown): string {
  if (error instanceof ApiError && error.code === 'NAME_CONFLICT') return 'You already have an active space with this name.'
  return error instanceof ApiError ? error.message : 'Something went wrong. Please try again.'
}

/** W04 — Storage spaces: create, rename, archive and restore the places food is kept. */
export function SpacesPage() {
  const queryClient = useQueryClient()
  const today = todayLocal()
  const { reminders } = useReminders()
  const [editing, setEditing] = useState<StorageSpace | null>(null)
  const [archiving, setArchiving] = useState<StorageSpace | null>(null)
  const [blocked, setBlocked] = useState<{ space: StorageSpace; count: number } | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [rowError, setRowError] = useState<string | null>(null)

  // Active AND archived spaces. The key starts with 'storage-spaces', so changes here
  // also refresh the active list used by the sidebar, W03 and the dashboard.
  const spaces = useQuery({ queryKey: ['storage-spaces', 'all'], queryFn: ({ signal }) => listAllStorageSpaces(signal) })
  const spaceList = spaces.data?.items ?? []
  // How many items each space holds right now (the same queries as the dashboard's bars).
  const counts = useQueries({
    queries: spaceList.map((space) => inventoryCountQuery({ ...IN_STOCK_COUNT, storageSpaceId: space.id })),
  })
  // "Expiring soon" per space: the user's look-ahead (3 days by default), grouped by space in the browser (≤100 items).
  const expiring = useQuery(
    expirySummaryQuery({ asOf: today, daysBefore: reminders.daysBefore, storageSpaceId: null, bucket: null, page: 1, pageSize: 100 }),
  )
  const expiringIn = (spaceId: string) => expiring.data?.items.filter((item) => item.storage_space_id === spaceId).length

  function refresh() {
    void queryClient.invalidateQueries({ queryKey: ['storage-spaces'] })
    void queryClient.invalidateQueries({ queryKey: ['inventory'] })
  }

  function tryToArchive(space: StorageSpace, count: number | undefined) {
    setNotice(null)
    // A space that still holds food can't be archived (the backend would answer 409).
    // Instead of sending a request that must fail, say why and what to do.
    // If the count couldn't be loaded, let the user try: the backend still refuses a
    // space with items, and the confirm dialog shows its message.
    if (count !== undefined && count > 0) {
      setBlocked({ space, count })
      return
    }
    setBlocked(null)
    setArchiving(space)
  }

  async function restore(space: StorageSpace) {
    setRowError(null)
    try {
      await restoreStorageSpace(space.id)
      setNotice(`Restored ${space.name}.`)
      refresh()
    } catch (error) {
      setRowError(`${space.name} couldn’t be restored: ${spaceError(error)}`)
    }
  }

  /** The default space is where new stock goes when none is named, e.g. by the assistant. */
  async function makeDefault(space: StorageSpace) {
    setRowError(null)
    try {
      await setDefaultStorageSpace(space.id)
      setNotice(`${space.name} is now your default space.`)
      refresh()
    } catch (error) {
      setRowError(`${space.name} couldn’t be made the default: ${spaceError(error)}`)
    }
  }

  const columns: Column<StorageSpace>[] = [
    {
      key: 'space',
      header: 'Space',
      render: (space) => (
        <div className={styles.spaceCell}>
          <SpaceIcon type={space.type} />
          <div>
            <span className={styles.spaceName}>
              {space.name}
              {space.is_default && <span className={styles.defaultTag}>Default</span>}
            </span>
            <span className={styles.created}>Created {formatDate(todayLocal(new Date(space.created_at)))}</span>
          </div>
        </div>
      ),
    },
    { key: 'type', header: 'Type', width: '110px', render: (space) => <span className={styles.typeTag}>{spaceTypeLabel(space.type)}</span> },
    {
      key: 'items',
      header: 'Items',
      width: '80px',
      render: (space) => <span className={styles.number}>{counts[spaceList.indexOf(space)]?.data ?? '…'}</span>,
    },
    {
      key: 'expiring',
      header: 'Expiring soon',
      width: '130px',
      render: (space) => {
        const soon = expiringIn(space.id)
        if (soon === undefined) return '…'
        return soon > 0 ? <span className={styles.soonPill}>{soon} {soon === 1 ? 'item' : 'items'}</span> : <span className={styles.nonePill}>None</span>
      },
    },
    { key: 'status', header: 'Status', width: '110px', render: (space) => <StatusPill status={space.status} /> },
    {
      key: 'actions',
      header: 'Actions',
      width: '150px',
      render: (space) => {
        if (space.status === 'ARCHIVED') {
          return (
            <div className={styles.actions}>
              <Button variant="secondary" size="sm" onClick={() => void restore(space)} aria-label={`Restore ${space.name}`}>
                Restore
              </Button>
            </div>
          )
        }
        const count = counts[spaceList.indexOf(space)]?.data
        const full = count !== undefined && count > 0 // known to hold items
        return (
          <div className={styles.actions}>
            {!space.is_default && (
              <IconButton label={`Make ${space.name} the default space`} onClick={() => void makeDefault(space)}>
                <svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true">
                  <path d="m12 3 2.7 5.6 6.1.8-4.5 4.3 1.1 6.1-5.4-3-5.4 3 1.1-6.1L3.2 9.4l6.1-.8Z" />
                </svg>
              </IconButton>
            )}
            <IconButton label={`Rename ${space.name}`} onClick={() => setEditing(space)}>
              <svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true">
                <path d="M4 20h4L19 9l-4-4L4 16Z" />
                <path d="m13.5 6.5 4 4" />
              </svg>
            </IconButton>
            <IconButton
              label={full ? `Archive ${space.name} (not possible while it holds items)` : `Archive ${space.name}`}
              aria-disabled={full}
              onClick={() => tryToArchive(space, count)}
            >
              <svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true">
                <path d="M3 5h18v4H3Z" />
                <path d="M5 9v10h14V9" />
                <path d="M10 13h4" />
              </svg>
            </IconButton>
          </div>
        )
      },
    },
  ]

  let message: ReactNode = null
  if (spaces.isPending) message = <p role="status">Loading your spaces…</p>
  else if (spaces.isError) {
    message = (
      <div role="alert" className={styles.stateBox}>
        <p className={styles.stateTitle}>We couldn’t load your spaces.</p>
        <p>{spaces.error.message}</p>
        <Button variant="secondary" size="sm" onClick={() => void spaces.refetch()}>
          Try again
        </Button>
      </div>
    )
  } else if (spaceList.length === 0) {
    message = (
      <div className={styles.stateBox}>
        <p className={styles.stateTitle}>No storage spaces yet.</p>
        <p>Add your fridge, freezer or pantry with the form on the right.</p>
      </div>
    )
  }

  return (
    <>
      <PageHeader title="Storage spaces" subtitle="Where food is kept. Names must be unique among your active spaces." />

      <div className={styles.layout}>
        <div className={styles.mainColumn}>
          {blocked && (
            <Banner
              tone="warning"
              role="alert"
              action={
                <>
                  <Link to="/inventory" className={styles.bannerLink}>
                    Move items
                  </Link>
                  <Button variant="secondary" size="sm" onClick={() => setBlocked(null)}>
                    Dismiss
                  </Button>
                </>
              }
            >
              {blocked.space.name} still holds {blocked.count} {blocked.count === 1 ? 'item' : 'items'} in stock. Move or
              discard them before archiving the space.
            </Banner>
          )}
          {notice && (
            <Banner
              tone="info"
              role="status"
              title={notice}
              action={
                <Button variant="secondary" size="sm" onClick={() => setNotice(null)}>
                  Dismiss
                </Button>
              }
            />
          )}
          {rowError && <FormError message={rowError} />}

          <DataTable
            caption="Storage spaces"
            columns={columns}
            rows={spaceList}
            getRowId={(space) => space.id}
            getRowLabel={(space) => space.name}
            message={message}
          />
          <p className={styles.footnote}>
            New stock goes to the default space when no space is named, for example when you tell the assistant “I
            bought milk”. Archived spaces keep their history, and can be restored.
          </p>
        </div>

        <CreateSpaceCard
          onCreated={(space) => {
            setNotice(`Added ${space.name}.`)
            refresh()
          }}
        />
      </div>

      {editing && (
        <EditSpaceDialog
          space={editing}
          onClose={() => setEditing(null)}
          onSaved={(space) => {
            setEditing(null)
            setNotice(`Saved ${space.name}.`)
            refresh()
          }}
        />
      )}

      <ConfirmDialog
        title={`Archive ${archiving?.name ?? ''}?`}
        open={archiving !== null}
        onClose={() => setArchiving(null)}
        confirmLabel="Archive"
        onConfirm={async () => {
          if (!archiving) return
          await archiveStorageSpace(archiving.id) // a 409 (items added meanwhile) is shown in the dialog
          setNotice(`Archived ${archiving.name}. It can be restored later.`)
          setArchiving(null)
          refresh()
        }}
      >
        <p>It won’t be offered as a place to put food any more. Its history is kept, and you can restore it later.</p>
      </ConfirmDialog>
    </>
  )
}

/** The "Add a storage space" form on the right. */
function CreateSpaceCard({ onCreated }: { onCreated: (space: StorageSpace) => void }) {
  const [name, setName] = useState('')
  const [type, setType] = useState<SpaceType>('FRIDGE')
  const [error, setError] = useState<string | undefined>()
  const [saving, setSaving] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!name.trim()) {
      setError('Give the space a name, e.g. Kitchen fridge.')
      return
    }
    setSaving(true)
    setError(undefined)
    try {
      const space = await createStorageSpace({ name: name.trim(), type })
      setName('')
      setType('FRIDGE')
      onCreated(space)
    } catch (caught) {
      setError(spaceError(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card title="Add a storage space" className={styles.createCard}>
      <form noValidate onSubmit={handleSubmit} className={styles.createForm}>
        <TextField
          label="Name"
          value={name}
          maxLength={100}
          placeholder="e.g. Garage freezer"
          onChange={(event) => setName(event.target.value)}
          error={error}
        />
        <SpaceTypePicker name="new-space-type" value={type} onChange={setType} />
        <div className={styles.formButtons}>
          <Button type="submit" size="lg" disabled={saving}>
            {saving ? 'Creating…' : 'Create space'}
          </Button>
          <Button
            variant="secondary"
            size="lg"
            onClick={() => {
              setName('')
              setType('FRIDGE')
              setError(undefined)
            }}
          >
            Clear
          </Button>
        </div>
      </form>
    </Card>
  )
}

/** Rename a space and/or change its type (PATCH, only what changed). */
function EditSpaceDialog({ space, onClose, onSaved }: { space: StorageSpace; onClose: () => void; onSaved: (space: StorageSpace) => void }) {
  const [name, setName] = useState(space.name)
  const [type, setType] = useState<SpaceType>(space.type)
  const [error, setError] = useState<string | undefined>()
  const [saving, setSaving] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const changes: { name?: string; type?: SpaceType } = {}
    if (name.trim() !== space.name) changes.name = name.trim()
    if (type !== space.type) changes.type = type
    if (!name.trim()) return setError('The name can’t be empty.')
    if (Object.keys(changes).length === 0) return onClose() // nothing to save
    setSaving(true)
    try {
      onSaved(await updateStorageSpace(space.id, changes))
    } catch (caught) {
      setError(spaceError(caught))
      setSaving(false)
    }
  }

  return (
    <Dialog title={`Edit ${space.name}`} open onClose={onClose}>
      <form noValidate onSubmit={handleSubmit} className={styles.createForm}>
        <TextField label="Name" value={name} maxLength={100} onChange={(event) => setName(event.target.value)} error={error} autoFocus />
        <SpaceTypePicker name="edit-space-type" value={type} onChange={setType} />
        <div className={dialogStyles.buttons}>
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button type="submit" disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </form>
    </Dialog>
  )
}
