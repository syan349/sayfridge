import { Outlet } from 'react-router-dom'
import { useAuth } from '../../auth/AuthContext'
import { Sidebar } from '../Sidebar/Sidebar'
import styles from './AppShell.module.css'

/**
 * Layout for every signed-in page: fixed sidebar on the left, the page on the
 * right. Only the page column scrolls. Pages render their own <PageHeader>.
 */
export function AppShell() {
  const { user } = useAuth()

  return (
    <div className={styles.shell}>
      <a href="#main" className={styles.skipLink}>
        Skip to main content
      </a>
      <Sidebar isAdmin={user?.role === 'ADMIN'} />
      <main id="main" tabIndex={-1} className={styles.main}>
        <Outlet />
      </main>
    </div>
  )
}
