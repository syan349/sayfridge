import { Outlet } from 'react-router-dom'
import { useAuth } from '../../auth/AuthContext'
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

  return (
    <div className={styles.shell}>
      <a href="#main" className={styles.skipLink}>
        Skip to main content
      </a>
      <Sidebar
        isAdmin={isAdmin}
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
