import type { RouteObject } from 'react-router-dom'
import { RequireAuth } from './auth/RequireAuth'
import { AppShell } from './components/AppShell/AppShell'
import { AccountsPage } from './pages/admin/AccountsPage'
import { AssistantPage } from './pages/assistant/AssistantPage'
import { ConversationsPage } from './pages/conversations/ConversationsPage'
import { DashboardPage } from './pages/dashboard/DashboardPage'
import { ExpiryPage } from './pages/expiry/ExpiryPage'
import { GuestPage } from './pages/GuestPage'
import { InventoryPage } from './pages/inventory/InventoryPage'
import { ItemDetailsPage } from './pages/itemDetails/ItemDetailsPage'
import { LoginPage } from './pages/LoginPage'
import { ProfilePage } from './pages/profile/ProfilePage'
import { RegisterPage } from './pages/RegisterPage'
import { SpacesPage } from './pages/spaces/SpacesPage'
import { ErrorPage } from './pages/status/ErrorPage'
import { NotFoundPage } from './pages/status/NotFoundPage'
import { StockInPage } from './pages/stockIn/StockInPage'

// The route table only. main.tsx turns it into a browser router; tests use a
// memory router with the same table, so they exercise the real routes.
export const routes: RouteObject[] = [
  {
    // The outer error boundary: a crash anywhere, even in the shell or the sign-in pages.
    errorElement: <ErrorPage />,
    children: [
      // Public pages: no sidebar, no sign-in needed.
      { path: '/login', element: <LoginPage /> },
      { path: '/register', element: <RegisterPage /> },
      { path: '/guest', element: <GuestPage /> },

      // Everything else needs a signed-in user and sits inside the shell.
      {
        element: <RequireAuth />,
        children: [
          {
            element: <AppShell />,
            children: [
              {
                // The inner error boundary: when a page crashes, the menu stays usable.
                errorElement: <ErrorPage />,
                children: [
                  { index: true, element: <DashboardPage /> },
                  { path: 'inventory', element: <InventoryPage /> },
                  { path: 'inventory/new', element: <StockInPage /> },
                  { path: 'inventory/:id', element: <ItemDetailsPage /> },
                  { path: 'expiry', element: <ExpiryPage /> },
                  { path: 'spaces', element: <SpacesPage /> },
                  { path: 'assistant', element: <AssistantPage /> },
                  // W08 shows sample data: the backend can't list conversations yet (issue #51).
                  { path: 'conversations', element: <ConversationsPage /> },
                  { path: 'settings', element: <ProfilePage /> },
                  {
                    path: 'admin',
                    element: <RequireAuth role="ADMIN" />,
                    // W12 (task ledger) and W13 (operation audit) are left out for now (team decision, 26 Sep).
                    children: [{ path: 'accounts', element: <AccountsPage /> }],
                  },
                  { path: '*', element: <NotFoundPage /> },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
]
