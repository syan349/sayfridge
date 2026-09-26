import { createContext, useContext } from 'react'
import type { Credentials, User } from '../api/types'

/**
 * anonymous     — no token: send the user to /login
 * loading       — token found, GET /auth/me in flight
 * authenticated — user loaded
 * error         — GET /auth/me failed for a reason other than 401 (e.g. backend down)
 */
export type AuthStatus = 'anonymous' | 'loading' | 'authenticated' | 'error'

export interface AuthContextValue {
  status: AuthStatus
  user: User | null
  /** Why the user could not be loaded; set only when status is 'error'. */
  error: Error | null
  login: (credentials: Credentials) => Promise<User>
  logout: () => void
  /** Load the user again after an error. */
  retry: () => void
}

export const AuthContext = createContext<AuthContextValue | null>(null)

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext)
  if (!value) throw new Error('useAuth() must be used inside <AuthProvider>')
  return value
}
