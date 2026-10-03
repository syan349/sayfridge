import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { beforeEach, describe, expect, it } from 'vitest'
import type { StorageSpace } from '../../api/storageSpaces'
import { signInAs, testUser } from '../../test/fixtures'
import { freezer, fridge, page } from '../../test/inventoryFixtures'
import { renderApp } from '../../test/renderApp'
import { server } from '../../test/server'

const oldFreezer: StorageSpace = { ...freezer, id: '33333333-0000-4000-8000-000000000009', name: 'Old chest freezer', status: 'ARCHIVED' }

// In stock per space: the fridge still holds 4 items, the freezer is empty.
const inStock: Record<string, number> = { [fridge.id]: 4, [freezer.id]: 0, [oldFreezer.id]: 0 }
let archived: string[]

beforeEach(() => {
  archived = []
  signInAs(testUser)
  server.use(
    http.get('/api/v1/storage-spaces', () => HttpResponse.json(page([fridge, freezer, oldFreezer]))),
    http.get('/api/v1/inventory-items', ({ request }) => {
      const space = new URL(request.url).searchParams.get('storage_space_id')
      return HttpResponse.json(page([], space ? (inStock[space] ?? 0) : 4))
    }),
    http.post('/api/v1/storage-spaces/:id/archive', ({ params }) => {
      archived.push(String(params.id))
      return HttpResponse.json({ ...freezer, status: 'ARCHIVED' })
    }),
  )
})

