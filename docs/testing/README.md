# Testing Strategy and Evidence

This is the project's testing entry point for assessment criterion 8. Tests are
maintained alongside feature development: historical feature reports and commits
record the unit, API, database, UI and Agent checks added during implementation.

## Strategy and execution

| Layer | Trigger | Coverage and environment |
| --- | --- | --- |
| Fast CI | Every PR creation/update; Backend also runs on main push | Marked Backend core tests; all selected Web and Flutter unit/component/widget tests; Web typecheck/build; disposable PostgreSQL |
| Core E2E | Relevant PR file changes after fast checks pass; manual dispatch | Eight real Chromium → Web → Backend → database workflows in isolated schemas |
| Full regression | Manual before release or after substantial cross-module changes | Same immutable commit for full offline Backend, Web/Flutter selections and E2E; aggregate pass/fail |
| Live-model checks | Explicit local opt-in | Actual configured model with synthetic stock in disposable test schemas |
| Native/manual acceptance | Selected Android build and deployed system | Permissions, camera/speech, notifications, network interruption and cross-client business flows |
| Performance | Dedicated measured run | Record environment, load, data volume, warm/cold latency and errors against architecture targets |

Fast CI favors core business boundaries and bounded runtime. Full regression adds
Backend cases without repeating real-model calls in routine PRs. Unit/UI mocks
exercise deterministic client behavior; E2E verifies actual persistence and CORS.
Native Android and model behavior have separate evidence records.
[Architecture](../architecture/README.md#capacity-assumptions-and-scaling) defines
performance targets; the [performance record](records/PERFORMANCE_TEST_RECORD.md)
contains measured results.

## Fast CI entry point

[Core E2E](../../.github/workflows/core-e2e.yml) orchestrates reusable Backend and
Frontend jobs on PRs. [Backend CI](../../.github/workflows/backend-ci.yml) and
[Frontend CI](../../.github/workflows/frontend-ci.yml) provide additional entry points: Backend runs on main push/dispatch; Frontend supports dispatch. Required-check settings control merge permission;
workflow YAML controls execution. A historical check name must not be retained
as a required check after its job is renamed.

<a id="ci-selection-policy"></a>

The `ci` marker selects Backend fast checks. Web/Flutter keep their complete
selected offline tests; browser E2E runs after successful fast jobs when the path
selector matches. The commands below are the current CI selection policy.

Local equivalents:

```bash
# From backend/, with ignored .env.test / TEST_DATABASE_URL for a database ending _test
python -m pytest -v -m ci --strict-markers --durations=15 --junitxml=test-results.xml
python -m pytest --collect-only -q -m ci --strict-markers

# From web/, Node.js 22
npm ci
npm test
npm run build
npm run lint

# From mobile/, Flutter 3.44.8
flutter pub get --enforce-lockfile
flutter test --exclude-tags manual_preview
flutter analyze
```

Pytest markers define the current fast selection; inspect it with `--collect-only`
rather than maintaining a duplicated count. Web lint and Flutter analyze are local
checks; the current frontend workflow executes tests and Web typecheck/build.
Backend does not currently define a unified lint job.

Backend database fixtures use a direct TEST_DATABASE_URL ending `_test` and
random schemas. CI supplies disposable PostgreSQL 18 without shared Neon secrets.
Web unit/UI tests use MSW and reject unhandled requests. Flutter tests exclude
`manual_preview` screenshot exporters. E2E files are excluded from Vitest.

## Core E2E

This suite contains **eight browser scenarios**:

1. Register, sign out, sign in, load empty inventory, renew an expired access credential after reload, and verify logout revocation.
2. Create, rename, archive and restore an empty storage space.
3. Create a private definition and stock item; verify inventory and expiry summary.
4. Edit notes and move an item; verify persistence after reload.
5. Record consumption; verify remaining quantity and operation history.
6. Reconcile an exact count; verify confirmed quantity and null estimate.
7. Archive an item; verify read-only persistence and removal from in-stock queries.
8. Verify another user cannot read or edit the item, or access administrator accounts.

Requests are real and are not intercepted. Each test has a unique account.
Fixture setup and persistence assertions also use authenticated real HTTP calls;
the business action under test is performed through Web UI. This suite exercises archival as the removal action.

The [runner](../../backend/scripts/run_e2e.py) starts a fresh Backend process and
Playwright starts a production Web build with the actual Backend URL. Different
loopback ports exercise CORS. Database migrations, 25 public categories and Agent
storage are initialized in unique schemas; no demonstration accounts are seeded.
The browser creates its account through the real registration endpoint. Agent
model calls are disabled and no OpenAI or hosting-platform credentials are needed.

**Isolation:** only an explicit `E2E_DATABASE_URL` with a loopback host and a database
name ending `_e2e` is accepted. Connection parameters that could override the host
or database are rejected. There is no application `.env` database fallback. Every
run owns two random schemas and removes them after success or failure, after
stopping its Backend. Playwright stops the Web server. Forced process termination
may prevent local cleanup; use a disposable database/container. In GitHub the
entire service container is discarded when the job ends. Never point this suite
at Neon or the shared demonstration environment.

### Local setup and execution

Prerequisites: Python 3.12, Node.js 22 and PostgreSQL 18 with a UTF8 database.
Install once (from repository root):

```bash
python -m pip install -r backend/requirements.txt
npm --prefix web ci
cd web
npx playwright install chromium
cd ..
```

For example, create a disposable database with Docker (port 5433):

```bash
docker run --rm -d --name sayfridge-e2e-db \
  -e POSTGRES_USER=e2e_user -e POSTGRES_PASSWORD=local-e2e-password \
  -e POSTGRES_DB=sayfridge_e2e -p 127.0.0.1:5433:5432 postgres:18
docker exec sayfridge-e2e-db pg_isready -U e2e_user -d sayfridge_e2e
cp backend/.env.e2e.example backend/.env.e2e
```

Wait until PostgreSQL accepts connections. A locally installed PostgreSQL also
works: create a dedicated UTF8 database ending `_e2e` and edit the ignored
`backend/.env.e2e`. Its user needs permission to create and drop schemas.

The single execution entry point, from repository root, is:

```bash
python backend/scripts/run_e2e.py
```

To watch Chromium perform the same test with slower browser actions:

```bash
python backend/scripts/run_e2e.py --headed
```

The script builds the Web app, starts the services, waits for readiness, runs
Chromium, and cleans its schemas. Run one local instance at a time: each run
replaces the previous build/report directory. No separately started backend/frontend is needed.
An `E2E_DATABASE_URL` environment variable takes precedence over `.env.e2e`.
After testing, stop the optional disposable container:

```bash
docker stop sayfridge-e2e-db
```

### GitHub execution and evidence

After the workflow is present on the default branch, select **Actions → Core E2E
→ Run workflow** and choose the branch to test. Each manual run uses
Ubuntu, Node.js 22, Python 3.12, Chromium and a PostgreSQL 18 service, with a
15-minute job limit. No Render, Vercel or Neon environment is changed.

`core-e2e-results` is retained for seven days. Local evidence is ignored under
`web/.e2e-artifacts/`: HTML/JUnit results, initialization/backend logs, and a run
manifest recording the commit and temporary schema names. Browser failures retain
a screenshot and Playwright trace. These may contain generated test credentials
and tokens; keep artifacts within the team rather than publishing traces.

```bash
# From web/, view the latest report
npx playwright show-report .e2e-artifacts/html
```

Vitest explicitly excludes `e2e/**`, keeping Web unit/component tests separate from browser E2E.
Database-target guard cases belong to Backend regression. Use pytest collection
to inspect the current fast selection. Core E2E results must be reported separately from
unit/component counts.

### PR gates and verification

The [path selector](../../.github/scripts/e2e_paths.py) compares the PR base and
head commits. Backend application code, migrations, initialization scripts,
Python dependencies/runtime declarations, Web code/assets/API clients, npm lock
files, browser tests/configuration and workflow changes trigger E2E. Documentation
and Flutter-only changes skip browser E2E; Flutter still runs all its fast checks.
The Web suite does not exercise native Android hardware.

Backend and frontend workflows are reused by the orchestrator, so each fast
selection runs once per PR. The browser job depends on successful Backend,
Web and Flutter checks and relevant paths. A failed fast job prevents E2E startup.
Manual dispatch selects E2E regardless of paths. Superseded runs are cancelled.
Check names now include reusable-job prefixes; update any required-check setting
that names the former checks after confirming the first remote PR run.

Local verification on 2026-09-30: eight real-browser scenarios passed in 11.7
seconds with Node.js 22, Python 3.12 and Docker PostgreSQL 18. Six path-selection
checks cover docs, business code, migrations, client code, locks/workflows and
Flutter-only changes. GitHub run summaries identify the tested commit and artifact outcomes.

## Unified full regression

Use **Actions → Full Regression → Run workflow**, choose the target branch and
start one run. Run it before a release, after substantial changes across modules,
or before final acceptance. It has no PR, push or scheduled trigger.

The revision job resolves an immutable commit SHA. Every module checks out that
same SHA; branch updates during execution do not change the tested version.
Backend, frontend and browser E2E run concurrently on separate Linux jobs.
Backend and browser jobs each have their own disposable PostgreSQL service.

| Required job | Selection | Limit | Artifact |
| --- | --- | --- | --- |
| Backend | All collected offline pytest tests with strict markers; live-model opt-ins disabled | 60 minutes | `backend-test-results` JUnit |
| Web | All Vitest tests, typecheck and production build | 10 minutes | `web-test-results`, `web-dist` |
| Flutter | All unit/widget tests except `manual_preview` exporters | 10 minutes | `flutter-test-results` JSON lines |
| Browser E2E | Eight real Web/API/database scenarios plus database guards | 15 minutes | `core-e2e-results` HTML, JUnit and diagnostics |

The summary always evaluates all required jobs. Failure, cancellation, skipped
or missing results produce **FAIL**. It records the test SHA, workflow SHA, run ID,
job outcomes and test scope in the Actions summary and `full-regression-summary`
(JSON and Markdown). Reports from all jobs belong to the same Actions run and
are retained for seven days. Download them when preparing final submission evidence.
Backend's regular PR fast timeout remains ten minutes.

This workflow runs automated regression. Deployment and Android packaging use
the [delivery runbook](../delivery/README.md).
Live OpenAI acceptance needs a separate explicit opt-in and credentials; native
Android validation and manual screenshot exporters remain separate activities.
Their exclusion is recorded in the summary. Web and Flutter currently use the
same complete offline unit/UI selections in both fast CI and full regression;
Backend expands from its marked fast selection to the full offline suite.

Orchestration tests exercise successful aggregation and
failure/cancellation/skipped/missing outcomes; YAML and reusable workflow targets
are checked locally. Run the complete multi-module suite through the manual GitHub workflow and
retain its result and SHA as release evidence.

## Performance record

The [Performance Test Record](records/PERFORMANCE_TEST_RECORD.md) records the
2026-10-04 measurements: a 10-minute, 5 RPS baseline with 100 users, 50,000
inventory batches and 500,000 quantity operations; 120 hosted Vercel/Neon business
reads; separate login/refresh and contention checks; and 10 real-model Agent
samples. The REST baseline and hosted reads passed. Nine Agent samples completed;
one returned `rate_limit_exceeded`. The record retains individual timings, the
failure, code identities, cleanup verification and reproduction scripts. A separate
historical section preserves the 2026-09-29 hosted latency measurements and the
Vercel function-region comparison, with the original timing extract.

## Manual integration record

The [Manual Integration Test Record](reports/MANUAL_INTEGRATION_TEST_RECORD.md)
contains 13 team-reviewed cases covering onboarding, inventory, AI interactions,
session renewal, ownership and mobile usability. Each case records setup, steps,
expected behavior, observations and corrective work. The
[evidence index](evidence/manual-integration/2026-10-03/source-index.json) retains
finding metadata and screenshot references.

Use its case IDs in emulator/device retests and the
[Final Acceptance Record](reports/FINAL_ACCEPTANCE.md#manual-cross-client-and-android-validation).
Record each run's date, tester, client/device, APK and Backend versions, outcome
and evidence. Manual observations, browser E2E and release acceptance have separate
results. Track issue resolution and manual retest outcome in separate fields.

## Reports

| Work packages | Report | Scope |
| --- | --- | --- |
| Performance baseline and hosted response | [Performance test record](records/PERFORMANCE_TEST_RECORD.md) | 2026-09-29 hosted region comparison; 2026-10-04 large-data REST load, hosted reads, authentication, contention and real-model SSE timings |
| Manual integration during development | [Manual integration test record — issue #139](reports/MANUAL_INTEGRATION_TEST_RECORD.md) | 13 cases with setup, steps, expected results, observations, fixes and evidence |
| Documentation consolidation | [Documentation review — 2026-10-02](reports/DOCUMENTATION_REVIEW.md) | Navigation, links, command syntax, source consistency and evidence preservation |
| Security 8.1–8.6 | [Security and Privacy](../security/README.md) | Authorization, hostile inputs, uploads, tokens, logging and dependency audit |
| Agent multimodal | [Image input and stock review](reports/AGENT_MULTIMODAL_TEST_RESULTS.md) | Inline images, cross-turn context, supplements, mandatory review, checkpoint recovery and live-model acceptance |
| Agent V0.2 | [Agent workflow verification](reports/AGENT_V02_TEST_RESULTS.md) | Memory, estimates, per-item transactions, resume, recovery, and live-model acceptance |
| B01–B03 | [Authentication](reports/B01-B03_AUTH_TEST_RESULTS.md) | Registration, login, and current user |
| B04 | [Storage spaces](reports/B04_STORAGE_SPACES_TEST_RESULTS.md) | Ownership, state, pagination, and concurrency |
| B05–B06 | [Catalog](reports/B05-B06_CATALOG_TEST_RESULTS.md) | Categories and private definitions |
| B07–B09 | [Inventory](reports/B07-B09_INVENTORY_TEST_RESULTS.md) | Queries, stock entry, metadata, versions, and notes |
| B10 | [Inventory additions](reports/B10_INVENTORY_ADDITIONS_TEST_RESULTS.md) | Quantity precision, ADD, idempotency, locking, and rollback |
| B11 | [Inventory consumption](reports/B11_INVENTORY_CONSUMPTION_TEST_RESULTS.md) | CONSUME amounts/fractions, precision, state, retries, and concurrency |
| B12 | [Inventory reconciliation](reports/B12_INVENTORY_RECONCILIATION_TEST_RESULTS.md) | Confirmed totals, estimate clearing, state, retries, and atomicity |
| B13 | [Inventory state](reports/B13_INVENTORY_STATE_TEST_RESULTS.md) | Discard/archive transitions, preservation, isolation, and concurrency |
| B14 | [Inventory history](reports/B14_INVENTORY_HISTORY_TEST_RESULTS.md) | Item/global ordering, filters, pagination, detail, field exposure, and ownership |
| B15 | [Inventory batches](reports/B15_INVENTORY_BATCH_TEST_RESULTS.md) | Atomic batch creation, movement, and archival |
| B22 | [Expiry summary](reports/B22_EXPIRY_SUMMARY_TEST_RESULTS.md) | On-demand expiry buckets, filters, pagination, and ownership |
| B25 | [Administrator accounts](reports/B25_ADMIN_USERS_TEST_RESULTS.md) | Permission, safe reads, filtering, status changes, and no-op writes |
| Database release readiness | [Database isolation and acceptance evidence](reports/DATABASE_ACCEPTANCE.md) | Environment guards, migration/seed evidence, transaction rollback, and idempotency |

Manual requests: [Postman guide](POSTMAN_GUIDE.md).
Setup and database configuration: [backend README](../../backend/README.md).

## Evidence maintenance

[Recorded testing notes](reports/TESTING_IMPLEMENTATION_NOTES.md) retain dated
category/schema, frontend and session verification results formerly embedded here.
Each report identifies its tested date, revision and selection. Report overlapping
selections separately.
Security conclusions remain in [Security and Privacy](../security/README.md), which
links the original redacted audit/JUnit files under `evidence/security/`.

For each release retain commit SHA, environment/tool versions, exact command,
result and report/artifact location. Actions artifacts expire after seven days;
keep the selected submission evidence before expiry. Label manual/device/model
results separately from offline regression. Record failures, fixes and rerun results
rather than replacing an old result with a newer total.

Database evidence is produced by `backend/scripts/record_database_acceptance.py`;
[delivery](../delivery/README.md) owns operator commands and deployed smoke checks.

Original blueprints, design alternatives and pre-consolidation records remain
available through the [project archive](../archive/README.md).

## Final release evidence

Use the [Final Acceptance Record](reports/FINAL_ACCEPTANCE.md) to record one
selected main release's automated, deployed and Android results. At the time of
release, enter each result, tested commit and evidence link. Status: awaiting
final-release execution. Keep feature reports and raw attachments alongside it.
