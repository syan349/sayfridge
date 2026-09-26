// Response and request shapes from backend/app/schemas/auth.py.
// Timestamps arrive as ISO 8601 strings; IDs are UUID strings.

export type UserRole = 'USER' | 'ADMIN'
export type UserStatus = 'ACTIVE' | 'SUSPENDED' | 'DISABLED'

/** UserPublic */
export interface User {
  id: string
  email: string
  role: UserRole
  status: UserStatus
  created_at: string
}

/** LoginRequest / RegisterRequest (password: 8–128 characters) */
export interface Credentials {
  email: string
  password: string
}

/** LoginResponse */
export interface LoginResponse {
  access_token: string
  token_type: 'bearer'
  expires_in: number
  user: User
}
