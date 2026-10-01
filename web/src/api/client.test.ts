import { http, HttpResponse } from 'msw'
import { describe, expect, it, vi } from 'vitest'
import { server } from '../test/server'
import { ApiError, apiFetch, onUnauthorized } from './client'
import { getToken, getRefreshToken, setToken } from './tokenStore'
import type { User } from './types'

const user: User = {
  id: '550e8400-e29b-41d4-a716-446655440000',
  email: 'tim@example.com',
  role: 'USER',
  status: 'ACTIVE',
  created_at: '2026-09-11T00:00:00Z',
}

/** Runs the request and returns the error it threw. */
async function failure(request: Promise<unknown>): Promise<ApiError> {
  const error = await request.then(
    () => expect.fail('expected the request to fail'),
    (reason: unknown) => reason,
  )
  expect(error).toBeInstanceOf(ApiError)
  return error as ApiError
}

describe('apiFetch', () => {
  it('sends the bearer token and returns the JSON body', async () => {
    setToken('token-123', 900)
    let authorization: string | null = null
    server.use(
      http.get('/api/v1/auth/me', ({ request }) => {
        authorization = request.headers.get('Authorization')
        return HttpResponse.json(user)
      }),
    )

    await expect(apiFetch<User>('/auth/me')).resolves.toEqual(user)
    expect(authorization).toBe('Bearer token-123')
  })

  it('sends JSON bodies and extra headers such as Idempotency-Key', async () => {
    setToken('token-123', 900)
    let received: { body: unknown; contentType: string | null; key: string | null } | null = null
    server.use(
      http.post('/api/v1/inventory-items/item-1/operations', async ({ request }) => {
        received = {
          body: await request.json(),
          contentType: request.headers.get('Content-Type'),
          key: request.headers.get('Idempotency-Key'),
        }
        return HttpResponse.json({ ok: true }, { status: 201 })
      }),
    )

    await apiFetch('/inventory-items/item-1/operations', {
      method: 'POST',
      body: { operation_type: 'CONSUME' },
      headers: { 'Idempotency-Key': 'key-1' },
    })

    expect(received).toEqual({
      body: { operation_type: 'CONSUME' },
      contentType: 'application/json',
      key: 'key-1',
    })
  })

  it('adds query parameters and leaves out empty ones', async () => {
    let search = ''
    server.use(
      http.get('/api/v1/inventory-items', ({ request }) => {
        search = new URL(request.url).search
        return HttpResponse.json({ items: [], total: 0, page: 2, page_size: 20 })
      }),
    )

    await apiFetch('/inventory-items', { query: { q: 'milk', page: 2, storage_space_id: undefined, category_id: '' } })

    expect(search).toBe('?q=milk&page=2')
  })

  it('reads business errors: code, message and field errors', async () => {
    server.use(
      http.get('/api/v1/inventory-items', () =>
        HttpResponse.json(
          {
            detail: {
              code: 'VALIDATION_ERROR',
              message: 'Invalid request parameters',
              errors: [{ loc: ['query', 'page_size'], msg: 'Input should be less than or equal to 100' }],
            },
          },
          { status: 422 },
        ),
      ),
    )

    const error = await failure(apiFetch('/inventory-items', { query: { page_size: 500 } }))

    expect(error).toMatchObject({ status: 422, code: 'VALIDATION_ERROR', message: 'Invalid request parameters' })
    expect(error.fieldErrors).toEqual([
      { loc: ['query', 'page_size'], msg: 'Input should be less than or equal to 100' },
    ])
  })

  it('reads authentication validation errors (a list under "detail")', async () => {
    server.use(
      http.post('/api/v1/auth/login', () =>
        HttpResponse.json(
          { detail: [{ type: 'string_too_short', loc: ['body', 'password'], msg: 'String should have at least 8 characters' }] },
          { status: 422 },
        ),
      ),
    )

    const error = await failure(
      apiFetch('/auth/login', { method: 'POST', body: { email: 'a@b.co', password: 'short' }, auth: false }),
    )

    expect(error.code).toBe('VALIDATION_ERROR')
    expect(error.fieldErrors).toEqual([{ loc: ['body', 'password'], msg: 'String should have at least 8 characters' }])
  })

  it('treats a wrong password as an ordinary error, not a sign-out', async () => {
    setToken('token-123', 900)
    const listener = vi.fn()
    const unsubscribe = onUnauthorized(listener)
    let authorization: string | null = 'not checked'
    server.use(
      http.post('/api/v1/auth/login', ({ request }) => {
        authorization = request.headers.get('Authorization')
        return HttpResponse.json({ detail: 'Invalid email or password' }, { status: 401 })
      }),
    )

    const error = await failure(
      apiFetch('/auth/login', { method: 'POST', body: { email: 'a@b.co', password: 'wrong-pass' }, auth: false }),
    )

    expect(error).toMatchObject({ status: 401, code: 'UNAUTHORIZED', message: 'Invalid email or password' })
    expect(authorization).toBeNull() // public endpoint: no token sent
    expect(listener).not.toHaveBeenCalled()
    expect(getToken()).toBe('token-123')
    unsubscribe()
  })

  it('signs out when an authenticated request gets 401', async () => {
    setToken('expired-token', 900)
    const listener = vi.fn()
    const unsubscribe = onUnauthorized(listener)
    server.use(
      http.get('/api/v1/auth/me', () =>
        HttpResponse.json({ detail: 'Invalid or expired access token' }, { status: 401 }),
      ),
    )

    const error = await failure(apiFetch('/auth/me'))

    expect(error).toMatchObject({ status: 401, code: 'UNAUTHORIZED' })
    expect(getToken()).toBeNull()
    expect(listener).toHaveBeenCalledOnce()
    unsubscribe()
  })

  it('reports a network failure as NETWORK_ERROR', async () => {
    server.use(http.get('/api/v1/auth/me', () => HttpResponse.error()))

    const error = await failure(apiFetch('/auth/me'))

    expect(error).toMatchObject({ status: 0, code: 'NETWORK_ERROR' })
  })
})


