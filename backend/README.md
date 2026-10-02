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
`iat` and `exp` claims. Login and refresh issue tokens with issuer `sayfridge` and
audience `sayfridge-api`. Protected requests verify the JWT once, then pass the
verified user/session IDs to database session and account checks.

Existing signed tokens with neither scope claim keep their original expiry and
session-revocation rules; refresh replaces them with scoped tokens. Wrong or
partial scope claims return the existing 401 response. Tokens without `sid`
retain their original short expiry. This update requires no database migration,
new environment variable or client payload change.

Security events record fixed event names, server-generated request IDs and
applicable internal UUIDs. Credentials and request content are excluded. See
[Security and Privacy](../docs/security/README.md#authentication-boundary-and-security-events)
for event fields and verification evidence.

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

## Persistent chat upgrade

Migration `a261002_chat` adds only `conversation.is_primary`,
`conversation.history_complete`, and the partial unique primary-user index.
Apply the reviewed migration before deploying this backend. It retains legacy
conversation IDs, messages and Agent checkpoints. Deployment and shared-database
changes require separate authorization.

```bash
python -m alembic upgrade a261002_categories:a261002_chat --sql
python scripts/recover_chat_history.py --dry-run
python scripts/recover_chat_history.py --dry-run --user-id <uuid> --source-thread <uuid>
```

The first command prints the migration preview. Recovery defaults to read-only;
`--apply` requires the migrated target and an explicit `BACKFILL` confirmation.
It recovers observed user text and saved public replies across checkpoints using
stable message IDs. It never reconstructs original text from summaries. Where a
send time is missing, it uses the first observed checkpoint time. Repeated runs
retain existing public rows. Recovered legacy history stays marked incomplete.
Primary binding uses the most recently active owned thread; other legacy pending
operations continue through their original IDs without combining execution state.

The [Agent API contract](../docs/reference/API_REFERENCE.md#9-agent-v02--chat-resume-and-recovery)
defines the incremental `GET /agent/chat` entry and its public-history cursor.
Existing clients continue using their current POST and state APIs; reopening the
complete public transcript requires their later adoption of the GET entry.

`AGENT_CONTEXT_TRIGGER=80000`, `AGENT_CONTEXT_TARGET=40000`,
`AGENT_CONTEXT_LIMIT=160000`, `AGENT_MODEL_CONTEXT_LIMIT=160000`, and
`AGENT_OUTPUT_TOKENS=8000` are the initial configurable defaults. Accounting
includes rules, tool schemas, relevant memory/task data, image input and output
reserves. `AGENT_SUMMARY_TIMEOUT_SECONDS=45` bounds the entire summarization step.
The current model merges the previous summary with older full text, checkpoints
that result, then removes eligible working messages in a separate node. Recent
text, pending evidence and complete tool call/result groups remain available.
Public messages are retained separately. Failed summarization retains the prior
state; requests that cannot fit safely return `CONTEXT_BUDGET_EXCEEDED` for retry.
This implementation adds neither LangMem nor retrieval of old public messages.

The backend CI subset includes durable history/recovery regressions. CI also feeds
captured responses from FastAPI and isolated PostgreSQL to unchanged Web and Mobile
parsers/controllers. To run the same compatibility checks locally, set
`AGENT_CLIENT_CAPTURE_FILE` to an ignored JSONL path, run the relevant PostgreSQL
Agent API tests, then run:

```bash
# From web/
npm test -- --config ../backend/tests/vitest.agent-clients.config.mts
# From mobile/, after locked dependencies are available
flutter test --no-pub ../backend/tests/agent_client_compat_test.dart
```

Original half-consumption and real summary fidelity checks remain opt-in:
`AGENT_LIVE_MODEL=1 python -m pytest -q tests/test_agent_chat_acceptance_live.py`.

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
