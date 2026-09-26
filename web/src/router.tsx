import type { RouteObject } from 'react-router-dom'
import { RequireAuth } from './auth/RequireAuth'
import { AppShell } from './components/AppShell/AppShell'
import { GuestPage } from './pages/GuestPage'
import { InventoryPage } from './pages/inventory/InventoryPage'
import { ItemDetailsPage } from './pages/itemDetails/ItemDetailsPage'
import { LoginPage } from './pages/LoginPage'
import { PlaceholderPage } from './pages/PlaceholderPage'
import { RegisterPage } from './pages/RegisterPage'

// Page names and issue numbers follow the design handoff (sub-issues of #14).
const notBuilt = (page: string) => `Not built yet — ${page}.`

// The route table only. main.tsx turns it into a browser router; tests use a
// memory router with the same table, so they exercise the real routes.
export const routes: RouteObject[] = [
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
          { index: true, element: <PlaceholderPage title="Dashboard" message={notBuilt('Dashboard')} /> },
          { path: 'inventory', element: <InventoryPage /> },
          // "Add items" on the inventory page leads here; the real page is W06 (Day 6).
          { path: 'inventory/new', element: <PlaceholderPage title="Add items" message={notBuilt('W06, issue #49')} /> },
          { path: 'inventory/:id', element: <ItemDetailsPage /> },
          { path: 'expiry', element: <PlaceholderPage title="Expiry overview" message={notBuilt('W09, issue #52')} /> },
          { path: 'spaces', element: <PlaceholderPage title="Storage spaces" message={notBuilt('W04, issue #47')} /> },
          { path: 'assistant', element: <PlaceholderPage title="AI assistant" message={notBuilt('W07, issue #50')} /> },
          {
            path: 'conversations',
            element: <PlaceholderPage title="Conversation log" message={notBuilt('W08, issue #51')} />,
          },
          {
            path: 'settings',
            element: <PlaceholderPage title="Profile & settings" message={notBuilt('W10, issue #53')} />,
          },
          {
            path: 'admin',
            element: <RequireAuth role="ADMIN" />,
            // W12 (task ledger) and W13 (operation audit) are left out for now (team decision, 26 Sep).
            children: [
              { path: 'accounts', element: <PlaceholderPage title="Accounts" message={notBuilt('W11, issue #54')} /> },
            ],
          },
          {
            path: '*',
            element: <PlaceholderPage title="Page not found" message="There is no page at this address." />,
          },
        ],
      },
    ],
  },
]
