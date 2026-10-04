# Agent v0.2 verification — 2026-09-25

Validation used Python 3.11 and a task-owned PostgreSQL 16 instance on loopback,
with a separate `_test` database and disposable schemas. No production inventory
was used. Existing deployment receipt-table initialization is a separate step.

## Stock-entry repair verification — 2026-09-28

Environment: Python 3.11, task-owned PostgreSQL 16 on loopback, a separate
`sayfridge_agent_test` database and per-test disposable schemas. The test database
uses UTC. Shared Neon data and application schemas were not modified. Live checks
used the configured `gpt-6-luna` model with synthetic products and inventory.

Latest full backend regression: **609 passed, 18 skipped in 555.80 seconds**.
The skipped cases are the opt-in live checks, separately verified below.

Verified changes:

- Intake records all stock items before the ordinary model/tool loop; a prose-only
  clarification cannot end an inventory task with no tracked work.
- Missing locations stay `NEEDS_INPUT`, retain quantity and item identity, and
  expose the same short `display.question` through SSE, state and replay.
- A user-specified new fridge and an unambiguous new product are created with the
  stock transaction, without name/category or new-space confirmation. Existing
  visible definitions are reused; receipt failure rolls back all dependencies.
- Task-scoped user text is required for new spaces; model/image/tool text is not
  accepted as its source. Genuine category/storage ambiguity still waits for input.
- Completion text uses committed results. A real-model run exposed a stale
  "awaiting confirmation" reply after successful insertion; receipt-derived
  summaries now prevent that contradiction and retain estimated-balance labels.
- Legacy confirmation previews, image review, estimate confirmation, ownership,
  independent item outcomes, restart recovery and idempotency remain covered.

Live screenshot reproduction (English and Chinese, each with a report first):

| Step | English | Chinese |
| --- | --- | --- |
| Purchase | I just bought 2 kg of tomatoes | 我刚买了2公斤西红柿 |
| Pending question | Where would you like to store Tomatoes? | 西红柿放在哪里？ |
| User answer | Put them in the fridge | 放冰箱里 |
| Result | SUCCEEDED; one 2.000 kg batch | SUCCEEDED; one 2.000 公斤 batch |
| Completion | Added 2 kg of Tomatoes to Fridge. | 已将2 公斤 西红柿加入冰箱。 |

No item definition, space or stock was written before the missing-location answer.
The screenshot cases assert the saved category, quantity, receipt count and reply,
not only a model statement of success. Chinese quantity units are preserved and
compared through the existing standard-unit normalization.

The updated focused workflow/transaction/HTTP/multimodal regression passed 27
cases before three additional defensive workflow cases were added. Three old
full-suite failures were resolved and rerun successfully: a superseded new-category
confirmation expectation, local test database timezone serialization, and an
expired authentication token after a long test-process interruption. Application
authentication and inventory serialization were not changed to accommodate tests.

Final combined opt-in live run: **18 passed in 134.65 seconds**, covering 12
text/intake/stock cases and 6 image cases in one process. A session-scoped event
loop prevents cached model HTTP clients from crossing closed test loops. Earlier
API timeout/DNS failures were superseded by this clean combined run. The
estimate-intake prompt was clarified so "wait for confirmation" and "do not save
memory" do not negate the requested consumption task.

The final overflow correction also passed the 17-case workflow/image-workflow
selection: both intake-detected and later proposal-detected overflow request
groups of at most 20, without executing a partial set.

Commands (from `backend`, with an isolated `TEST_DATABASE_URL`):

```powershell
python -m pytest -q -p no:cacheprovider
python -m pytest --collect-only -q -m ci
$env:AGENT_LIVE_MODEL='1'
python -m pytest -q tests/test_agent_live_model.py tests/test_agent_multimodal_live.py
```

Three regression cases are now marked `ci`; collection confirms 79 selected
cases out of 627 total. Live-model tests remain opt-in. These results are local
verification, not CI, deployment, or validation of the classmate's mobile build.

## Historical results — 2026-09-25

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

## Context and incremental state verification — 2026-10-04

### Later budget adjustment — 2026-10-04

