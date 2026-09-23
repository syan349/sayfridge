# B15 Inventory Batch Test Results

Date: 2026-09-23. Current scope: atomic batch creation on
`syan349_feat_backend_apis`. Batch move and batch archive remain pending.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_inventory_batch_create.py --strict-markers
```

## Coverage

- Creation of 1–100 entries with the existing InventoryCreate validation rules.
- Input-order responses, normalized units, version/state initialization, and count.
- Multiple identical entries representing separate physical stock batches.
- No quantity-operation history for stock entry.
- Owned spaces and visible definitions, with foreign and missing resources hidden.
- ACTIVE space, category, and definition requirements.
- Whole-batch rollback when any entry fails.
- Zero-based item_index on entry-specific validation and business errors.
- Authentication and rejection of empty, oversized, or malformed requests.

## Verification status

All 11 batch-create scenarios passed locally in 67.35 seconds. Three representative
scenarios are marked for the core selection: successful ordered creation, atomic
rollback for a missing space, and rollback for an archived definition. Full
regression and manual Postman acceptance remain pending. GitHub Actions is currently
unavailable because the organization has exhausted its Actions quota. No database
structure change or migration script is required.
