import { apiFetch } from './client'
import type { Credentials, LoginResponse, User } from './types'

/** POST /auth/login — 401 "Invalid email or password" on bad credentials. */
export function login(credentials: Credentials): Promise<LoginResponse> {
  return apiFetch<LoginResponse>('/auth/login', { method: 'POST', body: credentials, auth: false })
}

/**
 * POST /auth/register — creates a USER account and returns it (201). No token:
 * sign in separately. 409 "Email is already registered"; 422 for invalid input.
 * The backend accepts only email and password; any extra field is rejected.
 */
export function register(credentials: Credentials): Promise<User> {
  return apiFetch<User>('/auth/register', { method: 'POST', body: credentials, auth: false })
}

/** GET /auth/me — the signed-in user, including their role. */
export function getMe(signal?: AbortSignal): Promise<User> {
  return apiFetch<User>('/auth/me', { signal })
}
