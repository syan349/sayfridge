# B25 Administrator Account Test Results

Date: 2026-09-24. Tested the B25 working tree on
`syan349_feat_backend_apis`.

## Environment and command

Python 3.11 on macOS with the configured isolated PostgreSQL test database. Each
scenario used a freshly migrated random schema and removed it afterward.

Run from `backend`:

```bash
python -m pytest -v tests/test_admin_users.py --strict-markers
```

## Coverage

- ADMIN-only access with 401 authentication and 403 authorization boundaries.
- Safe account list/detail responses without passwords, quotas, or inventory.
- Literal case-insensitive email search and role/status filters.
- Deterministic newest-first pagination, accurate empty pages, and one-statement
  count/page reads.
- ACTIVE, SUSPENDED, and DISABLED ordinary-user state management.
- Immediate enforcement of changed account state on subsequent authentication.
- Idempotent same-state updates preserving updated_at.
- Rejection of administrator targets, invalid bodies, queries, and identifiers.
- Database persistence without role changes or audit records.

## Verification status

All 9 B25 scenarios passed locally in 56.00 seconds. Three representative scenarios
are marked for the core selection.

On 2026-09-24, GitHub Actions execution was blocked by the organization's
exhausted quota. This change used the existing schema and migrations. At the time
of release, record Full Regression and manual Postman acceptance for the selected
commit in the [Final Acceptance Record](FINAL_ACCEPTANCE.md).
