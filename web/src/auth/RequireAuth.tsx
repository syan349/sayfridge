import { Navigate, Outlet, useLocation } from 'react-router-dom'
import type { UserRole } from '../api/types'
import { Button } from '../components/Button/Button'
import { useAuth } from './AuthContext'
import type { LoginLocationState } from './loginState'
import styles from './RequireAuth.module.css'

interface RequireAuthProps {
  /** Also require this role, e.g. 'ADMIN'. Others are sent to the dashboard. */
  role?: UserRole
}

/**
 * Route guard. Renders the child routes only for a signed-in user; anyone else
 * goes to /login, which sends them back here after signing in.
 * Hiding pages is only for convenience — the backend checks every request.
 */
export function RequireAuth({ role }: RequireAuthProps) {
  const { status, user, error, retry, logout } = useAuth()
  const location = useLocation()

  if (status === 'loading') {
    return (
      <div className={styles.status} role="status">
        Loading your account…
      </div>
    )
  }

  if (status === 'error') {
    return (
      <div className={styles.status} role="alert">
        <p className={styles.title}>We couldn’t load your account</p>
        <p className={styles.message}>{error?.message}</p>
        <div className={styles.actions}>
          <Button onClick={retry}>Try again</Button>
          <Button variant="secondary" onClick={logout}>
            Sign in again
          </Button>
        </div>
      </div>
    )
  }

  if (!user) {
    const state: LoginLocationState = { from: location.pathname + location.search }
    return <Navigate to="/login" replace state={state} />
  }

  if (role && user.role !== role) {
    return <Navigate to="/" replace />
  }

  return <Outlet />
}