describe('SpacesPage (W04)', () => {
  it('won’t archive a space that still holds items, and says why', async () => {
    const user = userEvent.setup()
    renderApp('/spaces')

    const blockedButton = await screen.findByRole('button', { name: /^Archive Fridge/ })
    await waitFor(() => expect(blockedButton).toHaveAttribute('aria-disabled', 'true'))
    await user.click(blockedButton)

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Fridge still holds 4 items in stock. Move or discard them before archiving the space.',
    )
    expect(screen.queryByRole('dialog', { name: /Archive/ })).not.toBeInTheDocument()
    expect(archived).toEqual([]) // nothing was sent

    // The empty freezer can be archived — after a confirmation.
    await user.click(screen.getByRole('button', { name: 'Archive Freezer' }))
    const dialog = screen.getByRole('dialog', { name: 'Archive Freezer?' })
    await user.click(within(dialog).getByRole('button', { name: 'Archive' }))

    expect(await screen.findByText('Archived Freezer. It can be restored later.')).toBeInTheDocument()
    expect(archived).toEqual([freezer.id])
  })

  it('still lets you try when the item count can’t be loaded, and shows the backend’s refusal', async () => {
    server.use(
      http.get('/api/v1/inventory-items', () =>
        HttpResponse.json({ detail: { code: 'SERVER_ERROR', message: 'Database error' } }, { status: 500 }),
      ),
      http.post('/api/v1/storage-spaces/:id/archive', () =>
        HttpResponse.json(
          { detail: { code: 'STATE_CONFLICT', message: 'Storage space still has in-stock inventory' } },
          { status: 409 },
        ),
      ),
    )
    const user = userEvent.setup()
    renderApp('/spaces')

    const archive = await screen.findByRole('button', { name: 'Archive Fridge' })
    expect(archive).toHaveAttribute('aria-disabled', 'false') // unknown count: not blocked
    await user.click(archive)
    const dialog = screen.getByRole('dialog', { name: 'Archive Fridge?' })
    await user.click(within(dialog).getByRole('button', { name: 'Archive' }))

    expect(await within(dialog).findByText('Storage space still has in-stock inventory')).toBeInTheDocument()
  })

  it('creates a space with the chosen type', async () => {
    let body: unknown
    server.use(
      http.post('/api/v1/storage-spaces', async ({ request }) => {
        body = await request.json()
        return HttpResponse.json({ ...freezer, id: 'new-space', name: 'Garage freezer' }, { status: 201 })
      }),
    )
    const user = userEvent.setup()
    renderApp('/spaces')

    const form = await screen.findByRole('region', { name: 'Add a storage space' })
    await user.type(within(form).getByLabelText('Name'), 'Garage freezer')
    await user.click(within(form).getByLabelText('Freezer'))
    await user.click(within(form).getByRole('button', { name: 'Create space' }))

    expect(await screen.findByText('Added Garage freezer.')).toBeInTheDocument()
    expect(body).toEqual({ name: 'Garage freezer', type: 'FREEZER' })
    expect(within(form).getByLabelText('Name')).toHaveValue('') // ready for the next one
  })

  it('explains a name that is already taken', async () => {
    server.use(
      http.post('/api/v1/storage-spaces', () =>
        HttpResponse.json({ detail: { code: 'NAME_CONFLICT', message: 'Storage space name already exists' } }, { status: 409 }),
      ),
    )
    const user = userEvent.setup()
    renderApp('/spaces')

    const form = await screen.findByRole('region', { name: 'Add a storage space' })
    await user.type(within(form).getByLabelText('Name'), 'Fridge')
    await user.click(within(form).getByRole('button', { name: 'Create space' }))

    expect(await within(form).findByText('You already have an active space with this name.')).toBeInTheDocument()
  })

  it('renames a space, sending only what changed', async () => {
    let body: unknown
    server.use(
      http.patch('/api/v1/storage-spaces/:id', async ({ request }) => {
        body = await request.json()
        return HttpResponse.json({ ...fridge, name: 'Kitchen fridge' })
      }),
    )
    const user = userEvent.setup()
    renderApp('/spaces')

    await user.click(await screen.findByRole('button', { name: 'Rename Fridge' }))
    const dialog = screen.getByRole('dialog', { name: 'Edit Fridge' })
    const name = within(dialog).getByLabelText('Name')
    await user.clear(name)
    await user.type(name, 'Kitchen fridge')
    await user.click(within(dialog).getByRole('button', { name: 'Save' }))

    expect(await screen.findByText('Saved Kitchen fridge.')).toBeInTheDocument()
    expect(body).toEqual({ name: 'Kitchen fridge' }) // the type didn't change, so it isn't sent
  })

  it('offers Restore for an archived space', async () => {
    let restored = ''
    server.use(
      http.post('/api/v1/storage-spaces/:id/restore', ({ params }) => {
        restored = String(params.id)
        return HttpResponse.json({ ...oldFreezer, status: 'ACTIVE' })
      }),
    )
    const user = userEvent.setup()
    renderApp('/spaces')

    await user.click(await screen.findByRole('button', { name: 'Restore Old chest freezer' }))

    expect(await screen.findByText('Restored Old chest freezer.')).toBeInTheDocument()
    expect(restored).toBe(oldFreezer.id)
  })

  it('marks the default space and can make another one the default', async () => {
    let madeDefault: { id: string; body: string } | null = null
    server.use(
      http.get('/api/v1/storage-spaces', () =>
        // Before the change the fridge is the default; afterwards the freezer is.
        HttpResponse.json(
          page([
            { ...fridge, is_default: madeDefault === null },
            { ...freezer, is_default: madeDefault !== null },
          ]),
        ),
      ),
      http.post('/api/v1/storage-spaces/:id/default', async ({ params, request }) => {
        madeDefault = { id: String(params.id), body: await request.text() }
        return HttpResponse.json({ ...freezer, is_default: true })
      }),
    )
    const user = userEvent.setup()
    renderApp('/spaces')

    const fridgeRow = (await screen.findByRole('button', { name: 'Rename Fridge' })).closest('tr')!
    expect(within(fridgeRow).getByText('Default')).toBeInTheDocument()
    // The default space has nothing to offer here; the other one does.
    expect(screen.queryByRole('button', { name: 'Make Fridge the default space' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Make Freezer the default space' }))

    expect(await screen.findByText('Freezer is now your default space.')).toBeInTheDocument()
    expect(madeDefault).toEqual({ id: freezer.id, body: '' }) // the endpoint takes no request body
    const freezerRow = screen.getByRole('button', { name: 'Rename Freezer' }).closest('tr')!
    await waitFor(() => expect(within(freezerRow).getByText('Default')).toBeInTheDocument())
  })
})
