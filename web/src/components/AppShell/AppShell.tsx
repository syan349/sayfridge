import { useQuery } from '@tanstack/react-query'
import { useEffect } from 'react'
import { Outlet } from 'react-router-dom'
import { IN_STOCK_COUNT, attentionQuery, inventoryCountQuery, storageSpacesQuery } from '../../api/queries'
import { useAuth } from '../../auth/AuthContext'
import { todayLocal } from '../../lib/dates'
import { reminderText, showDailyReminder } from '../../lib/reminders'
import { useReminders } from '../../lib/useReminders'
import { AccountCard } from '../AccountCard/AccountCard'
import { Sidebar } from '../Sidebar/Sidebar'
import styles from './AppShell.module.css'

/**
 * Layout for every signed-in page: fixed sidebar on the left, the page on the
 * right. Only the page column scrolls. Pages render their own <PageHeader>.
 */
export function AppShell() {
  const { user, logout } = useAuth()
  const { reminders } = useReminders()
  const isAdmin = user?.role === 'ADMIN'
  const today = todayLocal()

  // The numbers in the menu. Same query keys as the dashboard and W03, so no extra requests
  // there — and every change to an item (which invalidates 'inventory') updates them.
  const inStock = useQuery(inventoryCountQuery(IN_STOCK_COUNT))
  const attention = useQuery(attentionQuery(today, reminders.daysBefore))
  const spaces = useQuery(storageSpacesQuery)
  const expiryCounts = attention.data?.counts

  // The daily reminder: one browser notification a day at most, and only if the user
  // turned it on in Profile & settings (showDailyReminder checks the rest).
  const userId = user?.id
  useEffect(() => {
    if (!userId || !reminders.notify || !expiryCounts) return
    const text = reminderText(expiryCounts, reminders.daysBefore)
    if (text) showDailyReminder(userId, today, text)
  }, [userId, reminders.notify, reminders.daysBefore, expiryCounts, today])

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
        // Log out forgets the session in this browser and asks the backend to end it.
        // Once signed out, RequireAuth sends the user to /login.
        footer={user && <AccountCard email={user.email} isAdmin={isAdmin} onLogout={logout} />}
      />
      <main id="main" tabIndex={-1} className={styles.main}>
        <Outlet />
      </main>
    </div>
  )
}
