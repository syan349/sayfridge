import { keepPreviousData, useQueries, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, type ReactNode } from 'react'
import { listUsers, setUserStatus, type AdminUser, type UserQuery } from '../../api/admin'
import { ApiError } from '../../api/client'
import type { UserStatus } from '../../api/types'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { ChipButton } from '../../components/ChipButton/ChipButton'
import { ChipSelect } from '../../components/ChipButton/ChipSelect'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { ConfirmDialog } from '../../components/Dialog/ConfirmDialog'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { Pagination } from '../../components/Pagination/Pagination'
import { SearchField } from '../../components/SearchField/SearchField'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { formatDate, todayLocal } from '../../lib/dates'
import { useDebouncedValue } from '../../lib/useDebouncedValue'
import styles from './AccountsPage.module.css'

const PAGE_SIZE = 20
const STATUS_CHIPS: { status: UserStatus | 'ALL'; label: string }[] = [
  { status: 'ALL', label: 'All' },
  { status: 'ACTIVE', label: 'Active' },
  { status: 'SUSPENDED', label: 'Suspended' },
  { status: 'DISABLED', label: 'Disabled' },
]

/** What each status change means, in the words the confirmation shows. */
const CHANGES: Record<UserStatus, { button: string; verb: string; explain: string }> = {
  SUSPENDED: {
    button: 'Suspend',
    verb: 'Suspended',
    explain: 'They can’t sign in or use the app until an administrator reactivates the account. Nothing is deleted.',
  },
  DISABLED: {
    button: 'Disable',
    verb: 'Disabled',
    explain: 'The account is switched off and can’t sign in. Nothing is deleted, and it can be reactivated later.',
  },
  ACTIVE: { button: 'Reactivate', verb: 'Reactivated', explain: 'They can sign in and use the app again straight away.' },
}

/** How many accounts match, keeping the other filters: page size 1, read `total`. */
function countQuery(query: UserQuery) {
  return {
    queryKey: ['admin', 'users', 'count', query],
    queryFn: ({ signal }: { signal: AbortSignal }) => listUsers(query, signal).then((page) => page.total),
  }
}

