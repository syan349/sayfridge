/** Room kept for each column without a fixed width (the item or account name). */
const FLEXIBLE_COLUMN_MIN = 200
const CHECKBOX_COLUMN = 44

/**
 * The narrowest a DataTable may get: every fixed width, plus room for the flexible
 * columns. Below this its frame scrolls sideways instead of squashing the name
 * column to nothing (which made the headers overlap on narrow windows).
 */
export function tableMinWidth(columns: { width?: string }[], hasCheckboxes: boolean): number {
  return columns.reduce(
    (total, column) => total + (column.width ? Number.parseFloat(column.width) || 0 : FLEXIBLE_COLUMN_MIN),
    hasCheckboxes ? CHECKBOX_COLUMN : 0,
  )
}
