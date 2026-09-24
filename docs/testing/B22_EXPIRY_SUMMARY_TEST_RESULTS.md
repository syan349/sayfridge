# B22 Expiry Summary Test Results

Date: 2026-09-24. Tested the B22 working tree on
`syan349_feat_backend_apis`.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_inventory_expiry_summary.py --strict-markers
```

## Coverage

- Overdue, today, and inclusive upcoming-window classification.
- Default and zero-day windows, maximum legal dates, and overflow rejection.
- Current-user ownership with optional storage-space and category filters.
- IN_STOCK and known-expiry requirements, including archived associations.
- Bucket filtering that leaves all-bucket counts unchanged.
- Deterministic expiry-date/ID ordering, pagination, and accurate empty pages.
- Safe validation failures and authentication enforcement.
- Counts, filtered total, and page returned by one database statement.
- Read-only behavior with no reminders, notifications, scheduled jobs, or writes.

## Verification status

All 8 B22 scenarios passed locally in 61.06 seconds. Three representative scenarios
are marked for the core selection. The complete regression suite and manual Postman
acceptance remain pending. GitHub Actions is currently unavailable because the
organization has exhausted its Actions quota. No database structure change or
migration script is required.
