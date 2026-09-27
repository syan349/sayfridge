import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useId, useState } from 'react'
import { ApiError } from '../../api/client'
import { createDefinition, searchDefinitions, type ItemDefinition } from '../../api/itemDefinitions'
import { categoriesQuery } from '../../api/queries'
import { Button } from '../../components/Button/Button'
import { FormError } from '../../components/FormError/FormError'
import { ItemCell } from '../../components/ItemCell/ItemCell'
import { StatusPill } from '../../components/StatusPill/StatusPill'
import { TextField } from '../../components/TextField/TextField'
import { useDebouncedValue } from '../../lib/useDebouncedValue'
import styles from './StockInPage.module.css'

interface DefinitionPickerProps {
  /** The chosen kind of food, or null while searching. */
  value: ItemDefinition | null
  onChange: (definition: ItemDefinition | null) => void
  error?: string
}

/**
 * "Item": type part of a name, pick a match (public, or one of yours), or create
 * your own private item when nothing matches. Matches are plain buttons, which
 * work with a keyboard and screen readers without any extra ARIA.
 */
export function DefinitionPicker({ value, onChange, error }: DefinitionPickerProps) {
  const queryClient = useQueryClient()
  const [text, setText] = useState('')
  const search = useDebouncedValue(text.trim(), 250)
  const [categoryId, setCategoryId] = useState('')
  const [creating, setCreating] = useState(false)
  const [createError, setCreateError] = useState<string | null>(null)
  const categorySelectId = useId()

  const results = useQuery({
    queryKey: ['item-definitions', 'search', search],
    queryFn: ({ signal }) => searchDefinitions(search, signal),
    enabled: value === null && search.length > 0,
  })
  const categories = useQuery(categoriesQuery)
  const categoryList = categories.data?.items ?? []

  function choose(definition: ItemDefinition) {
    setCreateError(null)
    setText('') // so the box starts empty for the next item, once this one is added to the batch
    onChange(definition)
  }

  async function createOwn() {
    setCreating(true)
    setCreateError(null)
    try {
      const created = await createDefinition({ name: search, category_id: categoryId })
      void queryClient.invalidateQueries({ queryKey: ['item-definitions'] })
      choose(created)
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === 'NAME_CONFLICT') {
        setCreateError('You already have an item with this name (maybe archived). Pick it from the list instead.')
      } else {
        setCreateError(caught instanceof ApiError ? caught.message : 'Could not create the item. Please try again.')
      }
    } finally {
      setCreating(false)
    }
  }

  if (value) {
    return (
      <div className={styles.pickerField}>
        <span className={styles.fieldLabel}>Item</span>
        <div className={styles.chosen}>
          <ItemCell name={value.name} />
          <StatusPill status={value.scope} />
          <Button
            variant="secondary"
            size="sm"
            className={styles.change}
            onClick={() => {
              onChange(null)
              setText('')
            }}
          >
            Change
          </Button>
        </div>
      </div>
    )
  }

  const matches = results.data?.items ?? []
  const exactMatch = matches.some((definition) => definition.name.toLowerCase() === search.toLowerCase())

  return (
    <div className={styles.pickerField}>
      <TextField
        label="Item"
        placeholder="Start typing, e.g. milk"
        autoComplete="off"
        value={text}
        onChange={(event) => setText(event.target.value)}
        error={error}
      />

      {search && (
        <div className={styles.matches}>
          <p className={styles.matchesTitle}>Matching items</p>
          {results.isPending && <p className={styles.matchesNote}>Searching…</p>}
          {results.isError && (
            <p role="alert" className={styles.matchesNote}>
              Search failed: {results.error.message}
            </p>
          )}
          {results.data && matches.length === 0 && <p className={styles.matchesNote}>No item called “{search}” yet.</p>}
          {matches.length > 0 && (
            <ul className={styles.matchList}>
              {matches.map((definition) => (
                <li key={definition.id}>
                  <button type="button" className={styles.match} onClick={() => choose(definition)}>
                    <ItemCell name={definition.name} />
                    <StatusPill status={definition.scope} />
                  </button>
                </li>
              ))}
            </ul>
          )}

          {results.data && !exactMatch && (
            <div className={styles.createOwn}>
              <p className={styles.matchesNote}>
                Not in the list? Create “{search}” as <strong>your own</strong> item (only you will see it).
              </p>
              {categories.data && categoryList.length === 0 ? (
                <p className={styles.matchesNote}>No categories exist yet, so new items can’t be created.</p>
              ) : (
                <div className={styles.createRow}>
                  <label htmlFor={categorySelectId} className="visually-hidden">
                    Category for {search}
                  </label>
                  <select
                    id={categorySelectId}
                    className={styles.select}
                    value={categoryId}
                    onChange={(event) => setCategoryId(event.target.value)}
                  >
                    <option value="">Choose a category…</option>
                    {categoryList.map((category) => (
                      <option key={category.id} value={category.id}>
                        {category.name}
                      </option>
                    ))}
                  </select>
                  <Button size="sm" variant="soft" disabled={creating || !categoryId} onClick={() => void createOwn()}>
                    {creating ? 'Creating…' : `Create “${search}”`}
                  </Button>
                </div>
              )}
              {createError && <FormError message={createError} />}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
