// Item-definition endpoints (docs/API_REFERENCE.md §5, backend/app/schemas/business.py).
// A definition is a kind of food ("Milk"); inventory items are batches of it.
import { apiFetch } from './client'
import type { Page } from './types'

/**
 * ItemDefinitionRead. PUBLIC definitions are shared by everyone; PRIVATE ones
 * were created by this user ("Yours") and only they can see them.
 */
export interface ItemDefinition {
  id: string
  name: string
  category_id: string
  status: 'ACTIVE' | 'ARCHIVED'
  scope: 'PUBLIC' | 'PRIVATE'
}

/** GET /item-definitions?q= — ACTIVE public definitions plus the user's own, by name. */
export function searchDefinitions(q: string, signal?: AbortSignal): Promise<Page<ItemDefinition>> {
  return apiFetch<Page<ItemDefinition>>('/item-definitions', { query: { q, scope: 'ALL', page_size: 8 }, signal })
}

/** POST /item-definitions — a new PRIVATE definition. 409 NAME_CONFLICT if you already have one with that name. */
export function createDefinition(definition: { name: string; category_id: string }): Promise<ItemDefinition> {
  return apiFetch<ItemDefinition>('/item-definitions', { method: 'POST', body: definition })
}
