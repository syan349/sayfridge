# Testing Strategy and Evidence

## Stock category, quantity and expiry acceptance

`test_inventory_expiry.py` covers date precedence, production/opening starting
dates, model output validation, mixed batch failures and unavailable estimation.
`test_agent_stock_policy_postgres.py` uses disposable migrated schemas to verify
private/public classification conflicts, HTTP confirmation/cancellation, atomic
rollback, concurrent edits, receipt replay, creation warnings, frozen previews and
persisted apple quantities. These tests are in the Backend `ci` selection.

`test_agent_stock_policy_live.py` requires explicit `AGENT_LIVE_MODEL=1` plus an
isolated `TEST_DATABASE_URL`; it runs English/Chinese yoghurt, apple weight and
category-correction scenarios through actual chat/resume with the configured model.
Normal regression replaces only optional expiry-model calls with an unavailable
estimator. It never spends model tokens or uses the application database for test
writes. Full regression and remote/deployed acceptance remain separate evidence.

Local verification on 2026-10-02 used Python 3.11 and a dedicated PostgreSQL 16
test cluster: the Backend core selection passed **154** tests (714 deselected),
and the new expiry/stock-policy offline suites passed **24** tests. The final
real-model suite plus date unit tests passed **18** tests, including all **6**
live scenarios and production-date shelf-life calculation. The full offline run
initially reported 797 passed, 63 skipped and one failure: an existing batch-archive
test compared a timestamp string with UTC while the temporary database returned
Pacific/Auckland. Setting only that test database to UTC made its focused rerun
pass; no product-code or remote-database change was used to mask the failure.

The configured remote database passed read-only ORM verification (11 tables,
96 columns); its revision was `a261001_sessions`, with 25 active categories and
105 inventory rows. Runtime/direct connection targets matched. This change has
no ORM or migration edits. These checks do not establish the deployed service's
environment configuration or confirm a code deployment.

## Fast CI entry point

