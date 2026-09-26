import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useId, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { ApiError } from '../../api/client'
import { batchCreate } from '../../api/inventory'
import type { ItemDefinition } from '../../api/itemDefinitions'
import { storageSpacesQuery } from '../../api/queries'
import type { StorageSpace } from '../../api/storageSpaces'
import { Banner } from '../../components/Banner/Banner'
import { Button } from '../../components/Button/Button'
import { Card } from '../../components/Card/Card'
import { DataTable, type Column } from '../../components/DataTable/DataTable'
import { ConfirmDialog } from '../../components/Dialog/ConfirmDialog'
import { IconButton } from '../../components/IconButton/IconButton'
import { ItemCell } from '../../components/ItemCell/ItemCell'
import { PageHeader } from '../../components/PageHeader/PageHeader'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { TextField } from '../../components/TextField/TextField'
import { formatDate } from '../../lib/dates'
import { DefinitionPicker } from './DefinitionPicker'
import styles from './StockInPage.module.css'

const MAX_ROWS = 100 // what batch-create accepts in one request
// Same rule as the backend: digits, optionally a point and up to three decimals.
const AMOUNT_PATTERN = /^[0-9]+(\.[0-9]{1,3})?$/

/** One line of the batch, before it's saved. */
interface BatchRow {
  key: string
  definition: ItemDefinition
  space: StorageSpace
  amount: string
  unit: string
  purchaseDate: string
  expiryDate: string
}

type FieldErrors = Partial<Record<'definition' | 'amount' | 'unit' | 'space', string>>

let nextKey = 0

