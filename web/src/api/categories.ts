// Category endpoint (docs/reference/API_REFERENCE.md §4, backend/app/schemas/business.py).
import { apiFetch } from './client'
import type { Page } from './types'

/** ItemCategoryRead — a public category (Dairy, Meat, …) or one the user created. */
export interface ItemCategory {
  id: string
  name: string
  status: 'ACTIVE' | 'ARCHIVED'
  sort_order: number
}

/** The most the backend sends in one page. */
const PAGE_SIZE = 100
/** Safety stop, in case a backend bug kept reporting more pages forever. */
const MAX_PAGES = 50

/**
 * GET /item-categories — EVERY visible ACTIVE category, in the backend's order.
 *
 * Users can create their own categories, so there can be more than one page
 * (e.g. 25 public + 76 private = 101 → "Yoghurt" sorts onto page 2). This asks
 * for page after page until it has `total` of them. If any page fails, the
 * whole call fails: a selector must never quietly show half the list.
 */
export async function listCategories(signal?: AbortSignal): Promise<ItemCategory[]> {
  const categories: ItemCategory[] = []
  const seen = new Set<string>()

  for (let page = 1; page <= MAX_PAGES; page++) {
    const result = await apiFetch<Page<ItemCategory>>('/item-categories', {
      query: { page, page_size: PAGE_SIZE },
      signal,
    })
    for (const category of result.items) {
      // A category added while we were paging can push one onto the next page twice.
      if (!seen.has(category.id)) {
        seen.add(category.id)
        categories.push(category)
      }
    }
    if (result.items.length === 0 || page * PAGE_SIZE >= result.total) break
  }
  return categories
}
