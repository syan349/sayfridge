# B07–B09 Inventory Test Results

## Scope and environment

Validated 2026-09-13 on the uncommitted working tree based on `dd292c1`, branch
`syan349_feat_backend_apis`. Python 3.11.16, pytest 9.1.1, macOS, PostgreSQL 18.
An isolated disposable local container supplied TEST_DATABASE_URL. Neon and real
application data were not used. Fixtures initialize the latest table definition in a fresh schema
and drop it after each scenario; the temporary container is removed after checks.

The delivery implements GET/POST `/api/v1/inventory-items` and GET/PATCH
`/api/v1/inventory-items/{id}`. The initial table definition includes nullable notes.
No quantity-operation, disposal, archival, batch, or initial ADD-history API is
included. Existing authentication, spaces, and catalog tests run in regression.

## Verification before schema simplification (historical)

Commands run from `backend` with an isolated TEST_DATABASE_URL:

| Command | Result |
| --- | --- |
| `python -m pytest -q --strict-markers --tb=short --junitxml=/tmp/sayfridge-inventory-full.xml` | 264 passed in 35.93 seconds |
| `python -m pytest -q -m ci --strict-markers --junitxml=/tmp/sayfridge-inventory-ci.xml` | 39 passed, 225 deselected in 5.99 seconds |

Inventory contributes 72 real PostgreSQL cases: 66 API scenarios and 6
concurrency/rollback/schema scenarios. The historical run below included a migration
test that has since been replaced by a notes-storage test. The current selection
contains eight inventory core scenarios and 64 full-suite-only scenarios. The full suite contains 253 PostgreSQL and 11
database-free cases. Tests do not substitute a mock database.

OpenAPI inspection verified four authenticated inventory operations and their
business validation schemas. The existing workflow still uses `test-job` with a
PostgreSQL 18 service; automatic runs select `-m ci`, manual dispatch runs all.
Workflow selection was unchanged. The durations above measure local pytest execution.

## Covered contracts

- Stock entry validates active/visible associations and initializes confirmed
  quantities, empty estimates, state, and version without creating ADD history.
- Decimal syntax/precision/range, string-only amounts, unit length, dates, notes,
  extra fields, and immutable fields are validated. Expired stock is allowed.
- Lists enforce ownership, literal search, category/space/state/date filters,
  inclusive boundaries, stable expiry ordering, pagination, and empty-page totals.
- Details remain visible for archived associations; current names are returned;
  a non-null zero estimate takes display priority.
- PATCH changes only metadata/location, clears nullable fields, preserves quantity
  facts, enforces expected_version, and leaves unchanged retries untouched.
- Foreign and missing inventory IDs are indistinguishable; terminal inventory
  cannot be edited. Version overflow is rejected while a no-op stays valid.
- EMPTY stock can leave archived spaces. Foreign or archived targets fail without
  partial metadata updates.
- Competing expected-version writes have one winner. Creation and moves wait on
  actual PostgreSQL space locks and recheck state after the wait.
- Test-only constraints force real database failures; rollback preserves state
  and the same session remains usable for a later successful write.
- Fresh schema initialization includes nullable notes. Saving a note through the
  ORM preserves quantities, confirmation time, and version; API version behavior
  is covered separately by the metadata tests.

## Outstanding deployment and manual acceptance

At this development stage, nullable `inventory_item.notes` was maintained in the
initial schema; Neon was unchanged. At the time of release, apply the selected
version's migrations using the [delivery runbook](../../delivery/README.md), and
record manual Postman acceptance and remote CI in the
[Final Acceptance Record](FINAL_ACCEPTANCE.md).

See the [API contract](../../reference/API_REFERENCE.md#6-inventory--b07b09),
[Postman guide](../POSTMAN_GUIDE.md), and [CI selection index](../README.md).

## Verification after schema simplification

The incremental notes revision was removed. The initial schema now includes notes;
the former migration test was replaced with a fresh-schema notes-storage test.
`python -m pytest -q --strict-markers --tb=short`: **264 passed in 55.34 seconds**
on disposable PostgreSQL 18. Core collection: **38 selected, 226 deselected**;
all selected tests also passed within the full run. No separate core timing was
measured. Eight of the 72 inventory scenarios are now core; 64 remain full-suite-only.
Neon and remote CI were not accessed. The temporary database was removed after testing.
