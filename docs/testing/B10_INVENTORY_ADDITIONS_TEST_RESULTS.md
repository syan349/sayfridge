# B10 Inventory Addition Test Results

Date: 2026-09-15. Scope: current uncommitted B10 working tree on
syan349_feat_backend_apis. These results cover ADD submission, not the planned
preview, CONSUME, RECONCILE, or history query endpoints.

## Environment and commands

Python 3.11 on macOS, disposable local PostgreSQL 18 container. Tests use
TEST_DATABASE_URL and the existing per-test random schema fixtures. Neon and
application data were not used. No temporary exercise files are required.

Run from backend with an isolated TEST_DATABASE_URL:

```bash
python -m pytest -v tests/test_inventory_quantities.py tests/test_inventory_additions.py tests/test_inventory_additions_postgres.py
python -m pytest -v --strict-markers
python -m pytest -v -m ci --strict-markers --junitxml=test-results.xml
```

## Results

- Addition suite: 82 passed (56 database-free, 26 real PostgreSQL).
- Full regression: 346 passed in 77.42 seconds (67 database-free, 279 PostgreSQL).
- Core regression: 44 passed, 302 deselected in 12.12 seconds, including six B10
  cases. The separate core command generated JUnit output successfully.
- GitHub Actions and manual Postman acceptance have not been run for this change.

## Coverage

| File | Behaviors |
| --- | --- |
| test_inventory_quantities.py | Effective balance including zero estimates; four unit conversions; exact units; immutable calculation; three-place input syntax; ROUND_HALF_UP; tiny/overflow quantities; version and header syntax; unit trimming; forbidden fields |
| test_inventory_additions.py | 201 creation and 200 replay; original expressions and applied changes; current inventory on replay; internal key omission; estimate/confirmation timestamps; EMPTY restoration; terminal/archived space rejection; archived catalog compatibility; identity/ownership; version conflicts; failed keys remain reusable; literal and cross-item key conflicts; historical failed keys; sanitized errors |
| test_inventory_additions_postgres.py | Concurrent identical requests apply once; distinct keys with one version have one winner; cross-space key collision hits the real unique constraint and rolls back; operation insertion failure rolls back inventory and leaves the session usable; lock waits recheck space archival and inventory relocation; keys are user-scoped |

Concurrency checks use independent database sessions and synchronization points.
The archive/move checks inspect PostgreSQL blocking process IDs before releasing
locks. Failure injection adds a constraint only inside the disposable test schema.

## Core CI

Six B10 cases are marked ci: ADD/replay lifecycle, zero-estimate addition,
authentication/ownership/header checks, concurrent identical requests, atomic
operation-write failure, and archive-after-lock-wait. The existing test-job name
and workflow commands remain unchanged. Full tests remain available locally and
through manual workflow dispatch.

## Remaining acceptance

Manual Postman testing and remote CI are still pending. No database schema change
is needed for B10. The project owner resolved unit storage to trim surrounding
whitespace while preserving case; the preview response decision remains separate.
