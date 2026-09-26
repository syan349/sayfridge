import { useEffect, useRef, type ReactNode } from 'react'
import styles from './DataTable.module.css'

export interface Column<Row> {
  key: string
  header: string
  /** Optional fixed width, e.g. "150px". The column without one takes the rest. */
  width?: string
  render: (row: Row) => ReactNode
}

interface Selection {
  selectedIds: Set<string>
  onToggleRow: (id: string) => void
  onToggleAll: () => void
}

interface DataTableProps<Row> {
  /** Describes the table for screen readers (not shown). */
  caption: string
  columns: Column<Row>[]
  rows: Row[]
  getRowId: (row: Row) => string
  /** Name used in each row's checkbox label: "Select Yogurt". */
  getRowLabel: (row: Row) => string
  /** Adds a checkbox column when given. */
  selection?: Selection
  /** Shown in place of the rows: loading, empty or error message. */
  message?: ReactNode
  /** True while new rows are loading over the old ones. */
  busy?: boolean
  /**
   * Clicking anywhere on a row (except its checkbox, links or buttons) calls this.
   * A mouse shortcut only: keyboard users need a real link inside the row too.
   */
  onRowClick?: (row: Row) => void
}

/** A real <table> in the design's style, with an optional checkbox per row. */
export function DataTable<Row>({
  caption,
  columns,
  rows,
  getRowId,
  getRowLabel,
  selection,
  message,
  busy = false,
  onRowClick,
}: DataTableProps<Row>) {
  const columnCount = columns.length + (selection ? 1 : 0)
  const selectedOnPage = selection ? rows.filter((row) => selection.selectedIds.has(getRowId(row))).length : 0
  const allSelected = rows.length > 0 && selectedOnPage === rows.length

  return (
    <div className={styles.frame}>
      <table className={styles.table} aria-busy={busy}>
        <caption className="visually-hidden">{caption}</caption>
        <colgroup>
          {selection && <col style={{ width: '44px' }} />}
          {columns.map((column) => (
            <col key={column.key} style={column.width ? { width: column.width } : undefined} />
          ))}
        </colgroup>
        <thead>
          <tr>
            {selection && (
              <th scope="col" className={styles.checkCell}>
                <SelectAllCheckbox
                  checked={allSelected}
                  indeterminate={selectedOnPage > 0 && !allSelected}
                  disabled={rows.length === 0}
                  onChange={selection.onToggleAll}
                />
              </th>
            )}
            {columns.map((column) => (
              <th key={column.key} scope="col" className={styles.th}>
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {message ? (
            <tr>
              <td colSpan={columnCount} className={styles.message}>
                {message}
              </td>
            </tr>
          ) : (
            rows.map((row) => {
              const id = getRowId(row)
              const selected = selection?.selectedIds.has(id) ?? false
              return (
                <tr
                  key={id}
                  className={[selected ? styles.selectedRow : '', onRowClick ? styles.clickable : ''].filter(Boolean).join(' ') || undefined}
                  onClick={
                    onRowClick &&
                    ((event) => {
                      // Clicks on the checkbox, a link or a button do their own job.
                      if ((event.target as HTMLElement).closest('a, button, input, select, label')) return
                      onRowClick(row)
                    })
                  }
                >
                  {selection && (
                    <td className={styles.checkCell}>
                      <input
                        type="checkbox"
                        className={styles.checkbox}
                        aria-label={`Select ${getRowLabel(row)}`}
                        checked={selected}
                        onChange={() => selection.onToggleRow(id)}
                      />
                    </td>
                  )}
                  {columns.map((column) => (
                    <td key={column.key} className={styles.td}>
                      {column.render(row)}
                    </td>
                  ))}
                </tr>
              )
            })
          )}
        </tbody>
      </table>
    </div>
  )
}

interface SelectAllCheckboxProps {
  checked: boolean
  indeterminate: boolean
  disabled: boolean
  onChange: () => void
}

/** "Select all" can be half-ticked (some rows selected). That state only exists in JavaScript, not HTML. */
function SelectAllCheckbox({ checked, indeterminate, disabled, onChange }: SelectAllCheckboxProps) {
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => {
    if (ref.current) ref.current.indeterminate = indeterminate
  }, [indeterminate])

  return (
    <input
      ref={ref}
      type="checkbox"
      className={styles.checkbox}
      aria-label="Select all items on this page"
      checked={checked}
      disabled={disabled}
      onChange={onChange}
    />
  )
}
