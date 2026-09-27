import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider, createBrowserRouter } from 'react-router-dom'
import './index.css'
import { ApiError } from './api/client'
import { AuthProvider } from './auth/AuthProvider'
import { routes } from './router'

const router = createBrowserRouter(routes)

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Retry network and server errors twice; a 4xx answer will not change on retry.
      retry: (failureCount, error) =>
        failureCount < 2 && !(error instanceof ApiError && error.status >= 400 && error.status < 500),
    },
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <RouterProvider router={router} />
      </AuthProvider>
    </QueryClientProvider>
  </StrictMode>,
)
