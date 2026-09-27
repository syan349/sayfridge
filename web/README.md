# SayFridge Web

SayFridge 的 React Web 端，由用户页面和管理员页面共用。当前项目使用 React、TypeScript 和 Vite，后续通过路由、布局和后端权限区分不同角色。

The web app is for the jobs that are easier on a big screen: looking through and
bulk-editing the whole inventory, typing in a shopping trip, the expiry overview,
and account administration. Voice and receipt photos are in the mobile app. Both
apps use the same FastAPI backend; the web app never talks to the database.

## 本地开发 / Local development

Needs Node 22 or newer.

```bash
npm install
npm run dev        # http://localhost:5173
```

Start the backend first (`../backend/README.md`). The Vite dev server forwards
every `/api` request to `http://127.0.0.1:8000` (see `vite.config.ts`), so the
browser only talks to its own origin and needs no CORS support from the backend.

## Environment variables

| Name | Default | What it is for |
| --- | --- | --- |
| `VITE_API_BASE_URL` | `/api/v1` | Where the backend is, including the `/api/v1` prefix. Only needed when the app is not served through the dev proxy, e.g. a deployed build: `VITE_API_BASE_URL=https://api.example.com/api/v1`. Put it in `.env.local` (git-ignored) or the host's build settings. |

Vite copies `VITE_…` values into the built JavaScript, so never put a secret in one.

## 基础检查 / Checks

```bash
npm run lint       # oxlint
npm run build      # type-check (tsc) + production build into dist/
npm test           # Vitest + Testing Library; the API is mocked with MSW
```

Tests never reach a real server: any request without a mock fails the test
(`src/test/setup.ts`). `src/test/server.ts` answers the background requests
every signed-in page makes with an empty household.

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

### The assistant (W07)

`POST /agent/chat` and `POST /agent/resume` answer with a stream of
Server-Sent Events, so the reply appears word by word. `EventSource` only
does GET and can't send the bearer token, so `src/api/agent.ts` reads the
stream with `fetch()` and `response.body.getReader()`, splitting it into
events at blank lines. When the assistant wants to change stock and isn't
sure (an AI estimate, a new item), it waits: the page shows a proposal card
with Confirm / Edit / Cancel, which answers through `/agent/resume`. The
conversation id is kept in `sessionStorage`, so a reload brings back what
was proposed and saved (`GET /agent/conversations/{id}/state`; the backend
doesn't keep the message text).

## Not built yet (future work)

- **W08 Conversation history, for real** — needs an endpoint that lists a user's
  conversations with their messages. The page shows sample data until then
  (`src/pages/conversations/sampleConversations.ts`).
- **W12 Task ledger and W13 Operation audit** (administrators) — left out in
  this phase by team decision (26 Sep).
- **Changing email or password, reminders, deleting the account** (W10) — the
  backend has no endpoints for them.
- **Photos in the assistant** (W07) — the chat endpoint takes text only.
- **Voice quota** — not in the backend yet (voice is phone-only anyway).
- **Guest mode** — the backend has no guest access.

## Libraries

- `react-router-dom` — about 14 pages that share one layout (`AppShell`) and
  need route guards (`RequireAuth`) and error pages.
- `@tanstack/react-query` — server state. It handles loading, error and
  caching for every request and refetches after changes, instead of each page
  writing that state by hand.
- Tests only: `vitest`, `@testing-library/react`, `@testing-library/user-event`,
  `@testing-library/jest-dom`, `jsdom`, `msw`.

There is no UI component library: components live in `src/components/`, styled
with CSS Modules and the design tokens in `src/styles/tokens.css`. There is no
streaming library either: reading Server-Sent Events takes about 30 lines.

## Sign-in and accounts

- **Sign in** (`/login`, W01): `POST /auth/login` returns a bearer token. It is
  kept in memory and in `sessionStorage` (so a reload keeps you signed in;
  closing the tab signs you out) and expires after `expires_in` seconds — the
  backend has no refresh tokens. Any `401` from an authenticated request signs
  the user out.
- **Create account** (`/register`, W02): `POST /auth/register` with **email and
  password only**, then an automatic sign-in. By team decision (26 Sep) there is
  no display name or avatar: the app shows the account by its email, and
  everyone gets the default avatar.
- **Log out** (sidebar, and W10): forgets the token in the browser. The backend
  has no logout endpoint, so the token itself stays valid until it expires.
- **Continue as guest** (`/guest`): a placeholder only — the backend has no guest
  access yet.
- Left out of W01 for now: "Forgot password?" (the backend has no password
  reset) and "Keep me signed in" (tokens last 15 minutes and there are no
  refresh tokens, so there is nothing to keep).

## Deployment

The build is a static site: `npm run build` writes `dist/`, which any static
host can serve.

1. Deploy the backend first, over HTTPS.
2. Build the web app with `VITE_API_BASE_URL` set to the backend's address
   (including `/api/v1`).
3. Serve `dist/`, and make every unknown path return `index.html` (a
   "single-page app" rewrite). Otherwise opening `/inventory` directly, or
   reloading it, gives the host's 404 page instead of the app.
4. Add the web app's address (e.g. `https://sayfridge-web.example.com`, no path)
   to the backend's `CORS_ORIGINS`. The browser blocks the app's requests to
   another origin until the backend allows it.

## Assets

`public/assets/` holds copies of the mobile app's images, served as `/assets/…`:

| Folder | Source | Note |
| --- | --- | --- |
| `icons/assistant/` | `mobile/assets/icons/assistant/` | resized to 256 px on the longest side (originals are up to 3448 px) |
| `icons/inventory/` | `mobile/assets/icons/inventory/` | copied unchanged (already 256 px) |
| `avatars/` | `mobile/assets/images/avatars/` | copied unchanged (100 px) |
