# B14 Inventory History Test Results

Date: 2026-09-22. Scope: item-scoped history, global filtered history, and operation
detail endpoints on `syan349_feat_backend_apis`.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_inventory_item_history.py tests/test_inventory_operation_history.py --strict-markers
```

## Coverage

- Deterministic `created_at DESC, id DESC` ordering.
- SUCCESS, PENDING_CONFIRMATION, FAILED, and UNDONE history visibility.
- Empty history and history retained for DISCARDED or ARCHIVED inventory.
- Public operation fields with the internal idempotency key omitted.
- Authentication, ownership isolation, missing resources, and invalid UUID input.
- Owned-only global history with stable pagination and accurate filtered totals.
- Inventory, operation-type, status, and half-open timestamp filters.
- Timezone-aware timestamps and rejection of invalid, reversed, or unknown queries.
- Owned operation detail in every inventory/association state, with foreign and
  missing operation IDs producing identical responses.

## Verification status

All 7 item-scoped history scenarios passed in 44.40 seconds. All 17 global
list/detail scenarios passed in 112.77 seconds. Four representative scenarios are
marked for core CI: ordering/field exposure and resource isolation for both route
groups. Full regression, remote CI, and manual Postman acceptance remain pending.
No database structure change or migration script is required.
