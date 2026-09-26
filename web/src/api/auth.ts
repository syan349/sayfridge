import { apiFetch } from './client'
import type { Credentials, LoginResponse, User } from './types'

/** POST /auth/login — 401 "Invalid email or password" on bad credentials. */
export function login(credentials: Credentials): Promise<LoginResponse> {
  return apiFetch<LoginResponse>('/auth/login', { method: 'POST', body: credentials, auth: false })
}

/** GET /auth/me — the signed-in user, including their role. */
export function getMe(signal?: AbortSignal): Promise<User> {
  return apiFetch<User>('/auth/me', { signal })
}