/** W06 — Add items by hand: build a list of new items, then save them all with one request. */
export function StockInPage() {
  const queryClient = useQueryClient()
  const spaces = useQuery(storageSpacesQuery)
  const spaceList = spaces.data?.items ?? []
  const spaceFieldId = useId()

  // The "New item" form
  const [definition, setDefinition] = useState<ItemDefinition | null>(null)
  const [amount, setAmount] = useState('')
  const [unit, setUnit] = useState('')
  const [spaceId, setSpaceId] = useState('')
  const [purchaseDate, setPurchaseDate] = useState('')
  const [expiryDate, setExpiryDate] = useState('')
  const [errors, setErrors] = useState<FieldErrors>({})

  // The batch
  const [rows, setRows] = useState<BatchRow[]>([])
  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState<{ rowKey?: string; message: string } | null>(null)
  const [saved, setSaved] = useState<number | null>(null)
  const [confirmDiscard, setConfirmDiscard] = useState(false)

  const space = spaceList.find((option) => option.id === spaceId) ?? spaceList[0]

  function addToBatch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const found: FieldErrors = {}
    if (!definition) found.definition = 'Choose an item from the list, or create your own.'
    if (!amount.trim()) found.amount = 'Enter an amount.'
    else if (!AMOUNT_PATTERN.test(amount.trim())) found.amount = 'Use a number like 2 or 0.25 (up to 3 decimals).'
    else if (Number(amount) === 0) found.amount = 'Enter an amount above zero.'
    if (!unit.trim()) found.unit = 'Enter a unit, e.g. g, kg, L or each.'
    else if (unit.trim().length > 16) found.unit = 'Use at most 16 characters.'
    if (!space) found.space = 'Add a storage space first.'
    setErrors(found)
    if (Object.keys(found).length > 0 || !definition || !space) return

    setRows((current) => [
      ...current,
      { key: `row-${nextKey++}`, definition, space, amount: amount.trim(), unit: unit.trim(), purchaseDate, expiryDate },
    ])
    setSaved(null)
    // Ready for the next item. The space and purchase date usually stay the same for one
    // shopping trip, so they're kept; every item has its own expiry date, so that one is cleared.
    setDefinition(null)
    setAmount('')
    setUnit('')
    setExpiryDate('')
  }

  function removeRow(key: string) {
    setRows((current) => current.filter((row) => row.key !== key))
    if (saveError?.rowKey === key) setSaveError(null)
  }

  async function saveBatch() {
    setSaving(true)
    setSaveError(null)
    try {
      // One request for everything: the backend saves all rows or none of them.
      await batchCreate(
        rows.map((row) => ({
          storage_space_id: row.space.id,
          item_definition_id: row.definition.id,
          amount: row.amount, // decimal TEXT, exactly as typed ("2.5"), never a number
          unit: row.unit,
          purchase_date: row.purchaseDate || undefined,
          expiry_date: row.expiryDate || undefined,
        })),
      )
      setSaved(rows.length)
      setRows([])
      void queryClient.invalidateQueries({ queryKey: ['inventory'] })
    } catch (error) {
      // Nothing was saved. The backend names the first bad row (item_index, counting from 0).
      const index = error instanceof ApiError ? error.itemIndex : undefined
      const reason =
        error instanceof ApiError ? (error.fieldErrors[0]?.msg ?? error.message) : 'Something went wrong. Please try again.'
      const badRow = index !== undefined ? rows[index] : undefined
      setSaveError(
        badRow
          ? { rowKey: badRow.key, message: `Row ${index! + 1} (${badRow.definition.name}): ${reason}` }
          : { message: reason },
      )
    } finally {
      setSaving(false)
    }
  }

  const columns: Column<BatchRow>[] = [
    {
      key: 'item',
      header: 'Item',
      render: (row) => (
        <div>
          <ItemCell name={row.definition.name} />
          {saveError?.rowKey === row.key && (
            <p className={styles.rowError}>This row stopped the save — fix or remove it.</p>
          )}
        </div>
      ),
    },
    {
      key: 'quantity',
      header: 'Quantity',
      width: '130px',
      render: (row) => (
        <span className={styles.mono}>
          {row.amount} {row.unit}
        </span>
      ),
    },
    { key: 'space', header: 'Space', width: '140px', render: (row) => row.space.name },
    { key: 'expires', header: 'Expires', width: '130px', render: (row) => (row.expiryDate ? formatDate(row.expiryDate) : '—') },
    { key: 'definition', header: 'Definition', width: '110px', render: (row) => <StatusPill status={row.definition.scope} /> },
    {
      key: 'remove',
      header: 'Remove',
      width: '80px',
      render: (row) => (
        <div className={styles.removeCell}>
          <IconButton label={`Remove ${row.definition.name} from the batch`} onClick={() => removeRow(row.key)}>
            <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M6 6l12 12M18 6 6 18" />
            </svg>
          </IconButton>
        </div>
      ),
    },
  ]

  const itemsText = rows.length === 1 ? '1 item' : `${rows.length} items`

  return (
    <>
      <PageHeader
        title="Add items by hand"
        breadcrumb={[{ label: 'Inventory', to: '/inventory' }, { label: 'Add items' }]}
        subtitle="Build a batch, then save it in one go — all rows are saved, or none."
        actions={
          <>
            <Button variant="secondary" disabled={rows.length === 0 || saving} onClick={() => setConfirmDiscard(true)}>
              Discard batch
            </Button>
            <Button icon="/assets/icons/assistant/add.png" disabled={rows.length === 0 || saving} onClick={() => void saveBatch()}>
              {saving ? 'Saving…' : rows.length === 0 ? 'Save items' : `Save ${itemsText}`}
            </Button>
          </>
        }
      />

      <div className={styles.page}>
        {saved !== null && (
          <Banner
            tone="info"
            role="status"
            title={`Saved ${saved === 1 ? '1 item' : `${saved} items`}.`}
            action={
              <Link to="/inventory" className={styles.bannerLink}>
                View inventory
              </Link>
            }
          />
        )}

        <Card title="New item">
          <form noValidate onSubmit={addToBatch}>
            <div className={styles.formGrid}>
              <DefinitionPicker value={definition} onChange={setDefinition} error={errors.definition} />
              <TextField
                label="Quantity"
                inputMode="decimal"
                autoComplete="off"
                value={amount}
                onChange={(event) => setAmount(event.target.value)}
                error={errors.amount}
              />
              <TextField
                label="Unit"
                placeholder="g, kg, L…"
                autoComplete="off"
                value={unit}
                onChange={(event) => setUnit(event.target.value)}
                error={errors.unit}
              />
              <div className={styles.selectField}>
                <label htmlFor={spaceFieldId}>Storage space</label>
                <select id={spaceFieldId} value={space?.id ?? ''} onChange={(event) => setSpaceId(event.target.value)}>
                  {spaceList.length === 0 && <option value="">No spaces yet</option>}
                  {spaceList.map((option) => (
                    <option key={option.id} value={option.id}>
                      {option.name}
                    </option>
                  ))}
                </select>
                {errors.space && (
                  <p className={styles.fieldError}>
                    {errors.space} <Link to="/spaces">Add one</Link>
                  </p>
                )}
              </div>
              <TextField label="Purchased" type="date" value={purchaseDate} onChange={(event) => setPurchaseDate(event.target.value)} />
              <TextField label="Expires" type="date" value={expiryDate} onChange={(event) => setExpiryDate(event.target.value)} />
            </div>
            <div className={styles.formFooter}>
              <p className={styles.hint}>Use the date printed on the packet where there is one; leave it empty if there isn’t.</p>
              <Button type="submit" variant="soft" size="lg" disabled={rows.length >= MAX_ROWS}>
                Add to batch
              </Button>
            </div>
            {rows.length >= MAX_ROWS && (
              <p className={styles.hint}>A batch holds at most {MAX_ROWS} items. Save this one first.</p>
            )}
          </form>
        </Card>

        <Card
          title="Batch"
          aside={<span className={styles.readyPill}>{rows.length === 1 ? '1 item ready' : `${rows.length} items ready`}</span>}
        >
          {saveError && (
            <div className={styles.saveError}>
              <Banner tone="danger" role="alert" title="Nothing was saved.">
                {saveError.message}
              </Banner>
            </div>
          )}
          <DataTable
            caption="Items to add"
            columns={columns}
            rows={rows}
            getRowId={(row) => row.key}
            getRowLabel={(row) => row.definition.name}
            isRowInvalid={(row) => saveError?.rowKey === row.key}
            message={rows.length === 0 ? <p>Nothing in the batch yet. Add items with the form above.</p> : null}
          />
          <p className={styles.hint}>
            {rows.length > 0
              ? `Saving creates ${itemsText} in one request. If any row has a problem, nothing is saved and that row is highlighted.`
              : 'Tip: the phone app can fill this in from a photo of your receipt.'}
          </p>
        </Card>
      </div>

      <ConfirmDialog
        title="Discard this batch?"
        open={confirmDiscard}
        onClose={() => setConfirmDiscard(false)}
        confirmLabel="Discard batch"
        tone="danger"
        onConfirm={async () => {
          setRows([])
          setSaveError(null)
          setConfirmDiscard(false)
        }}
      >
        <p>The {itemsText} in the list are removed. Nothing has been saved yet, so nothing changes in your inventory.</p>
      </ConfirmDialog>
    </>
  )
}
