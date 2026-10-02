# SayFridge Web

React/TypeScript desktop client for inventory maintenance and administration.
The [project README](../README.md) is the overall entry point.

## Local development

Use Node.js 22. Start the backend first, then run from `web/`:

```bash
npm ci
npm run dev
```

Open <http://localhost:5173>. Vite proxies `/api` to `http://127.0.0.1:8000`.
`VITE_API_BASE_URL` defaults to `/api/v1`; for cloud builds set the HTTPS API
origin including `/api/v1`. Vite embeds this value in browser JavaScript, so it
must contain no secrets.

## Checks

```bash
npm run lint
npm test
npm run build
```

Vitest/Testing Library use MSW; unhandled unit-test requests fail rather than
contacting a server. Real HTTP/browser testing is a separate Playwright suite:
[Core E2E](../docs/testing/README.md#core-e2e).

## Pages

| Route | Page | Backend |
| --- | --- | --- |
| `/login`, `/register` | W01 Sign in, W02 Create account | connected (`/auth/login`, `/auth/register`) |
| `/` | Dashboard | connected (inventory, expiry summary, operations) |
| `/inventory` | W03 Inventory, with bulk move / consume / archive | connected |
| `/inventory/:id` | W05 Item details: record use, reconcile, edit, discard | connected |
| `/inventory/new` | W06 Add items by hand (one all-or-nothing batch) | connected (`/inventory-items/batch-create`) |
| `/spaces` | W04 Storage spaces | connected |
| `/expiry` | W09 Expiry overview | connected (`/inventory-items/expiry-summary`) |
| `/assistant` | W07 AI assistant (text only) | connected (`/agent/chat`, `/agent/resume`, streamed) |
| `/conversations` | W08 Conversation history | **sample data** — no list endpoint yet |
| `/settings` | W10 Profile and settings (read-only) | connected (`/auth/me`) |
| `/admin/accounts` | W11 Accounts (administrators only) | connected (`/admin/users`) |
| `/guest` | Guest mode | placeholder — no guest access on the backend |
| anything else | Page not found | — |

Every page has loading, empty and error states. If a page crashes while
drawing, an error page with "Reload" replaces it (`errorElement` in
`src/router.tsx`) and the menu stays usable. An ordinary user who opens an
admin address sees "No permission"; the backend refuses their requests (403)
anyway.

## Assistant and sessions

Fetch-based SSE readers stream authenticated POST replies. Cards use current
proposal IDs and per-item results. State recovery restores pending progress;
full conversation history remains a labeled sample page. The backend accepts
text/images; this Web interface provides text input, while Mobile supplies
camera/gallery/speech. See [client integration](../docs/reference/AGENT_FRONTEND_INTEGRATION.md)
for confirmation and retry behavior.

Access and refresh credentials are held in memory/sessionStorage for the tab.
Authenticated requests renew access automatically once and share concurrent
renewal. Logout clears the local session and requests server revocation. If the
logout request fails, local logout has completed but server revocation is unconfirmed.
Suspended accounts and expired/revoked sessions require login again.

Account email/password editing, account deletion, guest backend access and
administrator task/audit dashboards are outside current delivery.

## Structure and deployment

React Router provides layouts/guards; TanStack Query owns server-state caching
and refetching. Components use CSS Modules and shared design tokens. API adapters
live in `src/api/`; unit/component tests live alongside implementation.

`npm run build` writes `dist/`. Render settings, SPA rewrites, API/CORS alignment
and version checks are maintained in [Build and Deployment](../docs/delivery/README.md).

## Assets

`public/assets/` holds copies of the mobile app's images, served as `/assets/…`:

| Folder | Source | Note |
| --- | --- | --- |
| `icons/assistant/` | `mobile/assets/icons/assistant/` | resized to 256 px on the longest side (originals are up to 3448 px) |
| `icons/inventory/` | `mobile/assets/icons/inventory/` | copied unchanged (already 256 px) |
| `avatars/` | `mobile/assets/images/avatars/` | copied unchanged (100 px) |
