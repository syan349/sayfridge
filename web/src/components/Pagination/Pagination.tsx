import { Button } from '../Button/Button'
import styles from './Pagination.module.css'

interface PaginationProps {
  page: number
  pageSize: number
  total: number
  /** "items", "accounts", … */
  noun: string
  onPageChange: (page: number) => void
}

/** "Showing 21–40 of 57 items" with Previous / Next under a table. */
export function Pagination({ page, pageSize, total, noun, onPageChange }: PaginationProps) {
  const first = (page - 1) * pageSize + 1
  const last = Math.min(page * pageSize, total)

  return (
    <nav aria-label="Pages" className={styles.pagination}>
      <span className={styles.showing}>
        Showing {first}–{last} of {total} {noun}
      </span>
      <Button variant="secondary" size="sm" disabled={page === 1} onClick={() => onPageChange(page - 1)}>
        Previous
      </Button>
      <Button variant="secondary" size="sm" disabled={last >= total} onClick={() => onPageChange(page + 1)}>
        Next
      </Button>
    </nav>
  )
}
