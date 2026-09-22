# B13 Inventory State Test Results

Date: 2026-09-21. Scope: the inventory discard endpoint on
`syan349_feat_backend_apis`. Inventory archival remains pending and B13 is not yet
complete as a whole.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_inventory_discard.py --strict-markers
```

## Coverage

- Successful `IN_STOCK` to `DISCARDED` transition and version increment.
- Preservation of initial, confirmed, and estimated quantities, timestamps,
  location, catalog associations, dates, and notes.
- No inventory operation history for discard.
- Rejection of EMPTY, DISCARDED, and ARCHIVED source states.
- Stale and maximum versions, invalid request bodies, authentication, and ownership.
- Discard from an archived space.
- Concurrent requests sharing one expected version have one winner.

## Verification status

All 16 discard scenarios passed in 103.82 seconds. Two representative scenarios
are marked for the core CI selection: the preservation lifecycle and concurrent
single-winner behavior. Full regression, remote CI, manual Postman acceptance, and
the inventory archive endpoint remain pending. No database structure change or
migration script is required.
