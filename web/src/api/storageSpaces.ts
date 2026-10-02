// Storage-space endpoints (docs/reference/API_REFERENCE.md §3, backend/app/schemas/business.py).
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

/** GET /storage-spaces?status=ALL — active and archived spaces (the W04 list). */
export function listAllStorageSpaces(signal?: AbortSignal): Promise<Page<StorageSpace>> {
  return apiFetch<Page<StorageSpace>>('/storage-spaces', { query: { status: 'ALL', page_size: 100 }, signal })
}

/** POST /storage-spaces — 409 NAME_CONFLICT if an active space already has this name. */
export function createStorageSpace(space: { name: string; type: SpaceType }): Promise<StorageSpace> {
  return apiFetch<StorageSpace>('/storage-spaces', { method: 'POST', body: space })
}

/** PATCH /storage-spaces/{id} — rename and/or change the type. Only ACTIVE spaces can be edited. */
export function updateStorageSpace(id: string, changes: { name?: string; type?: SpaceType }): Promise<StorageSpace> {
  return apiFetch<StorageSpace>(`/storage-spaces/${id}`, { method: 'PATCH', body: changes })
}

/** POST /storage-spaces/{id}/archive — refused (409 STATE_CONFLICT) while the space holds IN_STOCK items. */
export function archiveStorageSpace(id: string): Promise<StorageSpace> {
  return apiFetch<StorageSpace>(`/storage-spaces/${id}/archive`, { method: 'POST' })
}

/** POST /storage-spaces/{id}/restore — 409 NAME_CONFLICT if an active space took its name meanwhile. */
export function restoreStorageSpace(id: string): Promise<StorageSpace> {
  return apiFetch<StorageSpace>(`/storage-spaces/${id}/restore`, { method: 'POST' })
}
