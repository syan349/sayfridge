# Testing and CI

## Fast CI entry point

Start from the [root README](../../README.md#run-the-tests). The fast selection
contains **314 cases: Backend 60, Web 103, Flutter 151**. Backend PR checks target
`main` (and also run after pushes to `main`); frontend checks run for every PR.
No path filtering is applied. E2E and unified full-regression orchestration are
not implemented by this change; Backend manual dispatch retains its full suite.

The execution entry point is **GitHub Actions**:

| Workflow | Automatic execution | Manual `Run workflow` |
| --- | --- | --- |
| [Backend CI](../../.github/workflows/backend-ci.yml) | Core selection on PRs targeting `main` and pushes to `main` | Full Backend regression |
| [Frontend CI](../../.github/workflows/frontend-ci.yml) | Web and Flutter fast checks on every PR | The same frontend fast checks |

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

[Frontend CI](../../.github/workflows/frontend-ci.yml) runs on every pull request
(open, update, or reopen), without path filters, and can also be started manually.
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
unhandled mocked admin requests) did not fail the suite. The first GitHub Linux
run remains to be verified after pushing a PR.

The workflow reports checks automatically; requiring `Web tests` and
`Flutter tests` before merging is a separate GitHub branch-protection setting.
No repository setting is changed by adding this workflow. Historical Backend
reports below retain their original scope and results.

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
No test bodies or assertions were removed. All 727 scenarios remain in full
regression; 667 are excluded only by `-m ci`. Live-model cases still require opt-in.

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
Full collection still contains the same 727 parameterized scenarios, and test
function bodies and assertions are unchanged. Web (103) and Flutter (151) fast
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
