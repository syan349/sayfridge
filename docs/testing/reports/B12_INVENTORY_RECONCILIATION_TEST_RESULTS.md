# B12 Inventory Reconciliation Test Results

Date: 2026-09-21. Scope: the uncommitted B12 working tree on
syan349_feat_backend_apis. RECONCILE confirms a nonnegative total through the
existing inventory operations endpoint. Preview and history queries remain outside
this change.

## Environment and commands

Database-free request and quantity checks use Python 3.11. PostgreSQL acceptance,
concurrency, and rollback tests use the existing isolated TEST_DATABASE_URL setup;
Uvicorn is not required.

Run from backend:

```bash
python -m pytest -v tests/test_inventory_reconciliation*.py
python -m pytest -v --strict-markers
python -m pytest -v -m ci --strict-markers
```

## Coverage

| File | Behaviors |
| --- | --- |
| test_inventory_reconciliation_quantities.py | Nonnegative decimal contract; zero support only for RECONCILE; maximum and precision limits; direct total preparation without conversion |
| test_inventory_reconciliation.py | Confirmation and estimate clearing; unit replacement; zero/positive state; unchanged physical confirmation; EMPTY and archived-space rules; version, terminal state, ownership, literal retry conflicts, and successful replay |
| test_inventory_reconciliation_postgres.py | Concurrent identical requests apply once; operation insertion failure rolls back confirmed/estimated fields, timestamps, version, and history, then permits retry |

Four representative B12 scenarios are marked for the core CI selection: full
confirmation/replay, EMPTY restoration blocked in an archived space, concurrent
identical requests, and operation-write rollback. Boundary variants remain in the
full suite.

## Verification status

Fourteen B12 database-free scenarios passed during implementation. The complete
database-free regression also passed: 122 passed and 317 deselected in 0.38
seconds. The full regression, including real PostgreSQL scenarios, passed: 439
passed in 1893.58 seconds (31 minutes 33 seconds). The suite contains 31 new B12
scenarios and four new B12 core scenarios; collection found 53 core scenarios in
total. B12 used the existing schema and migrations. At the time of release, record remote
CI and manual Postman acceptance for the selected commit in the
[Final Acceptance Record](FINAL_ACCEPTANCE.md).
