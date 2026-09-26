// Category endpoint (docs/API_REFERENCE.md §4, backend/app/schemas/business.py).
import { apiFetch } from './client'
import type { Page } from './types'

/** ItemCategoryRead — public categories shared by everyone (Dairy, Meat, …). */
export interface ItemCategory {
  id: string
  name: string
  status: 'ACTIVE' | 'ARCHIVED'
  sort_order: number
}

/** GET /item-categories — ACTIVE categories in display order. */
export function listCategories(signal?: AbortSignal): Promise<Page<ItemCategory>> {
  return apiFetch<Page<ItemCategory>>('/item-categories', { query: { page_size: 100 }, signal })
}
