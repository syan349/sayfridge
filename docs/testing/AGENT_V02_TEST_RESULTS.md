# Agent v0.2 verification — 2026-09-25

Validation used Python 3.11 and a task-owned PostgreSQL 16 instance on loopback,
with a separate `_test` database and disposable schemas. No production inventory
was used. Existing deployment receipt-table initialization is a separate step.

## Results

| Check | Result |
| --- | --- |
| Latest non-PostgreSQL suite | 131 passed |
| Agent real-database actions and HTTP/resume/state tests | 8 passed |
| Agent database tests plus existing batch-archive regression | 21 passed |
| Receipt setup script plus Agent API tests | 5 passed |
| Opt-in real model: exact consumption and model-knowledge estimation | 2 passed |
| Syntax, imports, OpenAPI, Windows Selector loop and diff whitespace | Passed |

These groups overlap and must not be added as a unique-test total. An earlier
full-suite run had 558 passes and two environment failures: the temporary cluster
used Pacific/Auckland while an existing test expected UTC serialization, and one
connection timed out. The temporary test database was switched to UTC; the failed
archive cases passed in the targeted regression above. The full suite was not
repeated after every subsequent Agent-only correction.

## Verified behaviors

- Paginated memory lookup beyond the first page, user isolation, conflict and
  missing-condition detection, bounded preload and same-turn cache invalidation.
- Runtime injection is hidden from model-facing schemas while public inputs remain
  strict. A generic confirmation cannot authorize a memory write. An explicit save
  survives cancellation of a separate inventory action.
- A request can contain successful, failed and waiting items. Resuming a confirmed
  estimate does not repeat previously successful items.
- Original quantity expressions are retained, estimates preserve the confirmed
  baseline, exact changes continue on an estimate, and reconciliation clears it.
- Stored structured ratios override incorrect model arithmetic; stale memory and
  missing confirmation prevent a write.
- Concurrent identical actions commit once. Receipt insertion failure rolls back
  the item's newly created space, definition and inventory together.
- Simulated crash after commit but before checkpoint update is recovered using a
  real PostgreSQL checkpointer; rebuilding the graph does not apply consumption twice.
- Typed resume rejects stale IDs and invalid selections; a valid target selection
  completes a precise operation without an extra confirmation. Other users cannot
  inspect/resume the conversation. Conversation locks work across connections.
- Existing-database setup handles check, cancellation, creation and incompatible
  column nullability using only a disposable schema.
- Real-model acceptance used synthetic stock. Exact consumption committed to
  confirmed state; absent user memory still produced a MODEL_KNOWLEDGE estimate
  that paused before writing.

## Commands

Configure TEST_DATABASE_URL for an isolated `_test` database before running:

```powershell
.\.venv\Scripts\python.exe -m pytest -q -m 'not postgres'
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_actions_postgres.py tests/test_agent_api_postgres.py
.\.venv\Scripts\python.exe -m pytest -q tests/test_inventory_batch_archive.py tests/test_agent_setup_postgres.py
$env:AGENT_LIVE_MODEL='1'
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_live_model.py
```

The live-model tests are skipped unless explicitly enabled and incur API usage.
