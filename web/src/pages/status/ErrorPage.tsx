import { isRouteErrorResponse, useRouteError } from 'react-router-dom'
import { Button } from '../../components/Button/Button'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { EmptyState } from '../../components/EmptyState/EmptyState'
import styles from './statusPages.module.css'

/**
 * The error boundary. When a page crashes while drawing (a bug, or data in a shape
 * we didn't expect), React Router shows this instead of a blank screen.
 * Used twice in router.tsx: inside the shell (the menu stays usable) and around
 * everything (for a crash in the shell or the sign-in pages).
 */
export function ErrorPage() {
  const error = useRouteError()
  const details = isRouteErrorResponse(error)
    ? `${error.status} ${error.statusText}`
    : error instanceof Error
      ? error.message
      : String(error)

  return (
    <div className={styles.crashPage} role="alert">
      <title>Something went wrong · SayFridge</title>
      <div className={styles.card}>
        <EmptyState
          icon="/assets/icons/assistant/warn.png"
          title="Something went wrong on this page."
          action={
            <>
              <Button onClick={() => window.location.reload()}>Reload the page</Button>
              <ButtonLink to="/" variant="secondary">
                Go to the dashboard
              </ButtonLink>
            </>
          }
        >
          <p>Reloading usually fixes it. If it keeps happening, tell the team what you were doing.</p>
          <details className={styles.details}>
            <summary>Technical details</summary>
            <pre>{details}</pre>
          </details>
        </EmptyState>
      </div>
    </div>
  )
}
