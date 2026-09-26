import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import * as authApi from '../api/auth'
import { onUnauthorized } from '../api/client'
import { clearToken, getToken, setToken } from '../api/tokenStore'
import type { Credentials } from '../api/types'
import { AuthContext, type AuthContextValue, type AuthStatus } from './AuthContext'

const ME_QUERY_KEY = ['auth', 'me'] as const

/** Knows who is signed in. The user comes from GET /auth/me whenever a token exists. */
export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient()
  const [hasToken, setHasToken] = useState(() => getToken() !== null)

  const me = useQuery({
    queryKey: ME_QUERY_KEY,
    queryFn: ({ signal }) => authApi.getMe(signal),
    enabled: hasToken,
    retry: false,
    staleTime: 5 * 60 * 1000,
  })

  const logout = useCallback(() => {
    clearToken()
    setHasToken(false)
    queryClient.clear() // forget every response cached for this user
  }, [queryClient])

  // A 401 on any request means the token expired or the account was disabled.
  useEffect(() => onUnauthorized(logout), [logout])

  const login = useCallback(
    async (credentials: Credentials) => {
      const response = await authApi.login(credentials)
      setToken(response.access_token, response.expires_in)
      // The login response already contains the user, so skip a /auth/me round trip.
      queryClient.setQueryData(ME_QUERY_KEY, response.user)
      setHasToken(true)
      return response.user
    },
    [queryClient],
  )

  let status: AuthStatus
  if (!hasToken) status = 'anonymous'
  else if (me.data) status = 'authenticated'
  else if (me.isError) status = 'error'
  else status = 'loading'

  const { data, error, refetch } = me
  const value = useMemo<AuthContextValue>(
    () => ({
      status,
      user: status === 'authenticated' ? (data ?? null) : null,
      error: status === 'error' ? error : null,
      login,
      logout,
      retry: () => void refetch(),
    }),
    [status, data, error, login, logout, refetch],
  )

  return <AuthContext value={value}>{children}</AuthContext>
}
