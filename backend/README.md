# SayFridge Backend

The FastAPI backend for SayFridge. The current version provides health checks, local email/password authentication, B04 storage-space management, and infrastructure for Neon PostgreSQL, SQLAlchemy 2.x ORM, and Alembic migrations. Inventory CRUD, Agent, and Worker features have not been implemented yet.

## Requirements

- Python 3.11

## Run locally on Windows

Run the following commands from the `backend` directory after configuring `.env` as described below:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn app.main:app --reload
```

Once the server starts, the following endpoints are available:

- Health check: `GET http://127.0.0.1:8000/health`
- Register: `POST http://127.0.0.1:8000/api/v1/auth/register`
- Log in: `POST http://127.0.0.1:8000/api/v1/auth/login`
- Current user: `GET http://127.0.0.1:8000/api/v1/auth/me`
- Storage spaces: `GET/POST http://127.0.0.1:8000/api/v1/storage-spaces`
- Space detail/edit: `GET/PATCH http://127.0.0.1:8000/api/v1/storage-spaces/{id}`
- Space archive/restore: `POST http://127.0.0.1:8000/api/v1/storage-spaces/{id}/archive` or `/restore`
- API documentation: `http://127.0.0.1:8000/docs`

## Authentication settings

- `JWT_SECRET_KEY`: HS256 signing secret with at least 32 characters. Store it only in the local or deployment environment.
- `ACCESS_TOKEN_EXPIRE_MINUTES`: Access token lifetime in minutes; defaults to `15`.

Authentication supports local email/password accounts and short-lived Bearer access tokens. Refresh tokens, server-side sessions, logout, third-party login, email verification, password recovery, and MFA are not currently available.

## Database configuration and migrations

Copy `.env.example` to `.env` and enter real connection details only in the local file:

- `DATABASE_URL`: Neon pooled connection used by FastAPI at runtime.
- `DATABASE_URL_DIRECT`: Neon direct connection used by Alembic.

Both URLs must use the `postgresql+psycopg://` prefix. Git ignores `.env`; never put real connection strings or passwords in code, migrations, or documentation.

```powershell
# Show the current migration revision
alembic current

# Apply all migrations
alembic upgrade head

# Check for model/database differences not yet covered by migrations
alembic check
```

The initial migration creates the eight tables specified in the design document. Subsequent model changes must include a new migration committed alongside the code. Do not manually change tables in the Neon SQL Editor.

## Tests

```powershell
python -m pytest
```

## B01–B04 local startup and Postman

On macOS / Linux, create an environment with Python 3.11 from the `backend` directory. Skip environment creation if `.venv` already exists:

```bash
python3.11 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

If you use an existing Conda environment, activate it and use `python` instead of `.venv/bin/python`. Each team member should use their own `.env` and must not commit real credentials.

- [Authentication and storage-space API manual](../docs/API_REFERENCE.md)
- Optional local Postman collection: `docs/postman/SayFridge_Auth.postman_collection.json` (not included in the planned documentation commit; see the API manual for manual requests)
- [B01–B03 authentication test results](../docs/testing/B01-B03_AUTH_TEST_RESULTS.md)
- [B04 storage-space test results](../docs/testing/B04_STORAGE_SPACES_TEST_RESULTS.md)
- [Backend test results index](../docs/testing/README.md)

## One test suite for local development and CI

Run all 115 scenarios from `backend` with the same command on macOS and GitHub Actions:

```bash
python -m pytest -v
```

The suite contains 11 database-free scenarios and 104 scenarios that use real PostgreSQL fixtures. There is no fake database session. Some invalid requests are rejected before executing SQL, but their API tests use the same real database setup. Uvicorn does not need to be running: pytest loads the ASGI application directly.

- Local development: copy `.env.test.example` to `.env.test` and supply the direct URL for your isolated Neon test database (currently `sayfridge_auth_test`).
- GitHub Actions: the workflow starts a disposable PostgreSQL 18 service and supplies `TEST_DATABASE_URL` through its environment. It does not connect to Neon or require Neon credentials.
- An existing process environment variable takes precedence over `.env.test`. Keep the PostgreSQL major versions aligned between local testing and CI.

Never commit `.env` or `.env.test`. Commit only the templates and workflow. The CI password is a disposable test value, not a Neon credential.

Database tests require `postgresql+psycopg://`, a database name ending in `_test`, and a direct connection (not a Neon pooler). Missing configuration fails the selected database tests instead of silently skipping them. The application `.env` is never used as a fallback.

Each database test migrates a fresh random `auth_test_*` schema using Alembic, performs real database operations, and drops only its own schema in teardown, including after normal assertion failures. Forced termination or a network failure during cleanup may leave a schema behind. Postman data is outside this cleanup process.

To select a subset explicitly:

```bash
# 11 database-free scenarios
python -m pytest -v -m "not postgres"

# 104 scenarios with real PostgreSQL fixtures
python -m pytest -v -m postgres
```

Automatic CI for pull requests targeting `main` and pushes to `main` runs the
22 high-priority scenarios marked `ci`. Manual workflow dispatch runs all 115.
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
`app/services/storage_spaces.py`; catalog services will be separate. Request and
response contracts live in `app/schemas/business.py`. B04 adds no schema migration.

Run B04 tests alone with:

```bash
python -m pytest tests/test_storage_spaces_api.py tests/test_storage_spaces_postgres.py -v
```
