# B05–B06 Catalog Test Results

## Delivery and environment

Validation date: 2026-09-13. These results cover the uncommitted B05–B06 working
tree on `syan349_feat_backend_apis`, based on commit `12d45a0`. They do not assert
that the remote branch or GitHub Actions has tested these changes.

Environment: macOS, Python 3.11.16, pytest 9.1.1, and PostgreSQL 18 in a disposable
local Docker container. `TEST_DATABASE_URL` pointed only to that container.
Neon and application data were not used. Existing fixtures create a separate
schema, apply Alembic migrations, and drop that schema after each scenario.
The container was removed after verification. No database migration was added.

## Commands and results

Run from the repository's `backend` directory with `TEST_DATABASE_URL` configured
for an isolated test database, or use the ignored local `.env.test` configuration.
Never point these tests at application data.

| Scope | Command | Result |
| --- | --- | --- |
| Catalog API behavior | `python -m pytest -q tests/test_catalog_api.py --strict-markers` | 67 passed in 9.67 seconds |
| Catalog database coordination | `python -m pytest -q tests/test_catalog_postgres.py --strict-markers` | 10 passed in 1.46 seconds |
| Full regression | `python -m pytest -q --strict-markers --tb=short --junitxml=/tmp/sayfridge-b05-b06-full.xml` | 192 passed in 22.13 seconds |
| CI selection | `python -m pytest -v -m ci --strict-markers --junitxml=/tmp/sayfridge-b05-b06-ci.xml` | 30 passed, 162 deselected in 4.13 seconds |

The delivery adds 77 scenarios. All 77 use real PostgreSQL; the database is not
replaced by a mock session. The full suite includes 181 PostgreSQL scenarios and
11 database-free scenarios. Eight new catalog scenarios join the core selection;
the remaining 69 run in local full regression and manual full CI.

## Coverage

| Area | Verified behavior |
| --- | --- |
| B05 categories | Authentication, public response fields, ACTIVE/ARCHIVED/ALL filters, deterministic ordering, pagination, invalid queries, and out-of-range totals |
| B06 definition queries | Public plus current-user private visibility; scope/category/state filters; archived-category behavior; deterministic ordering; literal case-insensitive search; detail reads of archived records; foreign IDs hidden |
| Private writes | Owner and ACTIVE state assigned by the server, active-category requirement, partial updates, invalid/null/extra fields rejected, and identical 404 responses for public/foreign/missing write targets |
| Name rules | NFKC/trim/casefold normalization, normalized length limits, legacy-key compatibility, archived name reservation, per-owner uniqueness across categories, and allowed public/other-owner names |
| State transitions | Archive/restore persistence, body rejection, unchanged retry timestamps, archived-definition editing blocked, restore requiring an active category, and name-only edits retaining their existing category |
| Inventory preservation | Archiving a definition leaves linked inventory status, quantity, version, and reference unchanged |
| Concurrency | Competing create/rename operations in different categories have one winner; real category-lock waits recheck state and changed relationships |
| Failure recovery | Unrelated PostgreSQL constraint failures roll back and remain database errors; the same session can perform a subsequent successful write |
| Snapshot consistency | Definition/category page rows and totals are obtained in one SQL statement, including empty pages |
| Regression | Existing B01–B04 behavior remains passing after sharing the empty-body dependency and extending business validation handling |

Concurrency tests coordinate execution to exercise specific race conditions but
still execute actual SQL, row locks, unique indexes, and transactions. Test-only
constraints verify rollback and are discarded with their isolated schemas.

## CI and remaining acceptance

The existing workflow automatically discovers the new tests. It needs no YAML
change: pull requests and pushes to main select `-m ci`; manual workflow dispatch
runs the full suite. The job ID remains `test-job`, and CI uses its temporary
PostgreSQL 18 service without Neon credentials. See the [selection index](../README.md)
for the full list of core scenarios.

Local OpenAPI inspection verified all seven catalog operations, their Bearer
security requirements, and business validation response schemas. Manual Postman
acceptance of B05–B06 and remote CI verification remain pending. Use the
[API reference](../../reference/API_REFERENCE.md#5-item-definitions--b06) for
request examples. An active category must already exist through approved data
initialization; B05 does not add category-management endpoints or seed shared data.
