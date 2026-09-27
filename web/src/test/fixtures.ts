import { http, HttpResponse } from 'msw'
import { setToken } from '../api/tokenStore'
import type { LoginResponse, User } from '../api/types'
import { server } from './server'

export const testUser: User = {
  id: '550e8400-e29b-41d4-a716-446655440000',
  email: 'tim@example.com',
  role: 'USER',
  status: 'ACTIVE',
  created_at: '2026-09-11T00:00:00Z',
}

export const testAdmin: User = {
  ...testUser,
  id: '6f1d2c3b-0000-4000-8000-000000000001',
  email: 'admin@example.com',
  role: 'ADMIN',
}

export function loginResponse(user: User = testUser): LoginResponse {
  return { access_token: 'test-token', token_type: 'bearer', expires_in: 900, user }
}

/** The dashboard's heading greets the user by the time of day: "Good morning, tim". */
export const DASHBOARD_HEADING = /^Good (morning|afternoon|evening), /

/** Starts the test already signed in: a stored token, and GET /auth/me answering with `user`. */
export function signInAs(user: User) {
  setToken('test-token', 900)
  server.use(http.get('/api/v1/auth/me', () => HttpResponse.json(user)))
}
