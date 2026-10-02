import { http, HttpResponse } from 'msw'
import { describe, expect, it } from 'vitest'
import { server } from '../test/server'
import type { ItemCategory } from './categories'
import { listCategories } from './categories'
import { ApiError } from './client'

const category = (name: string, index = 0): ItemCategory => ({
  id: `category-${name.toLowerCase().replace(/\s+/g, '-')}`,
  name,
  status: 'ACTIVE',
  sort_order: index,
})

// 25 public + 76 private = 101 categories, sorted by name: "Yoghurt" is the 101st, on page 2.
const firstHundred = Array.from({ length: 100 }, (_, index) => category(`Category ${String(index).padStart(3, '0')}`, index))
const yoghurt = category('Yoghurt', 100)

/** Answers GET /item-categories page by page from `pages`, and remembers what was asked. */
function servePages(pages: ItemCategory[][], total: number, failOnPage?: number) {
  const asked: { page: string | null; pageSize: string | null }[] = []
  server.use(
    http.get('/api/v1/item-categories', ({ request }) => {
      const params = new URL(request.url).searchParams
      asked.push({ page: params.get('page'), pageSize: params.get('page_size') })
      const page = Number(params.get('page'))
      if (page === failOnPage) {
        return HttpResponse.json({ detail: { code: 'SERVER_ERROR', message: 'Database error' } }, { status: 500 })
      }
      return HttpResponse.json({ items: pages[page - 1] ?? [], total, page, page_size: 100 })
    }),
  )
  return asked
}

describe('listCategories', () => {
  it('fetches every page, so a category on page 2 (Yoghurt) is included, in the backend’s order', async () => {
    const asked = servePages([firstHundred, [yoghurt]], 101)

    const categories = await listCategories()

    expect(categories).toHaveLength(101)
    expect(categories[0].name).toBe('Category 000')
    expect(categories.at(-1)).toEqual(yoghurt)
    expect(asked).toEqual([
      { page: '1', pageSize: '100' },
      { page: '2', pageSize: '100' },
    ])
  })

  it('returns an empty list after one request when there are no categories', async () => {
    const asked = servePages([[]], 0)

    expect(await listCategories()).toEqual([])
    expect(asked).toHaveLength(1)
  })

  it('fails as a whole when a later page fails, instead of returning half the list', async () => {
    servePages([firstHundred, [yoghurt]], 101, 2)

    await expect(listCategories()).rejects.toBeInstanceOf(ApiError)
  })

  it('leaves out a category that appears on two pages (e.g. one was added while paging)', async () => {
    servePages([firstHundred, [firstHundred[99], yoghurt]], 102)

    const categories = await listCategories()

    expect(categories).toHaveLength(101)
    expect(new Set(categories.map((c) => c.id)).size).toBe(101)
  })

  it('passes the cancel signal on, so leaving the page stops the requests', async () => {
    servePages([firstHundred, [yoghurt]], 101)
    const controller = new AbortController()
    controller.abort()

    await expect(listCategories(controller.signal)).rejects.toThrow()
  })
})
