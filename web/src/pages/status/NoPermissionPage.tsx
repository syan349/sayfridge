import { ButtonLink } from '../../components/Button/ButtonLink'
import { EmptyState } from '../../components/EmptyState/EmptyState'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import styles from './statusPages.module.css'

/**
 * Shown instead of an admin page to someone who isn't an administrator.
 * Only a courtesy: the backend refuses their requests (403) anyway.
 */
export function NoPermissionPage() {
  return (
    <>
      <PageHeader title="No permission" />
      <div className={styles.body}>
        <div className={styles.card}>
          <EmptyState
            icon="/assets/icons/assistant/warn.png"
            title="You don’t have permission to see this page."
            action={<ButtonLink to="/">Go to the dashboard</ButtonLink>}
          >
            <p>Only administrators can open it. If you need access, ask an administrator.</p>
          </EmptyState>
        </div>
      </div>
    </>
  )
}
