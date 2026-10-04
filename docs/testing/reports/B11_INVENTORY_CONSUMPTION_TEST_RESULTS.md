# B11 Inventory Consumption Test Results

Date: 2026-09-19. Scope: the uncommitted B11 working tree on
syan349_feat_backend_apis. Covers CONSUME submission through the existing
operations endpoint with AMOUNT or FRACTION. Preview, reconciliation, and history
query endpoints remain outside this change.

## Environment and commands

Python 3.11 on macOS with a disposable local PostgreSQL 18 container. An explicit
TEST_DATABASE_URL selected a dedicated test database. Each database test created
and removed its own schema. Neon and application data were not used.

Run from backend with an isolated TEST_DATABASE_URL:

```bash
python -m pytest -v tests/test_inventory_consumption*.py
python -m pytest -q --strict-markers
python -m pytest -q -m ci --strict-markers --junitxml=test-results.xml
```

The verification runs disabled bytecode and pytest cache writes. JUnit output was
written to a temporary path rather than the repository.

## Results

- Full regression: 408 passed in 54.18 seconds; 108 database-free and 300 PostgreSQL scenarios.
- This includes all 62 new B11 scenarios: 41 database-free and 21 PostgreSQL.
- Core regression: 49 passed, 359 deselected in 8.21 seconds; JUnit output generated.
- The core set adds five B11 scenarios to the existing 44. The workflow job name
  remains test-job; automatic CI still selects the ci marker, while manual workflow
  dispatch runs the full suite.
- Recorded execution: local pytest; remote Actions and manual Postman acceptance were not performed in this run.

An initial run exposed inconsistent decimal serialization between creation and
replay (2.5 versus 2.500). Normalizing the applied change to three decimal places
fixed the discrepancy; the final full regression above passed afterward.

## Coverage

| File | Behaviors |
| --- | --- |
| test_inventory_consumption_quantities.py | Decimal and fraction contracts; literal preservation; fixed remaining unit; four unit conversions; exact ratios; HALF_UP rounding; maximum quantity; effective zero estimate; insufficient balance before rounding; tiny changes and positive remainder protection |
| test_inventory_consumption.py | New submission and replay; confirmed EMPTY versus estimated zero IN_STOCK; preserved initial/confirmed facts and timestamps; stored fractional expression; state and version checks; archived catalog/space behavior; ownership; atomic validation failures; reusable failed keys; conflicting literal input and ADD/CONSUME keys |
| test_inventory_consumption_postgres.py | Identical concurrent requests apply once; distinct keys sharing a version have one winner; operation insertion failure rolls back quantity/version/timestamps and leaves the session usable |

The complete suite also reruns existing ADD concurrency, cross-space key collision,
lock-wait, and transaction tests against the shared submission service.

## Core CI and remaining acceptance

Five B11 core cases cover consume/replay lifecycle, estimated zero after full
consumption, over-consumption before rounding, concurrent identical requests,
and database insertion failure rollback. Boundary variants remain in the full suite.

The implementation record notes a GitHub Actions account billing restriction.
At the time of release, record remote CI and manual Postman acceptance for the
selected commit in the [Final Acceptance Record](FINAL_ACCEPTANCE.md). B11 used
the existing schema and migrations.
