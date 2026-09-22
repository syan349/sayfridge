# B14 Inventory History Test Results

Date: 2026-09-22. Scope: `GET /inventory-items/{id}/operations` on
`syan349_feat_backend_apis`. The global history list and operation-detail endpoints
remain pending, so B14 is not yet complete as a whole.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_inventory_item_history.py --strict-markers
```

## Coverage

- Deterministic `created_at DESC, id DESC` ordering.
- SUCCESS, PENDING_CONFIRMATION, FAILED, and UNDONE history visibility.
- Empty history and history retained for DISCARDED or ARCHIVED inventory.
- Public operation fields with the internal idempotency key omitted.
- Authentication, ownership isolation, missing resources, and invalid UUID input.

## Verification status

All 7 item-scoped history scenarios passed in 44.40 seconds. Two representative
scenarios are marked for core CI: ordering/field exposure and foreign-resource
isolation. Full regression, remote CI, manual Postman acceptance, the global history
list, and operation detail remain pending. No database structure change or migration
script is required.
