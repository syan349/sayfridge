import { useQuery, type UseQueryResult } from '@tanstack/react-query'
import { useId, useState } from 'react'
import { listRecentOperations } from '../../api/inventory'
import { IN_STOCK_COUNT, inventoryCountQuery, storageSpacesQuery } from '../../api/queries'
import { useAuth } from '../../auth/AuthContext'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { Card } from '../../components/Card/Card'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { formatDate, todayLocal } from '../../lib/dates'
import { DAYS_BEFORE_OPTIONS, notificationsSupported } from '../../lib/reminders'
import { useReminders } from '../../lib/useReminders'
import styles from './ProfilePage.module.css'

/**
 * W10 — Profile and settings. The account comes from GET /auth/me (already loaded
 * when you signed in) and is read-only: the backend has no endpoint to change the
 * email or password. Reminder preferences are kept in this browser (lib/reminders.ts).
 */
export function ProfilePage() {
  const { user, logout } = useAuth()
  const { reminders, saveReminders } = useReminders()
  const [savedNote, setSavedNote] = useState('')
  const daysId = useId()

  /** Turning notifications on needs the browser's permission; turning them off doesn't. */
  async function changeNotify(wanted: boolean) {
    if (!wanted) {
      saveReminders({ notify: false })
      return setSavedNote('Saved. Notifications are off.')
    }
    const permission = Notification.permission === 'granted' ? 'granted' : await Notification.requestPermission()
    if (permission !== 'granted') {
      return setSavedNote('Notifications are blocked for this site. Allow them in your browser’s site settings, then try again.')
    }
    saveReminders({ notify: true })
    setSavedNote('Saved. You’ll get one notification a day while SayFridge is open.')
  }

  // "Your data": the same count queries as the sidebar and dashboard, so no extra requests.
  const spaces = useQuery({ ...storageSpacesQuery, select: (page) => page.total })
  const inStock = useQuery(inventoryCountQuery(IN_STOCK_COUNT))
  const operations = useQuery({
    queryKey: ['inventory', 'operations', 'count'],
    queryFn: ({ signal }) => listRecentOperations(1, signal).then((page) => page.total),
  })

  if (!user) return null // RequireAuth only shows this page to a signed-in user
  const memberSince = formatDate(todayLocal(new Date(user.created_at)))
  const roleName = user.role === 'ADMIN' ? 'Administrator' : 'Household user'

  return (
    <>
      <PageHeader title="Profile and settings" subtitle={`${user.email} · ${roleName}`} />

      <div className={styles.page}>
        <div className={styles.column}>
          <Card title="Personal information">
            <div className={styles.person}>
              <img src="/assets/avatars/default_avatar.png" alt="" width={72} height={72} className={styles.avatar} />
              <dl className={styles.details}>
                <div>
                  <dt>Email</dt>
                  <dd>{user.email}</dd>
                </div>
                <div>
                  <dt>Role</dt>
                  <dd>
                    <StatusPill status={user.role} /> <span className={styles.muted}>set by an administrator</span>
                  </dd>
                </div>
                <div>
                  <dt>Account status</dt>
                  <dd>
                    <StatusPill status={user.status} />
                  </dd>
                </div>
                <div>
                  <dt>Member since</dt>
                  <dd>{memberSince}</dd>
                </div>
              </dl>
            </div>
            <Banner tone="info" title="Read-only for now">
              Your email and password can’t be changed here yet: the server has no way to update them.
            </Banner>
          </Card>

          <Card title="Reminders">
            <div className={styles.setting}>
              <label htmlFor={daysId}>Count an item as “expiring soon” when it expires within</label>
              <select
                id={daysId}
                className={styles.select}
                value={reminders.daysBefore}
                onChange={(event) => {
                  saveReminders({ daysBefore: Number(event.target.value) })
                  setSavedNote('Saved. The sidebar, dashboard and expiry overview now use it.')
                }}
              >
                {DAYS_BEFORE_OPTIONS.map((days) => (
                  <option key={days} value={days}>
                    {days === 1 ? '1 day' : `${days} days`}
                  </option>
                ))}
              </select>
            </div>
            <label className={styles.check}>
              <input
                type="checkbox"
                checked={reminders.notify}
                disabled={!notificationsSupported()}
                onChange={(event) => void changeNotify(event.target.checked)}
              />
              Show a browser notification once a day when items need attention
            </label>
            {/* Announced by screen readers when it changes. */}
            <p role="status" className={styles.settingNote}>
              {savedNote}
            </p>
            <p className={styles.muted}>
              {notificationsSupported()
                ? 'Reminders are kept in this browser and only appear while SayFridge is open. The phone app has its own reminder settings.'
                : 'This browser can’t show notifications. The phone app has its own reminder settings.'}
            </p>
          </Card>

          <Card title="Voice input">
            <p className={styles.text}>
              Voice input is part of the phone app. Speech is turned into text on the phone before it is sent, so
              there is no voice quota to track on your account.
            </p>
          </Card>

          <Card title="Sign out">
            <p className={styles.text}>
              Signing out forgets your sign-in in this browser. You’ll need your email and password to come back.
            </p>
            <Button variant="secondary" onClick={logout}>
              Log out
            </Button>
          </Card>
        </div>

        <Card title="Your data" className={styles.dataCard}>
          <dl className={styles.stats}>
            <div>
              <dt>Storage spaces</dt>
              <dd>
                <Count query={spaces} />
              </dd>
            </div>
            <div>
              <dt>Items in stock</dt>
              <dd>
                <Count query={inStock} />
              </dd>
            </div>
            <div>
              <dt>Operations recorded</dt>
              <dd>
                <Count query={operations} />
              </dd>
            </div>
            <div>
              <dt>Member since</dt>
              <dd className={styles.date}>{memberSince}</dd>
            </div>
          </dl>
        </Card>
      </div>
    </>
  )
}

/** A number that is still loading ("…") or couldn't be loaded ("—"). */
function Count({ query }: { query: UseQueryResult<number> }) {
  if (query.isPending) return <SpokenSymbol text="…" spoken="loading" />
  if (query.isError) return <SpokenSymbol text="—" spoken="couldn’t load" />
  return <>{query.data}</>
}

/** Shows a symbol, but screen readers hear words instead. */
function SpokenSymbol({ text, spoken }: { text: string; spoken: string }) {
  return (
    <>
      <span aria-hidden="true">{text}</span>
      <span className="visually-hidden">{spoken}</span>
    </>
  )
}
