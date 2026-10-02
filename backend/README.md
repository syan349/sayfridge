# SayFridge Backend

The FastAPI backend for SayFridge. The current version provides health checks, local email/password authentication, B04 storage-space management, B05–B06 category queries and private item-definition management, and infrastructure for Neon PostgreSQL, SQLAlchemy 2.x ORM, and database initialization. Inventory listing, detail, stock entry, metadata/location editing, discard, and archival are implemented. ADD/CONSUME/RECONCILE quantity submission with idempotency and atomic operation history is implemented, including item-scoped and global history reads. The text Agent adds server-calculated previews, estimated actions, confirmations, and per-item recovery; Worker features remain planned.

## Documentation guide

| Question | Maintained reference |
| --- | --- |
| Product scope and future goals | [Project scope](../docs/product/README.md) |
| Current components, Agent graph, tools, memory and user intervention | [Architecture](../docs/architecture/AGENT_DESIGN.md) |
| Initial, confirmed, estimated and reconciled quantities | [Quantity rules](../docs/architecture/QUANTITY_STATE_DESIGN.md) |
| Tables, fields and constraints | [Database design](../docs/architecture/DATABASE_DESIGN.md) |
| HTTP request flow, layer ownership, services, permissions and transactions | [Backend design](../docs/architecture/BACKEND_DESIGN.md#21-http-request-lifecycle-and-layer-ownership) |
| HTTP/SSE contracts for frontend integration | [API reference](../docs/reference/API_REFERENCE.md) |
| Validation evidence and test commands | [Test index](../docs/testing/README.md) |

Startup, environment and database initialization instructions are maintained in this
README. Superseded plans are under `docs/archive/2026-09-25/` and are historical
references, not parallel implementation instructions.

## Requirements

The multimodal Agent has a six-node workflow, structured memory, independently
committed inventory actions, confirmation/resume, and SSE recovery interfaces.
See [Agent interfaces](../docs/reference/API_REFERENCE.md#9-agent-v02--chat-resume-and-recovery)
and [Agent configuration and storage](#agent-configuration-and-storage). Existing
databases require the explicit receipt-table setup before enabling Agent writes.
The same configured model reads text and inline images; no OCR service or second
model is used. See [frontend handoff](../docs/reference/AGENT_FRONTEND_INTEGRATION.md).

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
the hosting edge or gateway.

### Persistent login

Login issues a 15-minute access JWT and an opaque refresh credential. The clients
renew access automatically and retry a rejected authenticated request once. Concurrent
requests share one renewal. Network failures preserve credentials for a later retry.
Agent streams are retried only when authentication fails before the stream starts.

`POST /api/v1/auth/refresh` rotates the refresh credential. Only its SHA-256 hash is
stored in PostgreSQL. Reuse of a consumed credential revokes its session, including
all access JWTs issued for that session. `POST /api/v1/auth/logout` revokes the
session immediately; other devices retain their independent sessions. Every
protected request checks session expiry/revocation and the account's current status.

- `REFRESH_TOKEN_IDLE_DAYS=30`: renewal extends the idle deadline.
- `REFRESH_TOKEN_ABSOLUTE_DAYS=90`: renewal never extends the absolute deadline.
- Flutter saves credentials in FlutterSecureStorage and restores login on restart.
  Native device storage and Flutter Web browser storage have different protections.
- React Web keeps credentials in memory/sessionStorage for the current tab.
- Flutter waits for server logout before clearing credentials; offline logout can
  be retried. React clears its local session immediately and sends server logout;
  if that request fails, server revocation is not confirmed.
- A revoked/expired session or inactive account requires login again. Access tokens
  issued before this change keep their original short expiry; sign in again to
  obtain a persistent session. Passwords are never stored by either client.

### Migration runbook: persistent login on existing Neon

Migration `a261001_sessions` follows `a260929_defaults`. It adds `auth_session`
and `auth_refresh_credential`, their foreign keys and indexes. Existing users,
passwords, spaces, inventory and conversation data are preserved. A database reset
and demo reseed are unnecessary.

1. Merge the verified change into `main` and select its commit for release. Use
   Python 3.12 with the Backend dependencies installed. Run the commands below
   from `backend/` in that checkout.
2. Configure the ignored local `.env` or shell environment. `DATABASE_URL_DIRECT`
   must point to the same Neon branch and database as the Vercel Backend's
   `DATABASE_URL`. Use the direct, non-pooler connection for Alembic, with the
   `postgresql+psycopg://` prefix. Verify the branch/database in Neon; do not print
   or paste the full connection strings. The required JWT/CORS settings must also
   be present for Settings validation. Shell variables override `.env`.
3. Inspect the database revision and the checkout's migration head:

   ```bash
   python -m alembic current
   python -m alembic heads
   ```

   The checkout's head must be `a261001_sessions`. An existing database at
   `a260929_defaults` needs the new session migration. Earlier tracked revisions
   are upgraded through the migration chain. If the database already reports
   `a261001_sessions`, proceed to verification. If tables exist without a tracked
   revision, or the revision is unknown to the checkout, reconcile that state
   before continuing; `alembic stamp` does not create missing tables.

4. Apply the incremental business-schema migration:

   ```bash
   python -m alembic upgrade head
   ```

   This command uses `DATABASE_URL_DIRECT`. It does not seed demo accounts or
   initialize the separate Agent storage schema. Stop the release if it fails.

5. Verify the revision and structure:

   ```bash
   python -m alembic current
   python -m alembic check
   python scripts/verify_database_schema.py
   ```

   Success requires revision `a261001_sessions`, no pending ORM migration changes,
   and a successful schema verification. Confirm the two session tables are present
   in Neon's Tables view. Record the release commit, Neon branch/database, revision,
   verification outcome and execution time; exclude credentials from that record.

6. Deploy the selected Backend commit to Vercel, then deploy the updated React Web
   and Flutter clients. Keep the existing database URLs and JWT signing secret.
   `REFRESH_TOKEN_IDLE_DAYS` and `REFRESH_TOKEN_ABSOLUTE_DAYS` default to 30 and 90;
   explicit hosting values are optional unless changing those defaults.
7. Sign in again to obtain the new persistent session. Verify login returns both
   access and refresh credentials, automatic renewal preserves inventory access,
   and logout causes the old access credential to return 401. Check the deployed
   commit through `/api/v1/system/version`. Never include tokens in screenshots or
   committed acceptance reports.

#### Recovery

If migration or structural verification fails, leave the currently deployed
Backend running and resolve the reported database state before deploying the new
code. Recheck `alembic current` after a failure. Do not reset the schema or replace
business data as part of this migration.

If application deployment fails after a successful migration, redeploy the previous
application version and retain the added tables. They do not change the existing
business tables. The previous version retains its access-only authentication
behaviour; the new session-revocation behaviour returns when the new Backend is
redeployed.

The migration includes a `downgrade()` implementation. Downgrading to
`a260929_defaults` drops the two session tables and invalidates persistent sessions;
it is a separate operator action, not the routine application rollback path.

#### Fresh databases and local verification

For an empty database, use the complete initializer instead of the existing-Neon
procedure. It applies all business migrations, seeds public categories and
initializes Agent storage:

```bash
python scripts/initialize_database.py
python scripts/verify_database_schema.py
```

Run migration and session checks against the isolated test database configured by
`TEST_DATABASE_URL` or `backend/.env.test`:

```bash
python -m pytest tests/test_database_initialization_postgres.py tests/test_persistent_auth.py -v
```

Local isolated-database and browser tests have passed. No online Neon migration
or hosted deployment has been performed for this change. Cookie login, password
recovery and MFA are separate from these endpoints.

The [Security and Privacy review (8.1–8.6)](../docs/security/README.md) records focused
verification and remaining risks. Runtime SQLAlchemy exceptions hide bound SQL
parameters; this does not replace sanitizing driver messages or application logs.

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

Keep the migration history, ORM and API contracts together. Existing databases
are upgraded through Alembic; use the [persistent-login migration runbook](#migration-runbook-persistent-login-on-existing-neon) for this release.
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

### Migration, seed, reset, and restore

These operations have separate purposes and must not be treated as interchangeable:

| Operation | Command/process | Effect |
| --- | --- | --- |
| Migration | `python scripts/initialize_database.py` | Applies `alembic upgrade head` to an empty/current database and initializes the separate Agent schema. |
| Required seed | Included in `initialize_database.py` | Idempotently adds the 25 public item categories required by the application. |
| Demo seed | `scripts/manage_demo_data.py seed` | Explicitly adds non-production acceptance accounts and sample business data. |
| Demo reset | `scripts/manage_demo_data.py reset` | Removes only deterministic demo rows; it does not drop the schema or categories. |
| Restore | Neon branch restore/recreation or an approved database backup | Recovers an environment; it is an operator action, not application startup behavior. |

The optional demo dataset contains 11 accounts (the five configured team emails,
five virtual users, and one virtual administrator), 33 storage spaces, 25 public
item definitions, 77 inventory items, and 66 inventory operations. It covers
in-stock, estimated, empty, expired, discarded, archived, notes, expiry dates,
and ADD/CONSUME/RECONCILE history. It is not part of application startup and must
never be run against production.

Set two uncommitted operator passwords, then explicitly identify and confirm the
non-production target:

```bash
export DEMO_USER_PASSWORD='replace-with-shared-demo-user-password'
export DEMO_ADMIN_PASSWORD='replace-with-shared-demo-admin-password'

python scripts/manage_demo_data.py seed \
  --target predeploy \
  --confirm SEED-DEMO-DATA
python scripts/manage_demo_data.py check --target predeploy
```

The seed is repeatable. Existing accounts with one of the configured email
addresses retain their ID, password, role, and data; incompatible account or
catalog records stop the entire transaction instead of being overwritten.

Distribute the real non-production passwords through a secure team channel; do
not commit them to this repository or reuse them in production.
To update existing deterministic demo accounts without deleting their inventory,
spaces, or operation history, run:

```bash
python scripts/manage_demo_data.py seed \
  --target predeploy \
  --confirm SEED-DEMO-DATA \
  --rotate-passwords
```

To remove deterministic demo rows while retaining the required categories:

```bash
python scripts/manage_demo_data.py reset \
  --target predeploy \
  --confirm RESET-DEMO-DATA
```

The reset preserves pre-existing accounts and definitions. A seeded account is
also preserved if it has acquired non-demo spaces, private definitions,
conversations, or Agent receipts, avoiding cascading deletion of later work.

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

- [Authentication, storage-space, and catalog API manual](../docs/reference/API_REFERENCE.md)
- Optional local Postman collection: `docs/postman/SayFridge_Auth.postman_collection.json` (not included in the planned documentation commit; see the API manual for manual requests)
- [B01–B03 authentication test results](../docs/testing/reports/B01-B03_AUTH_TEST_RESULTS.md)
- [B04 storage-space test results](../docs/testing/reports/B04_STORAGE_SPACES_TEST_RESULTS.md)
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

### Database environments and acceptance

Database purposes are intentionally separate. Local development uses the ignored
application `.env`; backend tests and GitHub CI use a direct `_test` database;
future end-to-end CI must use a direct `_e2e` database configured from
`.env.e2e.example`; Vercel/manual acceptance uses the dedicated Neon predeploy
branch. Disposable test or E2E jobs must never reset the predeploy database.

The reusable target guards, read-only evidence command, and transaction/rollback
acceptance matrix are documented in
[Database isolation and acceptance evidence](../docs/testing/reports/DATABASE_ACCEPTANCE.md).
The transaction matrix can be run independently with:

```bash
python -m pytest -v -m database_acceptance --strict-markers
```


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
See [API reference](../docs/reference/API_REFERENCE.md#7-inventory-quantity-operations-and-history--b10b12-and-b14) for requests
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

The intake step records every stock request before conversational replies. Clear
new products and explicitly named new spaces are created automatically with the
stock transaction; missing details remain resumable items. Image review remains
required. Estimates execute directly unless the user explicitly requests confirmation. Run the first-purchase regression with
`python -m pytest -q tests/test_agent_stock_entry_postgres.py`; the opt-in live-model
suite also covers English/Chinese purchases and ambiguous storage locations.

Multimodal input requires Pillow from requirements.txt and a configured model/API
that supports image content blocks together with tool calls. Requests accept at
most 4 JPEG/PNG/WebP still images, 3 MiB decoded each, 8 MiB combined, 20 million
pixels each. The ASGI layer caps JSON bodies at 12 MiB before validation, including
chunked uploads. Configure reverse proxies to allow this size (base64 adds about
one third) or explicitly advertise their smaller deployment limit. Client-side
HEIC conversion/compression is required. Do not log request bodies.

Images remain in PostgreSQL conversation checkpoints with no separate expiry or
automatic cleanup. Allow for database/backup growth and increasing model context
cost as image history grows. Existing Agent/checkpoint and action-receipt storage must already exist. The
quantity/default-space update additionally requires migration `a260929_defaults`.
No application startup DDL is added. Full chat/image history retrieval is not
provided by the recovery endpoint.

Run image-specific checks with:

```powershell
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_messages.py tests/test_agent_multimodal_workflow.py tests/test_agent_multimodal_postgres.py
$env:AGENT_LIVE_MODEL='1'
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_multimodal_live.py
```


## Quantity, defaults, and continuous chat

Apply incremental Alembic revision `a260929_defaults` after checking the target
schema. Its ONLY changes are `storage_space.is_default`, an active-default check,
and a unique per-user default index. All quantity columns remain NUMERIC(12,3).
There is no startup DDL, inventory backfill, or remote migration implied by code changes.

A successful login ensures a default in the same transaction before issuing a
token. With no default, choose the earliest active space (created_at, then ID),
or create “默认空间” of type OTHER. `POST /api/v1/storage-spaces/{id}/default`
changes it. Archiving a default atomically ensures a replacement. Restoring an old
space does not override a current default. Space mutations lock user then space.

New stock uses an explicitly named space, otherwise the default. Consumption
searches actual inventory across spaces; ambiguous batches still require an answer.
`/agent/chat` now accepts supplements, edits, confirmations and cancellations while
work is pending; `/resume` remains supported. Queries and independent new requests
preserve suspended work. Clients must retain request IDs when retrying.

Quantity operations first convert the effective balance to the current input unit,
then add/subtract. Fractions without a new unit keep the current unit. Initial
entry fields never change. A cross-dimension conversion uses the current explicit
user basis, otherwise applicable user memory, otherwise a labeled model estimate.
An estimated balance stays estimated until an explicit physical stocktake.

Cross-dimension whole-count estimates round to integer balances (ROUND_HALF_UP),
including preview, saved stock and Agent feedback. Explicit partial-item changes
first use a rounded whole-count baseline, then apply the partial amount. Exact
same-unit partial stock is preserved. Physical quantities round only at persistence
to the existing three-decimal precision; there is no secondary hidden balance.
Unsupported tiny changes/positive remainders return a quantity error rather than
silently deleting stock. Relative non-integral whole counts ask the actual count.

A new conversion relationship is saved idempotently in existing user memory at
execution time, after any required approval and before stock writes. Memory failure
leaves stock unchanged and the item resumable. If memory succeeds but the stock
transaction fails, the relationship remains reusable; it is not proof of a stock
change. User instructions not to save memory are honored. Receipts remain ordinary
business receipts, not a memory synchronization queue. Older unexecuted quantity
previews are re-prepared; committed receipts only replay their actual results.

Model budgeting applies to intake, continuations, tools and retry calls:

| Setting | Default |
| --- | --- |
| AGENT_CONTEXT_TRIGGER | 80000 |
| AGENT_CONTEXT_TARGET | 40000 |
| AGENT_CONTEXT_LIMIT | 160000 |
| AGENT_MODEL_CONTEXT_LIMIT | 160000 |
| AGENT_OUTPUT_TOKENS | 8000 |

Set MODEL_CONTEXT_LIMIT to the provider's supported context size, below 275000.
The budget uses the configured model's message/image token meter, a 25% framing
allowance, conservative tool-schema/opaque-response accounting, and a 4096-token
safety reserve. Unknown meters fail closed. Required input plus reserved output
must fit the smaller limit; increasing settings cannot disable the 275k cap.
Compaction keeps up to eight complete recent turns plus protected image evidence,
a bounded historical excerpt summary, and separately persisted work/receipt state.
Required task content that still cannot fit returns CONTEXT_BUDGET_EXCEEDED without
calling the model. `agent_context_compacted` logs before/after estimates.

Acceptance suites: `test_agent_quantity_context.py`, `test_agent_chat_continuation.py`,
`test_agent_defaults_postgres.py`; optional real-model quantity cases are in
`test_agent_live_model.py` and require AGENT_LIVE_MODEL=1 and TEST_DATABASE_URL.

### Category correction and automatic stock expiry (issues 158, 145, 161)

Agent stock proposals select a real catalog category. Correcting an existing
private definition requires confirmation because its older stock shares that
category. Public definitions remain unchanged; an approved conflict creates a
private definition. Category correction, stock and receipt are one transaction.

All new-stock entry points preserve explicit expiry dates, calculate stated shelf
lives with a valid starting date, or reuse the configured Agent model to estimate
missing dates before taking write locks. Model failure still saves stock and returns
a creation warning. The Agent speaks the warning; manual clients can consume the
additive `warnings` response field. Ordinary reads are unchanged. No database
columns, migration, historical backfill, second model or background job is added.

Before pushing a release, verify the deployment's actual remote database target,
Alembic revision, required schema and active catalog using read-only checks. Local
tests or committed code do not prove a remote database is ready or a deployment is
running. This change requires no schema migration when the existing schema matches.

Focused acceptance (use a separate `TEST_DATABASE_URL` ending in `_test`):

```powershell
python -m pytest -q tests/test_inventory_expiry.py tests/test_agent_stock_policy_postgres.py tests/test_agent_quantity_context.py
# Explicit opt-in to real model costs, with writes confined to disposable test schemas:
$env:AGENT_LIVE_MODEL = '1'
python -m pytest -q tests/test_agent_stock_policy_live.py
```
