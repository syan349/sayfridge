# Database isolation and acceptance evidence

This document defines the release checks for database tasks 6.3–6.5. It does not
contain credentials or live application data.

## Environment isolation

| Purpose | Connection source | Required isolation | Data lifecycle |
| --- | --- | --- | --- |
| Local development | `DATABASE_URL` / `DATABASE_URL_DIRECT` in ignored `backend/.env` | Developer-owned database | Persistent until the developer resets it |
| Backend tests and GitHub CI | `TEST_DATABASE_URL` | Direct PostgreSQL database whose name ends in `_test`; each test owns a random migrated schema | Test schema is dropped during fixture teardown |
| End-to-end CI | `E2E_DATABASE_URL` | Direct PostgreSQL database whose name ends in `_e2e`; it must differ from the runtime/predeploy target | Reset by the E2E job only |
| Predeploy acceptance | Vercel/Neon secrets | Dedicated Neon predeploy branch used by people and deployed clients | Reset only through the reviewed demo/reset process |

`app/db/database_target.py` enforces the disposable database naming and direct
connection rules without printing credentials. The E2E runner must call
`validate_disposable_database_url(..., DatabasePurpose.E2E,
runtime_database_url=...)` before migrations, seed, reset, or tests. GitHub CI
continues to use its disposable PostgreSQL service and never connects to Neon.

## Read-only acceptance record

After initialization and seed, generate an evidence file from `backend`:

```bash
python scripts/record_database_acceptance.py \
  --environment predeploy \
  --initialized-at 2026-09-28 \
  --output ../docs/testing/evidence/database-acceptance.json
```

The operator supplies the actual initialization date because the current Alembic
table stores revision identifiers, not migration timestamps. For local, predeploy
and acceptance records the script reads `DATABASE_URL_DIRECT`; `ci` reads the
isolated `TEST_DATABASE_URL`, and `e2e` reads the isolated `E2E_DATABASE_URL`
through the same target guard. It starts a read-only transaction and records:

- environment, initialization date, application commit and credential-free target;
- current Alembic revision and expected head;
- content-addressed category seed version, count and drift;
- verified table, column, constraint, foreign-key and index counts.

The command exits nonzero when migration or seed state differs from the repository.
At the time of release, generate a new acceptance record for the selected commit
after migration, seed and schema verification. Operational procedures are maintained
in the [delivery runbook](../../delivery/README.md).

## Transaction and retry acceptance matrix

The `database_acceptance` pytest marker selects the existing real-PostgreSQL tests
that prove the following guarantees. These cases also carry the `ci` marker and run
for pull requests and pushes to `main`.

| Guarantee | Acceptance test |
| --- | --- |
| Batch create rolls back earlier inserts after a later failure | `test_batch_create_rolls_back_every_item_and_reports_failing_index[missing_space-404-NOT_FOUND]` |
| Batch move leaves the first item unchanged after a later stale-version failure | `test_batch_move_rolls_back_first_item_when_later_item_fails[stale-409-VERSION_CONFLICT]` |
| Batch archive leaves the first item unchanged after a later stale-version failure | `test_batch_archive_rolls_back_first_item_when_later_item_fails[stale-409-VERSION_CONFLICT]` |
| ADD update/history insert commit together and failed insert permits retry | `test_operation_insert_failure_rolls_back_inventory_and_session_recovers` |
| CONSUME update/history insert commit together and failed insert permits retry | `test_consumption_insert_failure_rolls_back_and_allows_retry` |
| RECONCILE update/history insert commit together and failed insert permits retry | `test_reconciliation_insert_failure_rolls_back_and_allows_retry` |
| Concurrent identical ADD and CONSUME requests apply once | the `same_key=True` concurrency cases |
| Concurrent identical RECONCILE requests apply once | `test_concurrent_identical_reconciliations_apply_once` |

Run only this matrix from `backend` with:

```bash
python -m pytest -v -m database_acceptance --strict-markers
```
