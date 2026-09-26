import { Button } from '../Button/Button'
import styles from './AccountCard.module.css'

interface AccountCardProps {
  email: string
  isAdmin: boolean
  onLogout: () => void
}

/**
 * Bottom of the sidebar: who is signed in, and Log out.
 * The backend stores no display name or avatar (team decision, 26 Sep), so the
 * name is the part of the email before "@" and everyone gets the default avatar.
 */
export function AccountCard({ email, isAdmin, onLogout }: AccountCardProps) {
  const name = email.split('@')[0]

  return (
    <div className={styles.card}>
      <div className={styles.who}>
        <img src="/assets/avatars/default_avatar.png" alt="" width={34} height={34} className={styles.avatar} />
        <div className={styles.text}>
          <span className={styles.name}>
            {name}
            {isAdmin && <span className={styles.role}>Admin</span>}
          </span>
          {/* Long addresses are cut off with "…"; the title shows the whole address on hover. */}
          <span className={styles.email} title={email}>
            {email}
          </span>
        </div>
      </div>
      <Button variant="secondary" size="sm" className={styles.logout} onClick={onLogout}>
        Log out
      </Button>
    </div>
  )
}
