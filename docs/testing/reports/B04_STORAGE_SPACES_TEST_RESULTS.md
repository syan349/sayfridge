# B04 Storage-Space Test Results

Validation date: 2026-09-13. Tested working tree: `syan349_feat_backend_apis`,
based on `1efc65e58409` (PR #61 merge). Test target: the uncommitted B04 working tree.

Design: [Backend design handbook](../../architecture/BACKEND_DESIGN.md), sections 3, 4.2, and 7.
Manual usage: [B04 API reference](../../reference/API_REFERENCE.md#3-storage-spaces--b04).

## 1. Delivered scope

Six authenticated endpoints under `/api/v1/storage-spaces`: list, detail, create,
partial update, archive, and restore. Routes handle HTTP concerns; the dedicated
storage-space service handles queries, ownership, business rules, and write
transactions. The former learning TODOs and learning guide have been removed.
The existing eight-table schema and migration remain unchanged.

## 2. Verification results

Environment: macOS, Python 3.11.16, pytest 9.1.1, disposable PostgreSQL 18 Docker
container. The process's TEST_DATABASE_URL pointed to this container, overriding
`.env.test`. No B04 test in this run accessed Neon or the application database.

| Verification | Result |
| --- | --- |
| B04 API contracts (`test_storage_spaces_api.py`) | 61 passed in 13.32 seconds |
| B04 concurrency/transaction tests (`test_storage_spaces_postgres.py`) | 9 passed in 1.66 seconds |
| Full backend regression suite | 115 passed, 0 failed, 0 skipped in 20.02 seconds |
| Regression composition | Existing 45 B01–B03 scenarios plus 70 B04 scenarios |
| Database composition | 11 database-free scenarios; 104 scenarios using real PostgreSQL fixtures |
| OpenAPI inspection after adding explicit error documentation | Six endpoints; Bearer authentication; success and business-error schemas; no archive/restore body; existing auth validation schema preserved |
| Test schema cleanup | Zero auth_test_* schemas remained after the suite |

Commands, from `backend`, after setting TEST_DATABASE_URL to the isolated test database:

```bash
python -m pytest tests/test_storage_spaces_api.py -q --tb=short
python -m pytest tests/test_storage_spaces_postgres.py -q --tb=short
python -m pytest -v --tb=short --junitxml=/tmp/sayfridge-b04-test-results.xml
```

The local JUnit artifact is temporary and is not committed. Database fixtures use
real SQLAlchemy sessions and apply Alembic to a fresh schema for each case. The
concurrency tests observe actual PostgreSQL locks and use independent sessions;
query-observation wrappers do not replace the database or return fabricated data.

## 3. Coverage

| Area | Verified behavior |
| --- | --- |
| Creation | All five types; trimmed names; 100-character boundary; generated public fields and timestamps; current-user ownership and ACTIVE state |
| Validation | Missing fields, blank/long names, invalid types, nulls, extra/server-owned fields, malformed JSON, invalid UUIDs and pagination; safe business 422 errors |
| Authentication/ownership | All six endpoints require identity; current inactive accounts are rejected; foreign and missing IDs return identical 404 responses without modification |
| Lists | ACTIVE default, ARCHIVED/ALL filtering, user isolation, name/UUID ordering, pagination, empty datasets and out-of-range pages; count and items in one SQL statement |
| Updates | Partial changes, unchanged values, archived-state rejection, case-insensitive active-name conflicts, atomic rollback of multi-field changes |
| State actions | Archive/restore and repeated requests; unchanged timestamps on no-op; conflicting restoration retains ARCHIVED state; request bodies rejected |
| Inventory checks | IN_STOCK blocks archival; EMPTY/DISCARDED/ARCHIVED do not; inventory values and versions unchanged |
| Concurrency | Concurrent creates, renames, and restores have one name winner; waiting archival sees committed new stock; waiting PATCH sees committed archival |
| Failure recovery | Unrelated PostgreSQL constraints propagate rather than becoming name conflicts; rollback leaves data unchanged and the same session usable |
| Existing behavior | All 45 authentication/configuration/security/model/health tests still pass |

## 4. CI and remaining acceptance

The `test-job` workflow uses the same test definitions. After the CI selection
update, automatic PR/main runs select 22 marked core cases (6 B01–B03 and 16 B04);
manual workflow dispatch and default local pytest run all 115. Its job name and
PostgreSQL service configuration were not changed. See the [CI selection policy](../README.md#ci-selection-policy). Recorded execution: local PostgreSQL tests. At the time of release, record remote
CI, manual Postman/Neon and Web/Flutter acceptance for the selected commit in the
[Final Acceptance Record](FINAL_ACCEPTANCE.md).

Stock-creation and movement APIs are outside B04. Their future implementations
must take the same space row lock and recheck ACTIVE state before adding stock,
as described in section 7 of the design handbook. The B04 lock test exercises
this coordination with a controlled real database writer.


### Historical B04 selection verification (2026-09-13)

- `pytest --collect-only -q -m ci --strict-markers`: 22 selected, 93 deselected.
- `pytest --collect-only -q --strict-markers`: all 115 scenarios collected.
- Core execution on macOS/Python 3.11.16 with disposable PostgreSQL 18:
  **22 passed, 93 deselected in 3.15 seconds**.
- Workflow YAML parsed and automatic/manual conditions, triggers, and `test-job`
  name checked. No remote workflow was triggered by this change.
- The previous full-suite run passed all 115 in 20.02 seconds; it predates the
  marker-only selection change. Observed local durations from separate runs: 20.02 seconds for the full
  suite and 3.15 seconds for the core selection.
