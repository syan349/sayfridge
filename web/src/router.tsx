import { createBrowserRouter, type RouteObject } from 'react-router-dom'
import { RequireAuth } from './auth/RequireAuth'
import { AppShell } from './components/AppShell/AppShell'
import { LoginPlaceholderPage } from './pages/LoginPlaceholderPage'
import { PlaceholderPage } from './pages/PlaceholderPage'

// Page names and issue numbers follow the design handoff (sub-issues of #14).
const notBuilt = (page: string) => `Not built yet — ${page}.`

export const routes: RouteObject[] = [
  { path: '/login', element: <LoginPlaceholderPage /> },
  {
    element: <RequireAuth />,
    children: [
      {
        element: <AppShell />,
        children: [
          { index: true, element: <PlaceholderPage title="Dashboard" message={notBuilt('Dashboard')} /> },
          { path: 'inventory', element: <PlaceholderPage title="Inventory" message={notBuilt('W03, issue #46')} /> },
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
            children: [
              { path: 'accounts', element: <PlaceholderPage title="Accounts" message={notBuilt('W11, issue #54')} /> },
              { path: 'tasks', element: <PlaceholderPage title="Task ledger" message={notBuilt('W12, issue #55')} /> },
              { path: 'audit', element: <PlaceholderPage title="Operation audit" message={notBuilt('W13, issue #56')} /> },
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

export const router = createBrowserRouter(routes)
