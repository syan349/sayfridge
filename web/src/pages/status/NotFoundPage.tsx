import { useLocation } from 'react-router-dom'
import { ButtonLink } from '../../components/Button/ButtonLink'
import { EmptyState } from '../../components/EmptyState/EmptyState'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import styles from './statusPages.module.css'

/** Any address that isn't a page (inside the app, so the menu is still there). */
export function NotFoundPage() {
  const { pathname } = useLocation()
  return (
    <>
      <PageHeader title="Page not found" />
      <div className={styles.body}>
        <div className={styles.card}>
          <EmptyState
            icon="/assets/icons/assistant/report.png"
            title="There’s no page at this address."
            action={<ButtonLink to="/">Go to the dashboard</ButtonLink>}
          >
            <p>
              <span className={styles.path}>{pathname}</span> doesn’t exist. Check the address, or use the menu on the
              left.
            </p>
          </EmptyState>
        </div>
      </div>
    </>
  )
}
