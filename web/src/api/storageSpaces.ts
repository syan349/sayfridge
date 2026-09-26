// Storage-space endpoints (docs/API_REFERENCE.md §3, backend/app/schemas/business.py).
import { apiFetch } from './client'
import type { Page } from './types'

export type SpaceType = 'FRIDGE' | 'FREEZER' | 'PANTRY' | 'WAREHOUSE' | 'OTHER'

/** StorageSpaceRead */
export interface StorageSpace {
  id: string
  name: string
  type: SpaceType
  status: 'ACTIVE' | 'ARCHIVED'
  created_at: string
  updated_at: string
}

/** GET /storage-spaces — the user's ACTIVE spaces, sorted by name. 100 is the backend's page-size limit. */
export function listStorageSpaces(signal?: AbortSignal): Promise<Page<StorageSpace>> {
  return apiFetch<Page<StorageSpace>>('/storage-spaces', { query: { page_size: 100 }, signal })
}
