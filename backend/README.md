# SayFridge Backend

FastAPI/Python 3.12 backend. Run commands below from `backend/`.
The [project README](../README.md) is the overall entry point.

## Local setup

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

On Windows:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Set `DATABASE_URL` (runtime pooled connection), `DATABASE_URL_DIRECT` (direct
connection), `JWT_SECRET_KEY` (at least 32 characters), and `CORS_ORIGINS` (JSON
list of exact browser origins) in the ignored `.env`. Both business URLs use
`postgresql+psycopg://`. Keep credentials out of committed files.

## Development database setup

```bash
python scripts/initialize_database.py
python scripts/verify_database_schema.py
python scripts/setup_agent_storage.py --check
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Initialization applies Alembic, seeds the 25 required public categories, initializes
the separate Agent schema and verifies both layers. It is repeatable and runs
explicitly before the application, not at API startup. Demo accounts are optional.
For existing Neon upgrades, demo seed/reset, acceptance records and recovery, use
[the database runbook](../docs/delivery/README.md#database-initialization-and-migration).

Local health: <http://127.0.0.1:8000/health>. Swagger: <http://127.0.0.1:8000/docs>.
Endpoint contracts are maintained only in the [API reference](../docs/reference/API_REFERENCE.md).

## Category and inventory migration

This branch adds user-owned categories and a category override for an individual
stock batch. Apply migration `a261002_categories` before deploying the matching
backend and clients. From `backend/`, using the intended database configuration:

```bash
python -m alembic upgrade head
python scripts/verify_database_schema.py
```

The migration retains existing categories and stock facts. Existing categories
remain public; existing batches initially have no category override. Never reset
shared inventory to apply this upgrade. Local test results do not establish the
migration or deployment status of a shared database.

Category creation/reuse, alphabetical ordering and batch-specific editing are
defined in the [API reference](../docs/reference/API_REFERENCE.md#4-categories--b05).
Ownership, indexes and category fallback are documented in
[Database Design](../docs/architecture/DATABASE_DESIGN.md#item_category).

## Authentication settings

`JWT_SECRET_KEY` is the shared signing secret. `ACCESS_TOKEN_EXPIRE_MINUTES`
defaults to 15. `LOGIN_RATE_LIMIT_ATTEMPTS=5` and
`LOGIN_RATE_LIMIT_WINDOW_SECONDS=60` configure the process-local login limiter.
`APP_VERSION` defaults to 0.1.0. `APP_COMMIT_SHA` or Vercel's Git SHA supplies the
public version endpoint; these metadata values are not credentials.

### Persistent login

Access JWTs use fixed HS256 signature verification and required `sub`, `type`,
`iat` and `exp` claims. The authentication dependency decodes identity; session
validation decodes again to obtain `sid`. Tokens without `sid` retain their
original expiry as the legacy compatibility path. The current branch does not
issue or explicitly validate issuer/audience claims.

Refresh credentials rotate once per use. PostgreSQL stores their SHA-256 hashes.
Default idle/absolute session lifetimes are `REFRESH_TOKEN_IDLE_DAYS=30` and
`REFRESH_TOKEN_ABSOLUTE_DAYS=90`. Replay and server logout revoke the device
session; protected requests also check session state and current account status.
Clients share concurrent renewal and retry authentication once. Passwords are
not saved by clients. Exact responses belong to the [authentication contract](../docs/reference/API_REFERENCE.md#2-authentication--b01b03).

## Agent configuration and storage

The configured OpenAI-compatible model handles text and images with tool calls.
Set `AGENT_API_KEY`, `AGENT_MODEL` and `AGENT_API_BASE` using `.env.example`.
`AGENT_DATABASE_URL`, when supplied, overrides `DATABASE_URL_DIRECT` for Agent
persistence; use a direct connection. `AGENT_DATABASE_SCHEMA` defaults to `agent`.
`AGENT_WORKFLOW_STEP_LIMIT` defaults to 128. Current model, timeout, retry, pool
and context defaults are defined in `app/agents/model.py` and `persistence.py`.

```bash
python scripts/setup_agent_storage.py --check
python scripts/setup_agent_actions.py --check
```

The second command checks the receipt table. Normal upgrades use Alembic. The
receipt compatibility script's explicit `--initialize` mode adds only that table
after target confirmation; it is not a substitute for the migration sequence.
On Windows, run without reload using a psycopg-compatible Selector loop:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --loop asyncio:SelectorEventLoop
```

The reload development command selects a compatible loop. Linux uses normal asyncio.
Image request limits and formats are owned by the [API reference](../docs/reference/API_REFERENCE.md#multimodal-messages-and-frontend-contract);
[security and privacy](../docs/security/README.md) explains storage and third parties.

## Checks

Copy `.env.test.example` to ignored `.env.test`; configure a direct
`TEST_DATABASE_URL` with database name ending `_test`. Fixtures own temporary
schemas. Commands do not require a running Uvicorn server.

```bash
python -m pytest -v -m ci --strict-markers
python -m pytest -v --strict-markers
python -m pytest --collect-only -q -m ci --strict-markers
```

Live-model verification is an explicit cost-bearing opt-in against the isolated test database:

```bash
AGENT_LIVE_MODEL=1 python -m pytest -q tests/test_agent_live_model.py
```

For test setup, E2E, CI triggers and reports, use [Testing Strategy and Evidence](../docs/testing/README.md).
For deployment and smoke checks, use [Build and Deployment](../docs/delivery/README.md).
For code boundaries, use [Backend Design](../docs/architecture/BACKEND_DESIGN.md).
