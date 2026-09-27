import { useQuery } from '@tanstack/react-query'
import { Outlet } from 'react-router-dom'
import { IN_STOCK_COUNT, attentionQuery, inventoryCountQuery, storageSpacesQuery } from '../../api/queries'
import { useAuth } from '../../auth/AuthContext'
import { todayLocal } from '../../lib/dates'
import { AccountCard } from '../AccountCard/AccountCard'
import { Sidebar } from '../Sidebar/Sidebar'
import styles from './AppShell.module.css'

/**
 * Layout for every signed-in page: fixed sidebar on the left, the page on the
 * right. Only the page column scrolls. Pages render their own <PageHeader>.
 */
export function AppShell() {
  const { user, logout } = useAuth()
  const isAdmin = user?.role === 'ADMIN'

  // The numbers in the menu. Same query keys as the dashboard and W03, so no extra requests
  // there — and every change to an item (which invalidates 'inventory') updates them.
  const inStock = useQuery(inventoryCountQuery(IN_STOCK_COUNT))
  const attention = useQuery(attentionQuery(todayLocal()))
  const spaces = useQuery(storageSpacesQuery)
  const expiryCounts = attention.data?.counts

  return (
    <div className={styles.shell}>
      <a href="#main" className={styles.skipLink}>
        Skip to main content
      </a>
      <Sidebar
        isAdmin={isAdmin}
        counts={{
          inventory: inStock.data,
          expiry: expiryCounts ? expiryCounts.overdue + expiryCounts.today + expiryCounts.upcoming : undefined,
          spaces: spaces.data?.total,
        }}
        // Log out only forgets the token here; the backend has no logout endpoint.
        // Once signed out, RequireAuth sends the user to /login.
        footer={user && <AccountCard email={user.email} isAdmin={isAdmin} onLogout={logout} />}
      />
      <main id="main" tabIndex={-1} className={styles.main}>
        <Outlet />
      </main>
    </div>
  )
}
