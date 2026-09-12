# Backend Test Results

Store backend work package test and acceptance records in this directory. Prefix each report with its work package ID or range so files sort in development-task order rather than by feature name.

Naming convention: `Bxx[-Byy]_FEATURE_TEST_RESULTS.md`. For example, the authentication report covers B01–B03. Use actual agreed work package IDs for later reports; do not invent a new numbering system.

| Work packages | Report | Scope |
| --- | --- | --- |
| B01–B03 | [Authentication test results](B01-B03_AUTH_TEST_RESULTS.md) | Registration, login, current user, database integration, and recorded manual acceptance |
| B04 | [Storage-space test results](B04_STORAGE_SPACES_TEST_RESULTS.md) | Six space APIs, ownership, validation, pagination, PostgreSQL locking, uniqueness, and rollback |

Each report should state the validation date, tested commit or working-tree status, environment, commands, results, and outstanding checks. Clearly separate current results from historical runs, and local execution from remote CI. Add dated entries for later verification; update this index as more work packages are implemented.


## CI selection policy

Updated: 2026-09-13. Keep one set of test definitions and choose which scenarios
run using pytest markers; do not create a second CI-only implementation.

| Execution | Selection | Command from backend |
| --- | --- | --- |
| Local default | All 115 scenarios | `python -m pytest -v` |
| Local fast check | 22 core scenarios | `python -m pytest -v -m ci` |
| Automatic PR/main CI | Same 22 core scenarios | `python -m pytest -v -m ci --strict-markers` |
| Manual GitHub workflow dispatch | All 115 scenarios | `python -m pytest -v --strict-markers` |

The 93 unselected cases are retained, not skipped or disabled in the full suite.
The `ci` marker is registered in `backend/pytest.ini`. Mark a whole test with
`@pytest.mark.ci`, or an individual parameter with
`pytest.param(..., marks=pytest.mark.ci)` to avoid pulling every boundary variant
into the core set. No default marker filter is configured in pytest.ini.

### Core scenarios

Prioritize authentication and authorization, representative successful workflows,
unsafe input, atomic failure handling, and data-corruption risks. Include one
representative enum/boundary case where the implementation is shared, while
retaining all ownership operations and critical archive/stock coordination.

| Work package | Selected scenario | Cases |
| --- | --- | ---: |
| B01–B03 | Registration/login/current-user database lifecycle, duplicate registration, wrong credentials, current role/state, and deleted user within one workflow | 1 |
| B01–B03 | Public registration cannot create an administrator | 1 |
| B01–B03 | Current user rejects missing, invalid, and expired tokens | 3 |
| B01–B03 | Forged token signature is rejected | 1 |
| B04 | Create FRIDGE: trim name, set owner/state, expose only public fields | 1 |
| B04 | Reject client-supplied owner ID without writing data | 1 |
| B04 | Read an owned archived space | 1 |
| B04 | Foreign and missing IDs yield identical 404 for detail, PATCH, archive, and restore | 4 |
| B04 | Creating a space requires authentication | 1 |
| B04 | List ownership/state filtering, deterministic pagination, and out-of-range pages | 1 |
| B04 | PATCH rejects null name without changing data | 1 |
| B04 | Partial PATCH, no-op behavior, conflicting name, and atomic rollback | 1 |
| B04 | Archive/restore lifecycle, retries, unchanged timestamps, and archived PATCH rejection | 1 |
| B04 | Restoring a conflicting name retains archived state | 1 |
| B04 | IN_STOCK inventory blocks archival and remains unchanged | 1 |
| B04 | Concurrent case-insensitive same-name creation has one winner | 1 |
| B04 | Archival waits on a real space lock and rechecks newly committed stock | 1 |
| **Total** | **6 authentication + 16 storage-space scenarios** | **22** |

The core set includes 21 real PostgreSQL fixture cases and one database-free token
signature test. CI still uses its disposable PostgreSQL 18 service, never Neon.
Required check name `test-job` is preserved. Automatic checks upload the core JUnit
report; manual dispatch uploads the full report.

### Maintenance

- Run the full suite locally before requesting review, particularly for shared
  authentication, transaction, schema, or validation changes.
- When adding a feature, mark a small number of critical scenarios and retain its
  other variants in the full suite. Review marker selection when risks change.
- A core-only CI pass does not assert that the full suite passed. Use a manual
  full workflow run when remote full-suite evidence is needed.
- Inspect the actual selection with `python -m pytest --collect-only -q -m ci`.
- Reduced execution does not remove runner, PostgreSQL startup, or installation
  overhead. Measure remote PR time separately from local pytest time.


### Selection verification (2026-09-13)

- `pytest --collect-only -q -m ci --strict-markers`: 22 selected, 93 deselected.
- `pytest --collect-only -q --strict-markers`: all 115 scenarios collected.
- Core execution on macOS/Python 3.11.16 with disposable PostgreSQL 18:
  **22 passed, 93 deselected in 3.15 seconds**.
- Workflow YAML parsed and automatic/manual conditions, triggers, and `test-job`
  name checked. No remote workflow was triggered by this change.
- The previous full-suite run passed all 115 in 20.02 seconds; it predates the
  marker-only selection change. The two timings are local observations, not a
  controlled benchmark or a prediction of total GitHub Actions duration.