Start from the [root README](../../README.md#run-the-tests). The fast selection
runs the Backend core selection and all Web and Flutter automated tests, excluding the manual screenshot exporter. All PRs run the fast checks through Core E2E orchestration; Backend also runs
after pushes to `main`. Fast CI has no path filter. Integration changes run
Core E2E after both reusable fast workflows succeed. Manual dispatch runs
the same gates and E2E. Backend manual dispatch retains its full suite.

The execution entry point is **GitHub Actions**:

| Workflow | Automatic execution | Manual `Run workflow` |
| --- | --- | --- |
| [Backend CI](../../.github/workflows/backend-ci.yml) | Reused by PR orchestration; core selection on pushes to `main` | Full Backend regression |
| [Frontend CI](../../.github/workflows/frontend-ci.yml) | Reused by PR orchestration on every PR | The same frontend fast checks |
| [Core E2E](../../.github/workflows/core-e2e.yml) | Every PR runs fast checks; relevant changes then run Chromium E2E | Fast checks followed by Chromium E2E |
| [Full Regression](../../.github/workflows/full-regression.yml) | None | Same-commit full offline Backend, Web, Flutter and browser E2E |

For local verification, use the per-module commands in this guide: frontend
commands below and Backend commands under **Run tests**. Use Python 3.12,
Node.js 22 and Flutter 3.44.8. Configure an isolated test database via
`TEST_DATABASE_URL` or `backend/.env.test` before running Backend database tests.
GitHub provides its own disposable PostgreSQL service. Local timings exclude
runner/SDK provisioning and artifact upload; GitHub jobs can run concurrently.
Generated reports are ignored by Git and uploaded as Actions artifacts.

The developer reported approximately 3 minutes 30 seconds for the combined fast
checks on 2026-09-30 and accepted this budget. This is a user-reported local
measurement, not a GitHub runtime guarantee. Both workflows cancel superseded
runs and retain reports for seven days. Backend manual full regression keeps a
separate concurrency group from PR/push runs.

## Frontend fast CI

[Frontend CI](../../.github/workflows/frontend-ci.yml) is called by Core E2E on every
pull request (open, update, or reopen), without path filters, and can also be started manually.
It adds two independent checks alongside the existing Backend CI:

| Check | Runtime | Verification | Evidence artifact |
| --- | --- | --- | --- |
| Web tests | Node.js 22, dependencies from `package-lock.json` | Typecheck, all Vitest unit/component/page tests with MSW-controlled APIs, production build | `web-test-results` (JUnit), `web-dist` (successful build only) |
| Flutter tests | Flutter 3.44.8, dependencies from `pubspec.lock` | Unit and widget tests under `mobile/test` except the `manual_preview` screenshot exporter, including models, services, controllers, authentication, inventory, Agent and UI interactions | `flutter-test-results` (Flutter machine JSON lines) |

These jobs use Linux runners, cached dependencies/SDK, a ten-minute timeout per
job, and seven-day artifact retention. A newer update cancels the previous run
for the same PR. There is no additional frontend push trigger, avoiding duplicate
runs for the same PR update. Test failures fail the job, including failures in the
Flutter command piped through `tee` (GitHub's explicit Bash shell uses pipefail).

Frontend tests use fake/mock dependencies: they need no Neon, deployed Backend,
OpenAI credentials, emulator, or device. Camera/voice widget and service tests
verify simulated interactions, not native hardware. The Windows-specific `voice_overlay_preview_test.dart` screenshot exporter is
tagged `manual_preview` and excluded; optional profile screenshot export is not
enabled. These checks do not build Android/iOS, deploy, or replace
real-system E2E or device acceptance.

Reproduce locally with the stated runtime versions:

```bash
# From web/
npm ci --no-audit --no-fund
npx tsc -b
npm test -- --reporter=default --reporter=junit --outputFile=test-results.xml
npm run build

# From mobile/, using Flutter 3.44.8 (also used by the Render build script)
flutter pub get --enforce-lockfile
flutter test --no-pub --exclude-tags manual_preview
```

Local verification on 2026-09-30 (macOS, this CI integration working tree):
Node.js 22.23.3 passed typechecking, all 103 Web tests in 21 files, and the
production build; Flutter 3.44.8 / Dart 3.12.2 passed all 151 selected tests with
`manual_preview` excluded. Locked dependency installation succeeded for both
clients without changing either lockfile. Test execution took approximately
5 seconds for Web and 11 seconds for Flutter; these exclude installation and
are not GitHub runner timings. Existing Web fixture warnings (duplicate keys and
unhandled mocked admin requests) did not fail the suite. The developer subsequently confirmed that the merged fast-CI PR passed on GitHub.
This confirmation does not cover the new Core E2E workflow.

The workflow reports checks automatically; requiring `Web tests` and
`Flutter tests` before merging is a separate GitHub branch-protection setting.
No repository setting is changed by adding this workflow. Historical Backend
reports below retain their original scope and results.

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
the business action under test is performed through Web UI. Archival is the
supported removal action; the suite does not invent a hard-delete API.

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
The seven database-target guard cases belong to Backend full regression; the fast
Backend selection remains 60. Core E2E results must be reported separately from
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
Flutter-only changes. The next PR run provides GitHub execution evidence.

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

This workflow runs automated regression, not deployment or Android packaging.
Live OpenAI acceptance needs a separate explicit opt-in and credentials; native
Android validation and manual screenshot exporters remain separate activities.
Their exclusion is recorded in the summary. Web and Flutter currently use the
same complete offline unit/UI selections in both fast CI and full regression;
Backend expands from its 60-case fast selection to the full offline suite.

Local verification: orchestration tests exercise successful aggregation and
failure/cancellation/skipped/missing outcomes; YAML and reusable workflow targets
are checked locally. The complete multi-module run is performed through the
manual GitHub workflow after this configuration is pushed and available on the
default branch. Record that run's result and SHA as final full-regression evidence.

## Reports

| Work packages | Report | Scope |
| --- | --- | --- |
| Security 8.1–8.6 | [Security and Privacy](../SECURITY_AND_PRIVACY.md) | Authorization, hostile inputs, uploads, tokens, logging and dependency audit |
| Agent multimodal | [Image input and stock review](AGENT_MULTIMODAL_TEST_RESULTS.md) | Inline images, cross-turn context, supplements, mandatory review, checkpoint recovery and live-model acceptance |
| Agent V0.2 | [Agent workflow verification](AGENT_V02_TEST_RESULTS.md) | Memory, estimates, per-item transactions, resume, recovery, and live-model acceptance |
| B01–B03 | [Authentication](B01-B03_AUTH_TEST_RESULTS.md) | Registration, login, and current user |
| B04 | [Storage spaces](B04_STORAGE_SPACES_TEST_RESULTS.md) | Ownership, state, pagination, and concurrency |
| B05–B06 | [Catalog](B05-B06_CATALOG_TEST_RESULTS.md) | Categories and private definitions |
| B07–B09 | [Inventory](B07-B09_INVENTORY_TEST_RESULTS.md) | Queries, stock entry, metadata, versions, and notes |
| B10 | [Inventory additions](B10_INVENTORY_ADDITIONS_TEST_RESULTS.md) | Quantity precision, ADD, idempotency, locking, and rollback |
| B11 | [Inventory consumption](B11_INVENTORY_CONSUMPTION_TEST_RESULTS.md) | CONSUME amounts/fractions, precision, state, retries, and concurrency |
| B12 | [Inventory reconciliation](B12_INVENTORY_RECONCILIATION_TEST_RESULTS.md) | Confirmed totals, estimate clearing, state, retries, and atomicity |
| B13 | [Inventory state](B13_INVENTORY_STATE_TEST_RESULTS.md) | Discard/archive transitions, preservation, isolation, and concurrency |
| B14 | [Inventory history](B14_INVENTORY_HISTORY_TEST_RESULTS.md) | Item/global ordering, filters, pagination, detail, field exposure, and ownership |
| B15 | [Inventory batches](B15_INVENTORY_BATCH_TEST_RESULTS.md) | Atomic batch creation, movement, and archival |
| B22 | [Expiry summary](B22_EXPIRY_SUMMARY_TEST_RESULTS.md) | On-demand expiry buckets, filters, pagination, and ownership |
| B25 | [Administrator accounts](B25_ADMIN_USERS_TEST_RESULTS.md) | Permission, safe reads, filtering, status changes, and no-op writes |
| Database release readiness | [Database isolation and acceptance evidence](DATABASE_ACCEPTANCE.md) | Environment guards, migration/seed evidence, transaction rollback, and idempotency |

Manual requests: [Postman guide](POSTMAN_GUIDE.md).
Setup and database configuration: [backend README](../../backend/README.md).

## Run tests

Run commands from `backend`. Uvicorn does not need to be running.

| Execution | Selection | Command |
| --- | --- | --- |
| Local full regression | Current suite; live-model tests require explicit opt-in | `python -m pytest -v` |
| Local core check | 60 scenarios | `python -m pytest -v -m ci` |
| Automatic PR/main CI | Same core set | `python -m pytest -v -m ci --strict-markers` |
| Manual workflow dispatch | Full suite | `python -m pytest -v --strict-markers` |
| Database-free check | Current database-free selection | `python -m pytest -v -m "not postgres"` |

Database tests use real PostgreSQL. Locally, supply `TEST_DATABASE_URL` through the
process environment or ignored `.env.test`; never use the application database.
CI uses a disposable PostgreSQL 18 service, not Neon. Fixtures initialize an
isolated schema and clean it up after each test.

Use `python -m pytest --collect-only -q` to inspect the current suite. Historical
reports retain the counts and outcomes of their recorded runs; do not sum overlapping
test groups. The Agent V0.2 report includes the opt-in model checks and environment
limitations of that run.

## CI selection policy

Use one test implementation for local and CI runs. The fast selection contains
**60 scenarios: 28 PostgreSQL-backed and 32 database-free** (collected on
2026-09-30). It was reduced from 169 (80 PostgreSQL-backed) after slow local runs.
No test bodies or assertions were removed. The original 727 scenarios remain in full regression; this E2E foundation adds
seven runner-safety cases (734 total; 674 excluded by `-m ci`). Live-model cases still require opt-in.

| Fast coverage | Scenarios |
| --- | ---: |
| Registration/login lifecycle and registration role protection | 2 |
| Administrator authorization and account status | 2 |
| Storage creation and non-empty archive guard | 2 |
| Catalog visibility | 1 |
| Inventory creation/listing/ownership and concurrent version conflict | 5 |
| Addition/replay and transaction rollback | 2 |
| Consumption/replay, reconciliation/replay, discard and archive | 4 |
| Batch create/move/archive: success and atomic rollback for each | 6 |
| Expiry summary and item/global operation history | 3 |
| Agent stock entry/replay and deterministic workflow validation | 3 |
| Architecture boundaries, database target guards, OpenAPI/version, migration logging | 14 |
| Token protection, login throttling, upload/CORS, private logs/settings and image metadata | 16 |
| **Total** | **60** |

Full regression retains exhaustive route/authentication matrices, malformed-input
variants, extra filters/states, additional lock-wait/concurrency permutations,
and complete database initialization/acceptance checks. Run it before release and
for changes to authentication, transactions, migrations, or shared API contracts;
a fast pass is not a full-suite or E2E pass. Do not skip it merely because the fast
selection is green.

Use `--durations=15` to identify slow setup, call, and teardown phases. A local
remote-database run is not comparable to GitHub's colocated disposable PostgreSQL
service. Reducing the database-backed selection cuts repeated migration/connection
work, but does not guarantee a particular runtime on a remote database. Each
selected database test still migrates its own schema; isolation is unchanged.

Local verification on 2026-09-30: **60 passed, 667 deselected in 12.67 seconds**
using Python 3.12 and a disposable PostgreSQL 18 instance on localhost (UTC).
This is a local measurement, not a remote Neon or GitHub runtime guarantee.
At that verification point, full collection contained 727 parameterized
scenarios, and test function bodies and assertions were unchanged. Web (103) and Flutter (151) fast
selections were not reduced.

Use `@pytest.mark.ci` for a whole test or `pytest.param(..., marks=pytest.mark.ci)`
for selected parameters. The marker is registered in `backend/pytest.ini`;
there is no default filter. Check the actual selection with:

```bash
python -m pytest --collect-only -q -m ci --strict-markers
```

The Backend job name remains `test-job`. Automatic/manual runs upload their
respective JUnit results. Whether a check blocks merging depends on repository
branch protection, which is not changed here. Run full regression for the
critical changes described above and before release.

## Maintain reports

Name reports `Bxx[-Byy]_FEATURE_TEST_RESULTS.md`. Record the date, tested commit or
working tree, environment, commands, outcomes, and outstanding acceptance checks.
Keep detailed scenarios and historical timings in the feature reports, not this
index. Distinguish local results from remote CI. Update current counts here when
selection changes; test collection is the source of truth.


## Category and schema verification — 2026-09-26

The targeted repair/category/receipt tests passed: **8 passed**. The full 598-test
collection initially reported **588 passed, 8 skipped, 1 failed and 2 errors**
(one error occurred during teardown of an already counted test). All three
exceptions were database connection failures; their targeted reruns passed.
Across these runs all 590 non-skipped cases passed, but the initial run was not
clean. Original interrupted/failed teardown cleanup was not verified.

Development database writes and authenticated development HTTP acceptance were
not performed. Live-model classification evaluation was not performed; deterministic
tests validate database checks and confirmation, not semantic classification accuracy.

### Fixed model-evaluation cases

These are manual/live-model evaluation expectations, not a rule-based classifier or a measured
accuracy claim. Run with a seeded isolated test database and explicit live-model opt-in; record
model/version, date, category result, clarification, and confirmation behavior.

| Input | Expected result |
| --- | --- |
| 鸡胸肉 / chicken breast / frozen chicken | Meat & Poultry |
| canned tomatoes / 罐装番茄 | Vegetables & Mushrooms |
| tomato sauce / 番茄酱 / 老干妈 | Sauces, Condiments & Spreads |
| frozen pizza / 冷冻披萨 | Prepared Meals & Leftovers |
| oat milk / 燕麦奶 | Milk & Plant-Based Milk |
| coconut milk / 椰奶 (no use indicated) | Clarify drinking versus cooking |
| cooking coconut milk | Sauces, Condiments & Spreads |
| Anchor (brand only) | Ask for product identity |
| CHK BRST 500G, user says chicken breast | Meat & Poultry; do not derive stock count from weight |
| XYZ 2.99 (unexplained receipt text) | Ask; do not silently choose Other |
| Greek yoghurt / 希腊酸奶 | Yoghurt |
| tofu / 豆腐 | Tofu & Meat Alternatives |
| dish soap / 洗洁精 | Household Supplies |
| clearly identified item outside catalog | Propose Other and require confirmation |
| existing private definition with user-selected category | Reuse category; do not reclassify |


## Persistent-login validation — 2026-10-01

Local verification used Python 3.12, Node.js 22 and Flutter 3.44.8. PostgreSQL
sessions and browser E2E used isolated local schemas; these checks did not modify
Neon or deploy to hosted platforms.

- Backend fast CI: 90 passed, 679 deselected.
- Ten [Backend session tests](../../backend/tests/test_persistent_auth.py) passed:
  rotation, hashed storage, replay revocation, logout, independent devices,
  concurrent rotation, inactive accounts, expired access renewal and session deadlines.
- Web: 108 Vitest cases passed; production build passed. Existing lint warning:
  the triple-slash type reference in `vite.config.ts`.
- Flutter: 165 cases passed with `manual_preview` excluded; analyzer reported no issues.
  Tests cover concurrent renewal, offline behavior, server logout, stream authentication
  and offline preview storage isolation.
- Eight Chromium E2E flows passed, including real session renewal and immediate
  access revocation after logout. The first browser run timed out before executing
  business requests; subsequent complete runs passed.

Deploy migration `a261001_sessions` before the new Backend, then update both
frontends. Existing access-only sessions require login again to use persistent login.
