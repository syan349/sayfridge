// Credentials are tab-scoped in sessionStorage; never store passwords.
const STORAGE_KEY = 'sayfridge.auth'

interface StoredToken {
  refreshToken?: string
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
      return { token: parsed.token, expiresAt: parsed.expiresAt, refreshToken: "refreshToken" in parsed && typeof parsed.refreshToken === "string" ? parsed.refreshToken : undefined }
    }
  } catch {
    // Storage blocked or value corrupted: behave as signed out.
  }
  return null
}

export function getToken(): string | null {
  return current && Date.now() < current.expiresAt ? current.token : null
}

export function setToken(token: string, expiresInSeconds: number, refreshToken?: string): void {
  current = { token, refreshToken, expiresAt: Date.now() + expiresInSeconds * 1000 }
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

export function getRefreshToken(): string | null {
  return current?.refreshToken ?? null
}
