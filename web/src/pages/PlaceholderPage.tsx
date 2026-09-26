import { PageHeader } from '../components/PageHeader/PageHeader'
import styles from './PlaceholderPage.module.css'

interface PlaceholderPageProps {
  title: string
  message: string
}

/** Stand-in for a page that has not been built yet, so every menu link leads somewhere. */
export function PlaceholderPage({ title, message }: PlaceholderPageProps) {
  return (
    <>
      <PageHeader title={title} />
      <div className={styles.body}>
        <p className={styles.card}>{message}</p>
      </div>
    </>
  )
}
