import { useId, type ReactNode } from 'react'
import { NavLink } from 'react-router-dom'
import styles from './Sidebar.module.css'

export type NavKey =
  | 'dashboard'
  | 'inventory'
  | 'expiry'
  | 'spaces'
  | 'assistant'
  | 'conversations'
  | 'settings'
  | 'accounts'

interface NavItem {
  key: NavKey
  to: string
  label: string
  icon: string
  /** Active only on this exact path (the dashboard at "/" would otherwise match every page). */
  end?: boolean
}

const icon = (name: string) => `/assets/icons/assistant/${name}.png`

const HOUSEHOLD: NavItem[] = [
  { key: 'dashboard', to: '/', label: 'Dashboard', icon: icon('home'), end: true },
  { key: 'inventory', to: '/inventory', label: 'Inventory', icon: icon('report') },
  { key: 'expiry', to: '/expiry', label: 'Expiry overview', icon: icon('warn') },
  { key: 'spaces', to: '/spaces', label: 'Storage spaces', icon: icon('update') },
  { key: 'assistant', to: '/assistant', label: 'AI assistant', icon: icon('ai_assistant') },
  { key: 'conversations', to: '/conversations', label: 'Conversation log', icon: icon('history') },
  { key: 'settings', to: '/settings', label: 'Profile & settings', icon: icon('profile') },
]

// Task ledger (W12) and Operation audit (W13) are left out for now (team decision, 26 Sep).
const ADMINISTRATION: NavItem[] = [
  { key: 'accounts', to: '/admin/accounts', label: 'Accounts', icon: icon('profile') },
]

export interface SidebarProps {
  /** Shows the Administration section. */
  isAdmin: boolean
  /** Optional number shown at the right of an item, e.g. { inventory: 16 }. */
  counts?: Partial<Record<NavKey, number>>
  /** Optional card pinned to the bottom (the signed-in account and Log out). */
  footer?: ReactNode
}

export function Sidebar({ isAdmin, counts = {}, footer }: SidebarProps) {
  return (
    <nav aria-label="Main" className={styles.sidebar}>
      <div className={styles.brand}>
        <img src={icon('ai_assistant')} alt="" width={38} height={38} className={styles.brandMark} />
        <span className={styles.brandName}>SayFridge</span>
      </div>

      <NavSection title="Household" items={HOUSEHOLD} counts={counts} />
      {isAdmin && <NavSection title="Administration" items={ADMINISTRATION} counts={counts} />}

      {footer && <div className={styles.footer}>{footer}</div>}
    </nav>
  )
}

interface NavSectionProps {
  title: string
  items: NavItem[]
  counts: Partial<Record<NavKey, number>>
}

function NavSection({ title, items, counts }: NavSectionProps) {
  const titleId = useId()
  return (
    <div className={styles.section}>
      <span id={titleId} className={styles.sectionTitle}>
        {title}
      </span>
      {/* Named list, so screen readers announce "Household, list, 7 items". */}
      <ul aria-labelledby={titleId} className={styles.list}>
        {items.map((item) => (
          <li key={item.key}>
            <NavLink
              to={item.to}
              end={item.end}
              className={({ isActive }) => (isActive ? `${styles.link} ${styles.active}` : styles.link)}
            >
              <img src={item.icon} alt="" width={21} height={21} className={styles.icon} />
              <span className={styles.label}>{item.label}</span>
              {counts[item.key] !== undefined && <span className={styles.count}>{counts[item.key]}</span>}
            </NavLink>
          </li>
        ))}
      </ul>
    </div>
  )
}
