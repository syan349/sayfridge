# SayFridge Agent v0.2: workflow and client contract

This document describes the six-node implementation. Business calculations and
transactions belong to backend services; LangGraph coordinates the conversation.
Frontend pages and historical recalculation are outside this release.

## Workflow

`__start__ -> prepare_context -> agent` is the entry path. Queries and memory tools
loop through `agent -> tools -> agent`. Inventory proposals go to
`prepare_operation`; ready items go to `execute_operation`; unresolved items go to
`await_user`. Executed results return to `agent` for the next item or final answer.
The waiting node uses a persisted LangGraph interrupt, not a long-running HTTP wait.

- Each turn accepts up to 20 items. Items execute independently, in input order
  among runnable items. One failure never rolls back another successful item.
- CREATE_STOCK initializes initial and confirmed quantities together; no ADD event
  is fabricated. Explicit count units such as bags can be recorded directly.
- Without an estimate, exact or deterministic converted changes update confirmed
  quantity. An approved uncertain change starts the estimated balance.
- With an estimate, every ordinary change continues from the estimate. Only an
  actual RECONCILE establishes a new confirmed balance and clears the estimate.
- Fixed conversions support g/kg, ml/l and their Chinese standard-unit spellings.
  User-specific cup/weight and other empirical relations remain AI_ESTIMATED.
- Estimates and proposed new private definitions/spaces require confirmation of
  the exact proposal ID. Resolving an otherwise exact target adds no confirmation.
- A user-confirmed estimate is not a stocktake and does not request memory storage.

## Memory

Store namespace: `("users", authenticated_user_id, "memories")`. The model cannot
choose the user or namespace. Records are versioned JSON supporting
UNIT_RELATIONSHIP, USAGE_PREFERENCE and ENTITY_ALIAS; existing v1 records remain
readable. A specific item is an applicability condition, not its own namespace.

At turn entry, at most 20 relevant records and 4,000 characters are supplied to the
model, with an explicit truncation flag. Before preparing a quantity action, the
memory service performs paginated applicability checks, not just a first-50 scan.
Same-turn context is cached; memory changes invalidate it. Resuming a proposal
checks the chosen memory snapshots again before writing.

Unit conditions include item ID/name, space, source/target units, utensil and date
range. Stable item IDs take precedence over historical display names. Compatible
g/kg and ml/l target units can share a remembered relation. Missing utensil/date
information is reported; equally specific conflicting relations require input.
More specific applicable relations outrank broad ones. Explicit current user
information can supply an estimate without rewriting an old memory.

`structured_value` for a unit relation uses decimal strings:

```json
{"source_amount":"1","source_unit":"cup","target_amount":"100","target_unit":"g"}
```

An alias uses `alias`, `target_type` (SPACE or ITEM_DEFINITION), and `target_id`.
The referenced target must be visible to the authenticated user. A global batch
preference can use `{"batch_selection":"EARLIEST_EXPIRY"}`; ties still need a
choice. Conditions and text remain available for more specific preferences.

No applicable memory allows a MODEL_KNOWLEDGE estimate, which still needs user
confirmation. Lookup failure retries once and then leaves the affected item
waiting; failure is not treated as absence. No vector index is required.

Saving/deleting memory requires an explicit current user instruction, including an
`authorization_quote` copied from that message. The quote must contain a supported
Chinese or English memory instruction (for example “记住” or “remember”). Generic
approval is insufficient. Structured saves are content-deduplicated and replay-safe.
Memory changes and inventory changes report their outcomes separately. Cancelling
stock work does not undo an explicit memory save.

## HTTP and SSE

All routes require the existing Bearer authentication. User identity is taken from
authentication. Client-supplied IDs never bypass ownership checks.

### POST /api/v1/agent/chat

```json
{"message":"I used two cups of rice","conversation_id":"<uuid>","request_id":"<uuid>","as_of":"2026-09-25"}
```

Only message is required. Clients should generate request_id before sending and
reuse it with an identical body for retries. If omitted, the server generates it.
The start event returns request_id and conversation_id. Supplying request_id without
conversation_id produces a stable initial conversation for that user/request.
`as_of` is a client-provided date, not an inferred server-local date.

A new message on an interrupted conversation returns 409 AGENT_INPUT_REQUIRED;
use resume. A running conversation returns 409 AGENT_CONVERSATION_BUSY. An
unfinished crashed turn returns AGENT_RECOVERY_REQUIRED for a different request;
retry its original request ID. Reusing an ID with different contents returns
REQUEST_ID_CONFLICT.

### POST /api/v1/agent/resume

