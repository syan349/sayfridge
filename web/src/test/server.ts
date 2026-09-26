import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'

const emptyPage = { items: [], total: 0, page: 1, page_size: 20 }

// Default answers: an empty household. Every signed-in page asks for the sidebar
// counts and the dashboard asks for several lists; these keep such background
// requests quiet. A test declares what it cares about with server.use(...), which
// takes priority over these defaults.
const emptyHousehold = [
  // Careful: a test that adds GET "/inventory-items/:id" would also catch this path
  // ("expiry-summary" looks like an id), so such a test answers it first itself.
  http.get('/api/v1/inventory-items/expiry-summary', () =>
    HttpResponse.json({ ...emptyPage, counts: { overdue: 0, today: 0, upcoming: 0 } }),
  ),
  http.get('/api/v1/inventory-items', () => HttpResponse.json(emptyPage)),
  http.get('/api/v1/storage-spaces', () => HttpResponse.json(emptyPage)),
  http.get('/api/v1/item-categories', () => HttpResponse.json(emptyPage)),
  http.get('/api/v1/inventory-operations', () => HttpResponse.json(emptyPage)),
]

// Any request without a handler (default or added) fails the test (see setup.ts),
// so nothing ever reaches a real server.
export const server = setupServer(...emptyHousehold)
