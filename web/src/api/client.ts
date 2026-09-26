// The one place the web app talks to the backend.
//
// apiFetch() adds the bearer token, sends/reads JSON, and turns every failed
// response into an ApiError so pages only handle one error type. The backend
// uses three error body shapes (docs/API_REFERENCE.md, "Errors"):
//
//   business:        {"detail": {"code": "NOT_FOUND", "message": "...", "errors"?: [...]}}
//   auth:            {"detail": "Invalid email or password"}
//   auth validation: {"detail": [{"type": "...", "loc": ["body", "email"], "msg": "..."}]}

import { clearToken, getToken } from './tokenStore'

const BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? '/api/v1').replace(/\/+$/, '')

export interface FieldError {
  loc: (string | number)[]
  msg: string
}

export class ApiError extends Error {
  /** HTTP status; 0 when the server could not be reached. */
  readonly status: number
  /** Backend business code (e.g. NOT_FOUND, VERSION_CONFLICT) or one derived from the status. */
  readonly code: string
  /** Per-field validation problems, when the backend sent them. */
  readonly fieldErrors: FieldError[]
  /** Batch endpoints: zero-based index of the first failing entry. */
  readonly itemIndex?: number

  constructor(
    status: number,
    code: string,
    message: string,
    details: { fieldErrors?: FieldError[]; itemIndex?: number } = {},
  ) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.fieldErrors = details.fieldErrors ?? []
    this.itemIndex = details.itemIndex
  }
}

/**
 * 409 VERSION_CONFLICT: the item was changed by someone else (or the phone)
 * after we loaded it, so the backend refused to overwrite that change.
 */
export function isVersionConflict(error: unknown): boolean {
  return error instanceof ApiError && error.code === 'VERSION_CONFLICT'
}

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE'
  /** Query parameters; undefined, null and '' values are left out. */
  query?: Record<string, string | number | boolean | null | undefined>
  /** Sent as JSON. */
  body?: unknown
  /** Extra headers, e.g. { 'Idempotency-Key': crypto.randomUUID() }. */
  headers?: Record<string, string>
  signal?: AbortSignal
  /**
   * false for the public endpoints (login, register): no token is sent and a
   * 401 is an ordinary answer ("wrong password"), not a reason to sign out.
   */
  auth?: boolean
}

const unauthorizedListeners = new Set<() => void>()

/** Called when an authenticated request gets 401 (token expired, or account disabled). */
export function onUnauthorized(listener: () => void): () => void {
  unauthorizedListeners.add(listener)
  return () => {
    unauthorizedListeners.delete(listener)
  }
}

export async function apiFetch<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', query, body, headers, signal, auth = true } = options
  const token = auth ? getToken() : null

  const requestHeaders: Record<string, string> = { Accept: 'application/json', ...headers }
  if (body !== undefined) requestHeaders['Content-Type'] = 'application/json'
  if (token) requestHeaders.Authorization = `Bearer ${token}`

  let response: Response
  try {
    response = await fetch(buildUrl(path, query), {
      method,
      headers: requestHeaders,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    })
  } catch (error) {
    if (signal?.aborted) throw error // cancelled on purpose, not a failure
    throw new ApiError(0, 'NETWORK_ERROR', 'Could not reach the server. Check your connection and try again.')
  }

  const data = await readBody(response)

  if (!response.ok) {
    if (response.status === 401 && auth) {
      clearToken()
      unauthorizedListeners.forEach((listener) => listener())
    }
    throw toApiError(response.status, data)
  }

  return data as T
}

function buildUrl(path: string, query: RequestOptions['query']): string {
  // Resolving against the page origin lets BASE_URL be relative (/api/v1)
  // or absolute (https://…/api/v1).
  const url = new URL(BASE_URL + path, window.location.origin)
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value))
    }
  }
  return url.toString()
}

async function readBody(response: Response): Promise<unknown> {
  const text = await response.text()
  if (!text) return undefined
  try {
    return JSON.parse(text)
  } catch {
    return text // e.g. an HTML error page from a proxy
  }
}

function toApiError(status: number, body: unknown): ApiError {
  const detail = isRecord(body) ? body.detail : undefined

  if (isRecord(detail) && typeof detail.code === 'string') {
    return new ApiError(
      status,
      detail.code,
      typeof detail.message === 'string' ? detail.message : fallbackMessage(status),
      {
        fieldErrors: toFieldErrors(detail.errors),
        itemIndex: typeof detail.item_index === 'number' ? detail.item_index : undefined,
      },
    )
  }

  if (typeof detail === 'string') {
    return new ApiError(status, codeForStatus(status), detail)
  }

  if (Array.isArray(detail)) {
    return new ApiError(status, 'VALIDATION_ERROR', 'Some fields are invalid.', {
      fieldErrors: toFieldErrors(detail),
    })
  }

  return new ApiError(status, codeForStatus(status), fallbackMessage(status))
}

function toFieldErrors(value: unknown): FieldError[] {
  if (!Array.isArray(value)) return []
  return value.filter(isRecord).map((error) => ({
    loc: Array.isArray(error.loc) ? error.loc : [],
    msg: typeof error.msg === 'string' ? error.msg : 'Invalid value',
  }))
}

function codeForStatus(status: number): string {
  switch (status) {
    case 401:
      return 'UNAUTHORIZED'
    case 403:
      return 'FORBIDDEN'
    case 404:
      return 'NOT_FOUND'
    case 409:
      return 'CONFLICT'
    case 422:
      return 'VALIDATION_ERROR'
    default:
      return status >= 500 ? 'SERVER_ERROR' : 'HTTP_ERROR'
  }
}

function fallbackMessage(status: number): string {
  return status >= 500
    ? 'The server had a problem. Please try again.'
    : `Request failed (${status}).`
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
