# B13 Inventory State Test Results

Date: 2026-09-22. Scope: inventory discard and archive endpoints on
`syan349_feat_backend_apis`.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_inventory_discard.py tests/test_inventory_archive.py --strict-markers
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
- Successful archival from both IN_STOCK and EMPTY while preserving the same facts.
- Rejection of DISCARDED and already ARCHIVED source states.
- Archive request validation, authorization, version boundaries, archived-space
  behavior, and concurrent single-winner behavior.

## Verification status

All 16 archive scenarios passed in 100.97 seconds. The 16 discard scenarios also
passed again in 99.83 seconds after the shared transaction refactor. Four
representative scenarios are marked for the core CI selection: one preservation
lifecycle and one concurrent single-winner case for each endpoint. B13 used the existing schema and migrations. At the time of release, record Full
Regression, remote CI and manual Postman acceptance for the selected commit in the
[Final Acceptance Record](FINAL_ACCEPTANCE.md).
