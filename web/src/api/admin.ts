// Administrator endpoints (docs/reference/API_REFERENCE.md §8, backend/app/schemas/admin.py).
// Only ADMIN accounts may call them; anyone else gets 403 FORBIDDEN.
import { apiFetch } from './client'
import type { Page, UserRole, UserStatus } from './types'

/** AdminUserRead — no names or avatars exist on the backend, so an account is its email. */
export interface AdminUser {
  id: string
  email: string
  role: UserRole
  status: UserStatus
  created_at: string
  updated_at: string
}

export interface UserQuery {
  /** Search in the email address. */
  q: string
  role: UserRole | 'ALL'
  status: UserStatus | 'ALL'
  page: number
  pageSize: number
}

/** GET /admin/users — newest accounts first. */
export function listUsers(query: UserQuery, signal?: AbortSignal): Promise<Page<AdminUser>> {
  return apiFetch<Page<AdminUser>>('/admin/users', {
    query: { q: query.q, role: query.role, status: query.status, page: query.page, page_size: query.pageSize },
    signal,
  })
}

/**
 * PATCH /admin/users/{id}/status — suspend, disable or reactivate an ordinary
 * account. Administrators can't be changed here (403 ADMIN_TARGET_FORBIDDEN).
 */
export function setUserStatus(user: AdminUser, status: UserStatus): Promise<AdminUser> {
  return apiFetch<AdminUser>(`/admin/users/${user.id}/status`, { method: 'PATCH', body: { status } })
}
