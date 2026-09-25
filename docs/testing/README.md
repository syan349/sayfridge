# Backend Testing

## Reports

| Work packages | Report | Scope |
| --- | --- | --- |
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

Manual requests: [Postman guide](POSTMAN_GUIDE.md).
Setup and database configuration: [backend README](../../backend/README.md).

## Run tests

Run commands from `backend`. Uvicorn does not need to be running.

| Execution | Selection | Command |
| --- | --- | --- |
| Local full regression | Current suite; live-model tests require explicit opt-in | `python -m pytest -v` |
| Local core check | 76 scenarios | `python -m pytest -v -m ci` |
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

Use one test implementation for local and CI runs. Mark a small set covering
permissions, representative workflows, atomic failures, and concurrency risks.
Keep boundary variants in the full suite. The remaining 475 scenarios still run
in full regression; a core pass alone is not evidence of a full-suite pass.

| Feature | Core scenarios |
| --- | ---: |
| Authentication | 6 |
| Storage spaces | 16 |
| Catalog | 8 |
| Inventory | 8 |
| Inventory additions | 6 |
| Inventory consumption | 5 |
| Inventory reconciliation | 4 |
| Inventory discard | 2 |
| Inventory archive | 2 |
| Item operation history | 2 |
| Global operation history | 2 |
| Inventory batch create | 3 |
| Inventory batch move | 3 |
| Inventory batch archive | 3 |
| Inventory expiry summary | 3 |
| Administrator accounts | 3 |
| **Total** | **76** |

Use `@pytest.mark.ci` for a whole test or `pytest.param(..., marks=pytest.mark.ci)`
for selected parameters. The marker is registered in `backend/pytest.ini`;
there is no default filter. Check the actual selection with:

```bash
python -m pytest --collect-only -q -m ci --strict-markers
```

The required GitHub job remains `test-job`. Automatic/manual runs upload their
respective JUnit results. Run full regression locally before requesting review.

## Maintain reports

Name reports `Bxx[-Byy]_FEATURE_TEST_RESULTS.md`. Record the date, tested commit or
working tree, environment, commands, outcomes, and outstanding acceptance checks.
Keep detailed scenarios and historical timings in the feature reports, not this
index. Distinguish local results from remote CI. Update current counts here when
selection changes; test collection is the source of truth.