/** W11 — Accounts (administrators only): find accounts and suspend, disable or reactivate them. */
export function AccountsPage() {
  const queryClient = useQueryClient()
  const [searchText, setSearchText] = useState('')
  const search = useDebouncedValue(searchText)
  const [role, setRole] = useState<UserQuery['role']>('ALL')
  const [status, setStatus] = useState<UserQuery['status']>('ALL')
  const [page, setPage] = useState(1)
  const [pending, setPending] = useState<{ user: AdminUser; to: UserStatus } | null>(null)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [notice, setNotice] = useState<string | null>(null)

  const query: UserQuery = { q: search.trim(), role, status, page, pageSize: PAGE_SIZE }
  const users = useQuery({
    queryKey: ['admin', 'users', 'list', query],
    queryFn: ({ signal }) => listUsers(query, signal),
    placeholderData: keepPreviousData,
  })
  // Chip counts (same search and role), plus totals for the subtitle.
  const counts = useQueries({
    queries: [
      ...STATUS_CHIPS.map((chip) => countQuery({ ...query, status: chip.status, page: 1, pageSize: 1 })),
      countQuery({ q: '', role: 'ADMIN', status: 'ALL', page: 1, pageSize: 1 }),
    ],
  })
  const [allCount, , suspendedCount] = counts.slice(0, 3).map((result) => result.data)
  const adminCount = counts[STATUS_CHIPS.length]?.data

  function askToChange(user: AdminUser, to: UserStatus) {
    setPending({ user, to })
    setDialogOpen(true)
  }

  async function confirmChange() {
    if (!pending) return
    await setUserStatus(pending.user, pending.to) // errors are shown inside the dialog
    setDialogOpen(false)
    setNotice(`${CHANGES[pending.to].verb} ${pending.user.email}.`)
    void queryClient.invalidateQueries({ queryKey: ['admin', 'users'] })
  }

  const columns: Column<AdminUser>[] = [
    {
      key: 'user',
      header: 'Account',
      render: (user) => (
        <div className={styles.user}>
          <img src="/assets/avatars/default_avatar.png" alt="" width={34} height={34} className={styles.avatar} />
          <div className={styles.userText}>
            <span className={styles.userName}>{user.email.split('@')[0]}</span>
            <span className={styles.userEmail}>{user.email}</span>
          </div>
        </div>
      ),
    },
    { key: 'role', header: 'Role', width: '100px', render: (user) => <StatusPill status={user.role} /> },
    { key: 'status', header: 'Status', width: '120px', render: (user) => <StatusPill status={user.status} /> },
    {
      key: 'joined',
      header: 'Joined',
      width: '130px',
      render: (user) => formatDate(todayLocal(new Date(user.created_at))),
    },
    {
      key: 'actions',
      header: 'Actions',
      width: '220px',
      render: (user) => {
        // The backend refuses changes to administrators (including yourself).
        if (user.role === 'ADMIN') return <span className={styles.muted}>Admins can’t be changed here</span>
        const options: { to: UserStatus; variant: 'primary' | 'secondary' | 'danger' }[] =
          user.status === 'ACTIVE'
            ? [
                { to: 'SUSPENDED', variant: 'secondary' },
                { to: 'DISABLED', variant: 'danger' },
              ]
            : user.status === 'SUSPENDED'
              ? [
                  { to: 'ACTIVE', variant: 'primary' },
                  { to: 'DISABLED', variant: 'danger' },
                ]
              : [{ to: 'ACTIVE', variant: 'primary' }]
        return (
          <div className={styles.actions}>
            {options.map((option) => (
              <Button
                key={option.to}
                size="sm"
                variant={option.variant}
                aria-label={`${CHANGES[option.to].button} ${user.email}`}
                onClick={() => askToChange(user, option.to)}
              >
                {CHANGES[option.to].button}
              </Button>
            ))}
          </div>
        )
      },
    },
  ]

  // 403: this account isn't (or is no longer) an administrator, whatever the sidebar thought.
  const forbidden = users.error instanceof ApiError && users.error.status === 403
  if (forbidden) {
    return (
      <>
        <PageHeader title="Accounts" />
        <div className={styles.noPermission} role="alert">
          <img src="/assets/icons/assistant/warn.png" alt="" width={32} height={32} />
          <h2 className={styles.stateTitle}>You don’t have permission to manage accounts</h2>
          <p>Only administrators can see this page. If you think you should be one, ask the team.</p>
          <ButtonLink to="/" variant="secondary" size="sm">
            Back to the dashboard
          </ButtonLink>
        </div>
      </>
    )
  }

  const rows = users.data?.items ?? []
  const total = users.data?.total ?? 0
  let message: ReactNode = null
  if (users.isPending) message = <p role="status">Loading accounts…</p>
  else if (users.isError) {
    message = (
      <div role="alert" className={styles.stateBox}>
        <p className={styles.stateTitle}>We couldn’t load the accounts.</p>
        <p>{users.error.message}</p>
        <Button variant="secondary" size="sm" onClick={() => void users.refetch()}>
          Try again
        </Button>
      </div>
    )
  } else if (total === 0) message = <p className={styles.stateTitle}>No accounts match.</p>

  const subtitle =
    allCount !== undefined && adminCount !== undefined && suspendedCount !== undefined
      ? `${allCount} ${allCount === 1 ? 'account' : 'accounts'} · ${adminCount} ${adminCount === 1 ? 'administrator' : 'administrators'} · ${suspendedCount} suspended`
      : undefined

  return (
    <>
      <PageHeader
        title="Accounts"
        subtitle={subtitle}
        actions={
          <SearchField
            label="Search accounts"
            placeholder="Search by email…"
            value={searchText}
            onChange={(event) => {
              setSearchText(event.target.value)
              setPage(1)
            }}
          />
        }
      />

      <div className={styles.filterBar}>
        <div role="group" aria-label="Account status" className={styles.chips}>
          {STATUS_CHIPS.map((chip, index) => {
            const count = counts[index]?.data
            return (
              <ChipButton
                key={chip.status}
                selected={status === chip.status}
                onClick={() => {
                  setStatus(chip.status)
                  setPage(1)
                }}
              >
                {count === undefined ? chip.label : `${chip.label} · ${count}`}
              </ChipButton>
            )
          })}
        </div>
        <ChipSelect
          label="Role"
          value={role}
          onChange={(event) => {
            setRole(event.target.value as UserQuery['role'])
            setPage(1)
          }}
          options={[
            { value: 'ALL', label: 'All roles' },
            { value: 'USER', label: 'Users' },
            { value: 'ADMIN', label: 'Administrators' },
          ]}
        />
      </div>

      <div className={styles.content}>
        {notice && (
          <div className={styles.notice}>
            <Banner
              tone="info"
              title={notice}
              role="status"
              action={
                <Button variant="secondary" size="sm" onClick={() => setNotice(null)}>
                  Dismiss
                </Button>
              }
            />
          </div>
        )}

        <DataTable
          caption="Accounts"
          columns={columns}
          rows={rows}
          getRowId={(user) => user.id}
          getRowLabel={(user) => user.email}
          message={message}
          busy={users.isFetching && !users.isPending}
        />

        {total > 0 && rows.length > 0 && (
          <Pagination page={page} pageSize={PAGE_SIZE} total={total} noun="accounts" onPageChange={setPage} />
        )}
      </div>

      {pending && (
        <ConfirmDialog
          title={`${CHANGES[pending.to].button} ${pending.user.email}?`}
          open={dialogOpen}
          onClose={() => setDialogOpen(false)}
          confirmLabel={CHANGES[pending.to].button}
          tone={pending.to === 'ACTIVE' ? 'primary' : 'danger'}
          onConfirm={confirmChange}
        >
          <p>{CHANGES[pending.to].explain}</p>
        </ConfirmDialog>
      )}
    </>
  )
}