The final user-selected configuration raises only the application cap to 150K
and trigger to 120K. The 50K soft target, 10K summary, 10K recent history and 20K
summary generation allowance remain unchanged. Code defaults and local overrides
were synchronized; targeted context/summary/quantity regressions passed after
updating the threshold-dependent fixtures. No hosted configuration was changed.

After the verification run below, the user selected a 100K application cap, 80K
trigger, 50K soft target, and 10K each for visible summary and recent history.
Summary generation now has a separate 20K allowance for reasoning plus visible
text; ordinary output remains 8K. Reasoning effort/temperature stay unspecified.
Code defaults, the example and local budget overrides were updated; hosted
configuration was not changed. Non-PostgreSQL regressions passed 373 cases
(602 deselected). No paid model calls were made for this adjustment.

Using the configured model's tokenizer locally, fixed rules/tools were 8,132
tokens (8,445 with cards). With 10K summary plus 10K history, estimated input is
28,132/28,445 tokens; conservative budget including 8K output and 4,096 reserve
is 47,261/47,653. Necessary task evidence/images add to those figures. The actual
SDK summary request was inspected without sending it: generation limit 20,000,
no explicit reasoning or sampling settings. The earlier 50K-run figures below
remain historical evidence, not fresh 100K PostgreSQL/live-model acceptance.

### Original 50K implementation verification

Changes are based on `f5846e7`. No frontend files, ORM models, migrations, or shared
database data were changed. No push or deployment was performed. Detailed counts
and the representative benchmark are in
[the verification record](../evidence/backend-release-readiness/context-state-optimization-2026-10-04.json).

| Check | Observed result |
| --- | --- |
| Baseline non-PostgreSQL tests | 360 passed |
| Complete offline backend run, local PostgreSQL 16 / Python 3.11 | 905 passed, 68 live-model cases skipped; 986.64 seconds |
| Final CI subset | 226 passed, 749 deselected; 247.00 seconds |
| Unchanged Web consumers | 3 passed |
| Unchanged Mobile consumers | 3 passed |
| Captured actual backend responses | 159 responses, including 98 successful SSE streams |
| Shared business schema / Agent storage | Read-only checks passed; no migrations applied |
| Real-model summary fidelity | Not run; release quality acceptance remains open |

The full run began before two final regression cases were added; both additional
cases passed separately and in the final CI subset. Existing client tests were
run without modifying client source, tests or dependency files.

The 200-turn synthetic graph benchmark uses real isolated PostgreSQL tables and
compares identical final accumulated records. Target-field blob plus write bytes
fell from 57,962,360 to 949,427 (98.36% reduction, above the 70% requirement).
Total serialized checkpoint/blob/write payload fell from 87,481,767 to 1,844,972
bytes. Both runs retained 600 checkpoints. Nine warmed reads gave median latest
state recovery of 4.07 ms versus 9.92 ms, within `baseline * 1.25 + 100 ms`.
Measurement scope: serialized local checkpoint size. Physical disk usage, hosted
latency and long-term checkpoint growth require separate measurements.

Tests cover update boundaries 49/50/51, reconstruction with a new saver/connection,
legacy full-state upgrade, old pending confirmation executed exactly once, mixed
history recovery, and frequency-1 delta-aware rollback. One picture followed by
100 text turns produces only one image-collection update. A PostgreSQL cursor
deadlock discovered during recovery validation was fixed by finishing checkpoint
listing before nested graph-state hydration.

Production-budget deterministic tests cover tokenized schema accounting, bounded
recent history, summary correction/failure preservation, complete tool groups,
protected evidence, omission notices, canonical result preservation and 20-item
execution. A synthetic compaction example reduced measured budget from 87,676 to
27,636 with 3,846 recent-history tokens. Its seven-token mock summary validates
accounting/control flow only, not real summary quality. A configured-tokenizer
check without model calls measured short requests at 22,282 budget units (22,673
with inventory cards), including reserves, under the 50,000 application cap.

Opt-in live acceptance now covers three cumulative summary cycles in English and
Chinese, name corrections, quantities, pending rice and cancelled milk tasks.
Run `AGENT_LIVE_MODEL=1` only for an explicitly approved model-cost run against the
isolated test database. Until then, do not describe summary fidelity as validated.
Deployment must explicitly update old environment overrides and keep delta-aware
code for rollback; see the Backend README. Old checkpoint pruning is not included.
