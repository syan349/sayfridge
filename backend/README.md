# SayFridge Backend

The FastAPI backend for SayFridge. The current version provides health checks, local email/password authentication, B04 storage-space management, B05–B06 category queries and private item-definition management, and infrastructure for Neon PostgreSQL, SQLAlchemy 2.x ORM, and database initialization. Inventory listing, detail, stock entry, metadata/location editing, discard, and archival are implemented. ADD/CONSUME/RECONCILE quantity submission with idempotency and atomic operation history is implemented, including item-scoped and global history reads. The text Agent adds server-calculated previews, estimated actions, confirmations, and per-item recovery; Worker features remain planned.

## Documentation guide

| Question | Maintained reference |
| --- | --- |
| Product scope and future goals | [Project scope](../docs/PROJECT_SCOPE_BILINGUAL.md) |
| Current components, Agent graph, tools, memory and user intervention | [Architecture](../docs/ARCHITECTURE.md) |
| Initial, confirmed, estimated and reconciled quantities | [Quantity rules](../docs/QUANTITY_STATE_DESIGN.md) |
| Tables, fields and constraints | [Database design](../docs/DATABASE_DESIGN.md) |
| HTTP request flow, layer ownership, services, permissions and transactions | [Backend design](../docs/BACKEND_DESIGN.md#21-http-request-lifecycle-and-layer-ownership) |
| HTTP/SSE contracts for frontend integration | [API reference](../docs/API_REFERENCE.md) |
| Validation evidence and test commands | [Test index](../docs/testing/README.md) |

Startup, environment and database initialization instructions are maintained in this
README. Superseded plans are under `docs/archive/2026-09-25/` and are historical
references, not parallel implementation instructions.

## Requirements

The multimodal Agent has a six-node workflow, structured memory, independently
committed inventory actions, confirmation/resume, and SSE recovery interfaces.
See [Agent interfaces](../docs/API_REFERENCE.md#9-agent-v02--chat-resume-and-recovery)
and [Agent configuration and storage](#agent-configuration-and-storage). Existing
databases require the explicit receipt-table setup before enabling Agent writes.
The same configured model reads text and inline images; no OCR service or second
model is used. See [frontend handoff](../docs/AGENT_FRONTEND_INTEGRATION.md).

- Python 3.12

## Run locally on Windows

Run the following commands from the `backend` directory after configuring `.env` as described below:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn app.main:app --reload
```

Once the server starts, the following endpoints are available:

- Health check: `GET http://127.0.0.1:8000/health`
- Deployed version: `GET http://127.0.0.1:8000/api/v1/system/version`
- Register: `POST http://127.0.0.1:8000/api/v1/auth/register`
- Log in: `POST http://127.0.0.1:8000/api/v1/auth/login`
- Current user: `GET http://127.0.0.1:8000/api/v1/auth/me`
- Storage spaces: `GET/POST http://127.0.0.1:8000/api/v1/storage-spaces`
- Space detail/edit: `GET/PATCH http://127.0.0.1:8000/api/v1/storage-spaces/{id}`
- Space archive/restore: `POST http://127.0.0.1:8000/api/v1/storage-spaces/{id}/archive` or `/restore`
- Categories: `GET http://127.0.0.1:8000/api/v1/item-categories`
- Item definitions: `GET/POST http://127.0.0.1:8000/api/v1/item-definitions`; detail/PATCH and archive/restore under `/{id}`
- Inventory: `GET/POST http://127.0.0.1:8000/api/v1/inventory-items`; detail/PATCH under `/{id}`
- Add to existing inventory: `POST http://127.0.0.1:8000/api/v1/inventory-items/{id}/operations` (ADD/AMOUNT; Idempotency-Key required)
- Consume inventory: the same operations endpoint (CONSUME with AMOUNT or FRACTION)
- Confirm a physical stocktake: the same operations endpoint (RECONCILE/AMOUNT)
- Discard in-stock inventory: `POST http://127.0.0.1:8000/api/v1/inventory-items/{id}/discard`
- Archive in-stock or empty inventory: `POST http://127.0.0.1:8000/api/v1/inventory-items/{id}/archive`
- Item operation history: `GET http://127.0.0.1:8000/api/v1/inventory-items/{id}/operations`
- Global operation history: `GET http://127.0.0.1:8000/api/v1/inventory-operations`
- Operation detail: `GET http://127.0.0.1:8000/api/v1/inventory-operations/{id}`
- Swagger UI: `http://127.0.0.1:8000/docs`
- ReDoc: `http://127.0.0.1:8000/redoc`
- OpenAPI JSON: `http://127.0.0.1:8000/openapi.json`

## Authentication settings

`APP_VERSION` identifies the release shown by OpenAPI and the version endpoint;
it defaults to `0.1.0`. Vercel automatically supplies `VERCEL_GIT_COMMIT_SHA` for
the same endpoint. Other providers may set `APP_COMMIT_SHA` to a 7–40 character
hexadecimal Git commit. These values are public deployment metadata, not secrets.

- `JWT_SECRET_KEY`: HS256 signing secret with at least 32 characters. Store it only in the local or deployment environment.
- `ACCESS_TOKEN_EXPIRE_MINUTES`: Access token lifetime in minutes; defaults to `15`.
- `LOGIN_RATE_LIMIT_ATTEMPTS`: Login attempts allowed for one client/account pair; defaults to `5`.
- `LOGIN_RATE_LIMIT_WINDOW_SECONDS`: Sliding login-limit window; defaults to `60` seconds.

Authentication supports local email/password accounts and short-lived Bearer access
tokens. A successful login clears that client/account limit. The application limit is
process-local, so a multi-instance deployment must also configure a shared limit at
the hosting edge or gateway. Refresh tokens, server-side sessions, a logout endpoint,
immediate token revocation, third-party login, email verification, password recovery,
and MFA are not currently available. Clients log out by deleting their token; an
issued token otherwise remains usable until expiry unless the account is suspended,
disabled, or deleted.

## Web browser access (CORS)

Set `CORS_ORIGINS` to the exact browser origins allowed to call the API. The value
is a JSON list; the local template allows Vite at `http://localhost:5173`:

```dotenv
CORS_ORIGINS=["http://localhost:5173"]
```

The backend permits browser requests using `GET`, `POST`, `PATCH`, and `OPTIONS`
with the `Authorization`, `Content-Type`, and `Idempotency-Key` headers. It uses
Bearer tokens without cookie credentials. Wildcards, URL paths, and unlisted
origins are rejected; add the deployed Web origin explicitly in its environment.

## Development database setup

Copy `.env.example` to `.env` and enter real connection details only in the local file:

- `DATABASE_URL`: Neon pooled connection used by FastAPI at runtime.
- `DATABASE_URL_DIRECT`: Neon direct connection used by Alembic.

Both URLs must use the `postgresql+psycopg://` prefix. Git ignores `.env`; never put real connection strings or passwords in code, migrations, or documentation.

Before the first backend release, maintain the latest table definition, ORM,
and API contracts together; record structural changes in the design handbook.
Incremental migration histories and deployment rollback procedures are not required.
Initialize a fresh database completely with:

```bash
python scripts/initialize_database.py
```

This repeatable command applies the Alembic schema, seeds the 25 public categories,
initializes the isolated Agent checkpoint/store schema, and verifies the result.
It must run before FastAPI uses an empty database and never runs implicitly during
application startup. Editing the initial migration does not update an already
initialized database; existing databases must still be reviewed and synchronized
explicitly.

Verify the complete process against the configured isolated test database with:

```bash
python -m pytest tests/test_database_initialization_postgres.py -v --strict-markers
```

For an existing Neon or PostgreSQL environment, run the read-only structural check:

```bash
python scripts/verify_database_schema.py
python scripts/setup_agent_storage.py --check
```

The first command compares the business schema with the current ORM tables,
columns, primary/foreign/unique/check constraints, and indexes. The second checks
the separate LangGraph Agent schema. Neither command creates, alters, seeds, or
deletes database objects. A successful migration of a new empty database is also
covered by `test_database_initialization_postgres.py` and included in core CI.

## Post-deployment smoke test

After deploying the Backend and initializing its database, run the smoke test from
`backend/` against the deployed HTTPS origin:

```bash
export SMOKE_BASE_URL="https://your-backend.example.com"
export SMOKE_USER_EMAIL="deployment-smoke@example.com"
export SMOKE_USER_PASSWORD="replace-with-a-strong-dedicated-password"
export SMOKE_ADMIN_EMAIL="deployment-smoke-admin@example.com"
export SMOKE_ADMIN_PASSWORD="replace-with-the-existing-admin-password"
python scripts/smoke_deployment.py
```

Use dedicated deployment-test accounts. The ordinary account is registered on its
first run and reused afterward; the administrator account must already exist with
the `ADMIN` role. Keep all five values in the operator's secret store or protected
CI secrets. They are test-runner settings and must not be added to the Vercel
application environment or committed files.

The script verifies `/health`, deployed version/commit, registration, login/current identity, inventory
list/detail/create behavior, the expiry summary, and an administrator account
query. It creates at most one named private space, item definition and in-stock
item for the dedicated user, then reuses them on later runs. It never deletes
records, changes roles, modifies account status or prints access tokens/passwords.
Any missing endpoint, unexpected status, invalid response, database initialization
problem or insufficient administrator permission makes the command exit nonzero.

The smoke runner's offline contract tests are part of core PR CI:

```bash
python -m pytest tests/test_deployment_smoke.py -v --strict-markers
```


## Tests

```powershell
python -m pytest
```

## B01–B09 local startup and Postman

On macOS / Linux, create an environment with Python 3.12 from the `backend` directory. Skip environment creation if `.venv` already exists:

```bash
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

If you use an existing Conda environment, activate it and use `python` instead of `.venv/bin/python`. Each team member should use their own `.env` and must not commit real credentials.

- [Authentication, storage-space, and catalog API manual](../docs/API_REFERENCE.md)
- Optional local Postman collection: `docs/postman/SayFridge_Auth.postman_collection.json` (not included in the planned documentation commit; see the API manual for manual requests)
- [B01–B03 authentication test results](../docs/testing/B01-B03_AUTH_TEST_RESULTS.md)
- [B04 storage-space test results](../docs/testing/B04_STORAGE_SPACES_TEST_RESULTS.md)
- [Backend test results index](../docs/testing/README.md)

## One test suite for local development and CI

Run the full suite from `backend` with the same command on macOS and GitHub Actions:

```bash
python -m pytest -v
```

The suite contains database-free scenarios and scenarios that use real PostgreSQL fixtures. Current counts are listed in the [test index](../docs/testing/README.md). There is no fake database session. Some invalid requests are rejected before executing SQL, but their API tests use the same real database setup. Uvicorn does not need to be running: pytest loads the ASGI application directly.

- Local development: copy `.env.test.example` to `.env.test` and supply the direct URL for your isolated Neon test database (currently `sayfridge_auth_test`).
- GitHub Actions: the workflow starts a disposable PostgreSQL 18 service and supplies `TEST_DATABASE_URL` through its environment. It does not connect to Neon or require Neon credentials.
- An existing process environment variable takes precedence over `.env.test`. Keep the PostgreSQL major versions aligned between local testing and CI.

Never commit `.env` or `.env.test`. Commit only the templates and workflow. The CI password is a disposable test value, not a Neon credential.

Database tests require `postgresql+psycopg://`, a database name ending in `_test`, and a direct connection (not a Neon pooler). Missing configuration fails the selected database tests instead of silently skipping them. The application `.env` is never used as a fallback.

Each database test migrates a fresh random `auth_test_*` schema using Alembic, performs real database operations, and drops only its own schema in teardown, including after normal assertion failures. Forced termination or a network failure during cleanup may leave a schema behind. Postman data is outside this cleanup process.

To select a subset explicitly:

```bash
# Database-free scenarios (inspect the current selection with --collect-only)
python -m pytest -v -m "not postgres"

# Scenarios with real PostgreSQL fixtures
python -m pytest -v -m postgres
```

Automatic CI for pull requests targeting `main` and pushes to `main` runs the
high-priority scenarios marked `ci`. Manual workflow dispatch runs the full suite.
Both use the same test definitions and temporary PostgreSQL service; there is no
separate CI implementation of a test. The required job remains `test-job`, and
JUnit reports are uploaded even on failure.

```bash
# Fast core regression: the same selection as automatic CI
python -m pytest -v -m ci

# Full local regression: no tests are excluded by default
python -m pytest -v

# Inspect the selection without executing tests or connecting to PostgreSQL
python -m pytest --collect-only -q -m ci
```

See the [CI selection policy](../docs/testing/README.md#ci-selection-policy) for
selected scenarios and maintenance rules. The core subset reduces test execution,
not the fixed time needed for GitHub runner setup and dependency installation.


## Backend organization

Routes parse HTTP inputs, obtain the authenticated user/session, and translate
business errors into HTTP responses. Feature services contain database queries,
business rules, and write transaction boundaries. B04 uses
`app/services/storage_spaces.py`; B05–B06 use `app/services/catalog.py`. Request and
response contracts live in `app/schemas/business.py`. B04–B06 add no schema migration. Public categories must be initialized through an approved setup or administrator process before creating private definitions; these APIs do not seed shared databases.

Run B04 tests alone with:

```bash
python -m pytest tests/test_storage_spaces_api.py tests/test_storage_spaces_postgres.py -v
```


## Inventory setup and verification

Inventory uses nullable TEXT `inventory_item.notes`, included in the latest initial
schema and ORM. Local schema definitions do not establish remote deployment status.

The 25 public categories and Agent classification guidance share one configuration:
`app/core/category_catalog.py`. The reviewed seed SQL is
`scripts/sql/seed_item_categories.sql`; `python scripts/render_category_seed.py`
prints SQL for review without connecting to a database. This is not a database
synchronization service. The fresh-database initializer applies the reviewed seed
automatically; existing databases still require review before corrections are
applied.

The inventory routes use `app/schemas/inventory.py` and `app/services/inventory.py`.
An owned active space and visible active definition/category must exist before
stock entry. No shared seed data is inserted automatically.

Run inventory tests alone with:

```bash
python -m pytest -v tests/test_inventory_api.py tests/test_inventory_postgres.py
```

These tests use the existing isolated test database configuration and initialize the latest structure
within disposable test schemas. They do not need Uvicorn running.


## Inventory quantity operations and item history

B10–B12 use the existing inventory_item and inventory_operation tables. No schema
change or incremental migration is introduced. Request/response schemas are in
`app/schemas/inventory_operations.py`; the transaction is in `app/services/inventory.py`,
and pure calculation helpers remain in `app/services/inventory_quantities.py`.
See [API reference](../docs/API_REFERENCE.md#7-inventory-quantity-operations-and-history--b10b12-and-b14) for requests
and retry behavior. Run the complete addition tests from backend:

```bash
python -m pytest -v tests/test_inventory_quantities.py tests/test_inventory_additions.py tests/test_inventory_additions_postgres.py
```

Temporary B10 exercise files are not required. Tests use the same isolated
PostgreSQL configuration as the existing test suite, with no application data writes.

Run the complete consumption tests from backend:

```bash
python -m pytest -v tests/test_inventory_consumption*.py
```

Run the complete reconciliation tests from backend:

```bash
python -m pytest -v tests/test_inventory_reconciliation*.py
```

Run the inventory state-action tests from backend:

```bash
python -m pytest -v tests/test_inventory_discard.py tests/test_inventory_archive.py
```

Run the operation history tests from backend:

```bash
python -m pytest -v tests/test_inventory_item_history.py tests/test_inventory_operation_history.py
```

Run the implemented B15 batch-create tests from backend:

```bash
python -m pytest -v tests/test_inventory_batch_create.py --strict-markers
```

Run the implemented B15 batch-move tests from backend:

```bash
python -m pytest -v tests/test_inventory_batch_move.py --strict-markers
```

Run the implemented B15 batch-archive tests from backend:

```bash
python -m pytest -v tests/test_inventory_batch_archive.py --strict-markers
```

Run the B22 expiry-summary tests from backend:

```bash
python -m pytest -v tests/test_inventory_expiry_summary.py --strict-markers
```

Run the B25 administrator account-management tests from backend:

```bash
python -m pytest -v tests/test_admin_users.py --strict-markers
```

## Agent configuration and storage

Python 3.12 and backend requirements are required. Agent persistence uses
AGENT_DATABASE_URL when nonempty, otherwise DATABASE_URL_DIRECT. Keep credentials
only in local/deployment secrets. AGENT_WORKFLOW_STEP_LIMIT defaults to 128 and is
the six-node step budget; legacy AGENT_RECURSION_LIMIT does not control this workflow.

On Windows, psycopg requires a Selector event loop. To run without reload with the
installed Uvicorn version, use:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --loop asyncio:SelectorEventLoop
```

The existing reload development command also selects a compatible loop. Linux
can use the normal Uvicorn asyncio loop.

For an existing database, explicitly check both storage layers:

```powershell
.\.venv\Scripts\python.exe scripts/setup_agent_storage.py --check
.\.venv\Scripts\python.exe scripts/setup_agent_actions.py --check
```

The receipt-table script exits nonzero if missing or structurally incompatible.
After checking the intended environment, `--initialize` prompts for INITIALIZE and
adds only the receipt table. It does not run automatically on application startup.
Fresh development/test schemas receive the table through the updated initial schema.
Applying these local changes does not synchronize an existing remote database.

Run `python -m pytest` against a separately configured TEST_DATABASE_URL ending in
`_test`. Fixtures own disposable schemas. Live model checks are opt-in:

```powershell
$env:AGENT_LIVE_MODEL='1'
.\.venv\Scripts\python.exe -m pytest tests/test_agent_live_model.py -q
```

Live checks use synthetic inventory in the isolated test database and incur model
API usage; they never use the production inventory connection for test actions.

Multimodal input requires Pillow from requirements.txt and a configured model/API
that supports image content blocks together with tool calls. Requests accept at
most 4 JPEG/PNG/WebP still images, 3 MiB decoded each, 8 MiB combined, 20 million
pixels each. The ASGI layer caps JSON bodies at 12 MiB before validation, including
chunked uploads. Configure reverse proxies to allow this size (base64 adds about
one third) or explicitly advertise their smaller deployment limit. Client-side
HEIC conversion/compression is required. Do not log request bodies.

Images remain in PostgreSQL conversation checkpoints with no separate expiry or
automatic cleanup. Allow for database/backup growth and increasing model context
cost as image history grows. There is no new business table or migration in this
change; existing Agent/checkpoint and action-receipt storage must already exist.
No application startup DDL is added. Full chat/image history retrieval is not
provided by the recovery endpoint.

Run image-specific checks with:

```powershell
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_messages.py tests/test_agent_multimodal_workflow.py tests/test_agent_multimodal_postgres.py
$env:AGENT_LIVE_MODEL='1'
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_multimodal_live.py
```