describe('persistent session renewal', () => {
  it('coalesces concurrent 401 responses and retries with the replacement', async () => {
    setToken('old', 900, 'refresh-old')
    let rotations = 0
    server.use(
      http.post('/api/v1/auth/refresh', async ({ request }) => {
        rotations++
        expect(await request.json()).toEqual({ refresh_token: 'refresh-old' })
        await new Promise((resolve) => setTimeout(resolve, 20))
        return HttpResponse.json({ access_token: 'new', refresh_token: 'refresh-new', expires_in: 900 })
      }),
      http.get('/api/v1/auth/me', ({ request }) => request.headers.get('Authorization') === 'Bearer new'
        ? HttpResponse.json(user) : HttpResponse.json({ detail: 'Expired' }, { status: 401 })),
    )
    await expect(Promise.all([apiFetch('/auth/me'), apiFetch('/auth/me')])).resolves.toEqual([user, user])
    expect(rotations).toBe(1)
    expect(getRefreshToken()).toBe('refresh-new')
  })

  it('renews expired access before sending a request', async () => {
    setToken('expired', -1, 'refresh-old')
    server.use(
      http.post('/api/v1/auth/refresh', () => HttpResponse.json({ access_token: 'new', refresh_token: 'refresh-new', expires_in: 900 })),
      http.get('/api/v1/auth/me', ({ request }) => {
        expect(request.headers.get('Authorization')).toBe('Bearer new')
        return HttpResponse.json(user)
      }),
    )
    await expect(apiFetch('/auth/me')).resolves.toEqual(user)
  })

  it('preserves refresh credentials after a network error', async () => {
    setToken('expired', -1, 'refresh-old')
    server.use(http.post('/api/v1/auth/refresh', () => HttpResponse.error()))
    expect(await failure(apiFetch('/auth/me'))).toMatchObject({ status: 0 })
    expect(getRefreshToken()).toBe('refresh-old')
  })

  it('clears a revoked session and stops retrying', async () => {
    setToken('old', 900, 'refresh-old')
    const listener = vi.fn()
    const unsubscribe = onUnauthorized(listener)
    server.use(
      http.post('/api/v1/auth/refresh', () => HttpResponse.json({ detail: 'Revoked' }, { status: 401 })),
      http.get('/api/v1/auth/me', () => HttpResponse.json({ detail: 'Expired' }, { status: 401 })),
    )
    expect(await failure(apiFetch('/auth/me'))).toMatchObject({ status: 401 })
    expect(getRefreshToken()).toBeNull()
    expect(listener).toHaveBeenCalledOnce()
    unsubscribe()
  })
})


it('notifies once when an already expired access token cannot be renewed', async () => {
  setToken('expired', -1, 'refresh-old')
  const listener = vi.fn()
  const unsubscribe = onUnauthorized(listener)
  server.use(http.post('/api/v1/auth/refresh', () => HttpResponse.json({ detail: 'Revoked' }, { status: 401 })))
  expect(await failure(apiFetch('/auth/me'))).toMatchObject({ status: 401 })
  expect(listener).toHaveBeenCalledOnce()
  unsubscribe()
})
