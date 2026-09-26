// Holds the bearer token from POST /auth/login.
//
// Kept in memory for normal use and mirrored to sessionStorage so a page
// reload keeps you signed in; sessionStorage is cleared when the tab closes.
// The backend has no refresh tokens, so the token simply stops being used
// once `expires_in` seconds have passed.

const STORAGE_KEY = 'sayfridge.auth'

interface StoredToken {
  token: string
  expiresAt: number // epoch milliseconds
}

let current: StoredToken | null = readStorage()

function readStorage(): StoredToken | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    const parsed: unknown = JSON.parse(raw)
    if (
      typeof parsed === 'object' &&
      parsed !== null &&
      'token' in parsed &&
      'expiresAt' in parsed &&
      typeof parsed.token === 'string' &&
      typeof parsed.expiresAt === 'number'
    ) {
      return { token: parsed.token, expiresAt: parsed.expiresAt }
    }
  } catch {
    // Storage blocked or value corrupted: behave as signed out.
  }
  return null
}

export function getToken(): string | null {
  if (current && Date.now() >= current.expiresAt) clearToken()
  return current?.token ?? null
}

export function setToken(token: string, expiresInSeconds: number): void {
  current = { token, expiresAt: Date.now() + expiresInSeconds * 1000 }
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(current))
  } catch {
    // Storage blocked: the in-memory copy still works until reload.
  }
}

export function clearToken(): void {
  current = null
  try {
    sessionStorage.removeItem(STORAGE_KEY)
  } catch {
    // Nothing to clean up.
  }
}
