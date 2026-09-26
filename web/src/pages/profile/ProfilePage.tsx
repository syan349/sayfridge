import { useQuery, type UseQueryResult } from '@tanstack/react-query'
import { listRecentOperations } from '../../api/inventory'
import { IN_STOCK_COUNT, inventoryCountQuery, storageSpacesQuery } from '../../api/queries'
import { useAuth } from '../../auth/AuthContext'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { Card } from '../../components/Card/Card'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { formatDate, todayLocal } from '../../lib/dates'
import styles from './ProfilePage.module.css'

/**
 * W10 — Profile and settings. The account comes from GET /auth/me (already loaded
 * when you signed in). Everything is read-only: the backend has no endpoint to
 * change the email or password yet.
 */
export function ProfilePage() {
  const { user, logout } = useAuth()

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
