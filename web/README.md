# SayFridge Web

SayFridge 的 React Web 端，由用户页面和管理员页面共用。当前项目使用 React、TypeScript 和 Vite，后续通过路由、布局和后端权限区分不同角色。

## 本地开发 / Local development

```bash
npm install
npm run dev        # http://localhost:5173
```

Start the backend first (`../backend/README.md`). The Vite dev server forwards
every `/api` request to `http://127.0.0.1:8000` (see `vite.config.ts`), so the
browser only talks to its own origin and needs no CORS support from the backend.

To use a different backend, set `VITE_API_BASE_URL` in `.env.local`
(git-ignored), including the `/api/v1` prefix:

```bash
VITE_API_BASE_URL=https://sayfridge.example.com/api/v1
```

## 基础检查 / Checks

```bash
npm run lint
npm run build
npm test           # Vitest + Testing Library; the API is mocked with MSW
```

## Libraries

- `react-router-dom` — about 14 pages that share one layout (`AppShell`) and
  need route guards (`RequireAuth`).
- `@tanstack/react-query` — server state. It handles loading, error and
  caching for every request and refetches after changes, instead of each page
  writing that state by hand.
- Tests only: `vitest`, `@testing-library/react`, `@testing-library/user-event`,
  `@testing-library/jest-dom`, `jsdom`, `msw`.

There is no UI component library: components live in `src/components/`, styled
with CSS Modules and the design tokens in `src/styles/tokens.css`.

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
- **Log out** (sidebar): forgets the token in the browser. The backend has no
  logout endpoint, so the token itself stays valid until it expires.
- **Continue as guest** (`/guest`): a placeholder only — the backend has no guest
  access yet.
- Left out of W01 for now: "Forgot password?" (the backend has no password
  reset) and "Keep me signed in" (tokens last 15 minutes and there are no
  refresh tokens, so there is nothing to keep).

## Assets

`public/assets/` holds copies of the mobile app's images, served as `/assets/…`:

| Folder | Source | Note |
| --- | --- | --- |
| `icons/assistant/` | `mobile/assets/icons/assistant/` | resized to 256 px on the longest side (originals are up to 3448 px) |
| `icons/inventory/` | `mobile/assets/icons/inventory/` | copied unchanged (already 256 px) |
| `avatars/` | `mobile/assets/images/avatars/` | copied unchanged (100 px) |
