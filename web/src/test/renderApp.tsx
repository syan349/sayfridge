import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render } from '@testing-library/react'
import { RouterProvider, createMemoryRouter } from 'react-router-dom'
import { AuthProvider } from '../auth/AuthProvider'
import { routes } from '../router'

/**
 * Renders the whole app — the real routes, AuthProvider and React Query — as if
 * the browser had opened `path`. A memory router is used instead of the
 * browser's address bar. The backend is whatever the test set up with MSW.
 */
export function renderApp(path = '/') {
  // A fresh cache per test, and no retries so errors show up straight away.
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const router = createMemoryRouter(routes, { initialEntries: [path] })

  render(
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <RouterProvider router={router} />
      </AuthProvider>
    </QueryClientProvider>,
  )

  return { router }
}