```json
{
  "conversation_id":"<uuid>",
  "interrupt_id":"<current interrupt id>",
  "request_id":"<new response uuid>",
  "responses":[{"item_id":"<uuid>","proposal_id":"<uuid>","decision":"confirm"}]
}
```

Supported decisions are confirm, answer, edit and cancel. Confirm/cancel carry only
identifiers. Answer/edit require message, or selected_inventory_item_id from the
current question's candidate list. Selecting a candidate still revalidates ownership.
Each item may appear once. Partial answers are allowed; other questions remain pending.
Text edits are interpreted by the Agent and always invalidate the edited proposal.
Confirming a stale proposal/interrupt returns 409; confirming missing information
returns 422. Confirmation never accepts a client-provided balance or estimated delta.

If a commit outcome is unknown, the item reports EXECUTION_UNCERTAIN. Confirm retries
the same immutable receipt first; editing/cancelling that unresolved item returns
VERIFY_OUTCOME_FIRST to avoid duplicating an already committed action.

### GET /api/v1/agent/conversations/{conversation_id}/state

Returns request_id, status and sanitized items. When waiting, it also returns the
current interrupt_id and pending questions. Other users receive 404. It does not
return raw checkpoint messages, model prompts, credentials or tool internals.

Turn states: COMPLETED, WAITING_INPUT, RECOVERABLE. Item states: DRAFT, READY,
NEEDS_INPUT, NEEDS_CONFIRMATION, SUCCEEDED, FAILED, CANCELLED.

### Events

| Event | Payload |
|---|---|
| start | conversation_id, request_id |
| text_delta | delta; only final user-facing answer text |
| operation_preview | data: item/proposal identifiers, before/after, method, estimate basis |
| action_required | data: interrupt_id and pending items |
| operation_result | data: item status, actual result or error |
| done | status and data containing current public state |
| error | stable code and sanitized message; query state before retrying |

Read the SSE stream until done, error or connection loss. A WAITING_INPUT done
event is not successful completion of the inventory actions. Clients render each
item's status and use the state endpoint after refresh/disconnection. Retried
responses may repeat result events; reconcile UI items by item_id/proposal_id.

## Writes, audit and recovery

`agent_inventory_action` stores committed per-item receipts with user, logical
conversation/turn IDs, request fingerprint, immutable request/basis snapshot and
actual result snapshot. It has no foreign key to the older conversation table:
LangGraph conversations do not create those rows. Inventory and receipt writes
commit together. New associations and stock creation within one item roll back
together; successful associations can be reused by later independent items.

Agent ADD/CONSUME/RECONCILE records use input_method=TEXT. Original expressions
remain in quantity fields; final balances are computed by the backend. Existing
manual interfaces retain their default transaction boundaries and MANUAL source.

Candidate IDs are saved before execution using synchronous checkpoints. A dedicated
direct PostgreSQL connection holds the conversation advisory lock and releases it
when the stream closes or the graph pauses. It does not occupy a checkpointer pool
connection or hold a business transaction while the model runs. Receipt locks and
version checks prevent duplicate or stale writes even if graph recovery repeats a node.

## Setup and validation

Python 3.11 and backend requirements are required. Agent persistence uses
AGENT_DATABASE_URL when nonempty, otherwise DATABASE_URL_DIRECT. Keep credentials
only in local/deployment secrets. AGENT_WORKFLOW_STEP_LIMIT defaults to 128 and is
the six-node step budget; legacy AGENT_RECURSION_LIMIT does not control this workflow.

On Windows, psycopg requires a Selector event loop. To run without reload with the
installed Uvicorn version, use:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app.main:app --loop asyncio:SelectorEventLoop
```

The existing reload development command also selects a compatible loop. Linux
can use the normal Uvicorn asyncio loop.

For an existing database, explicitly check both storage layers:

```powershell
.\.venv\Scripts\python.exe scripts/setup_agent_storage.py --check
.\.venv\Scripts\python.exe scripts/setup_agent_actions.py --check
```

The receipt-table script exits nonzero if missing or structurally incompatible.
After checking the intended environment, `--initialize` prompts for INITIALIZE and
adds only the receipt table. It does not run automatically on application startup.
Fresh development/test schemas receive the table through the updated initial schema.
Applying these local changes does not synchronize an existing remote database.

Run `python -m pytest` against a separately configured TEST_DATABASE_URL ending in
`_test`. Fixtures own disposable schemas. Live model checks are opt-in:

```powershell
$env:AGENT_LIVE_MODEL='1'
.\.venv\Scripts\python.exe -m pytest tests/test_agent_live_model.py -q
```

Live checks use synthetic inventory in the isolated test database and incur model
API usage; they never use the production inventory connection for test actions.
