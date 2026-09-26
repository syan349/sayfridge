import { setupServer } from 'msw/node'

// Mock backend for tests. It starts with no handlers: each test declares the
// responses it needs with server.use(http.get('/api/v1/…', …)). Any request
// without a handler fails the test (see setup.ts), so nothing reaches a real server.
export const server = setupServer()
