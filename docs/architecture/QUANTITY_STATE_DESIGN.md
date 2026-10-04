# Inventory Quantity Rules

This document owns quantity semantics. [Database design](DATABASE_DESIGN.md)
owns persisted fields; the [API reference](../reference/API_REFERENCE.md) owns requests.

## Balances and display

| Field group | Meaning | Update rule |
| --- | --- | --- |
| `initial_*` | Original stock-entry amount and unit | Preserved by subsequent operations |
| `confirmed_current_*` | Last certain balance and unit | Updated by certain operations when there is no estimated balance, or by reconciliation |
| `estimated_current_*` | Balance containing an uncertain conversion | Updated while uncertainty remains; amount/unit/time are set or cleared together |

New stock starts with confirmed quantity equal to its initial quantity and no
estimate. Display uses the estimate when present, including zero; otherwise it
uses the confirmed balance. Initial quantity is a historical fact, not a display fallback.
An estimated zero means possibly exhausted and remains visible. Confirmed zero
can set the item to EMPTY.

## Additions and consumption

ADD/CONSUME enter a change amount, not a remaining total. Operations use the
current effective balance rather than recalculating from the initial quantity.
An exact deduction from an estimated starting balance remains estimated.

| Calculation method | Basis |
| --- | --- |
| EXACT | Same-unit amounts or a valid fraction of the current balance |
| CONVERTED | Deterministic mass/volume conversions, such as g/kg or ml/l |
| AI_ESTIMATED | Context-dependent relationships, such as cups/weight or pieces/weight |

The backend calculates the final balance. User memory can supply an applicable
relationship but does not turn an empirical relationship into an exact conversion.
Estimates execute with an estimated label unless the user requests approval;
photo stock and category review have their own confirmation rules.

The effective balance is converted to the requested operation unit before the
change and saved in that unit. A fraction without a new unit retains the current
unit. Ordinary cross-unit whole-item estimates round to an integer consistently
in the preview, persisted result and feedback. An explicit half-item deduction
can retain a fractional result. An ambiguous half of three whole apples requires
clarification of the actual count.

Decimal arithmetic stores at most three decimal places in NUMERIC(12,3).
Unrepresentable changes and rounding that would erase a positive balance return
a specific validation problem. Physical reconciliation establishes a fresh baseline.

A new conversion relationship is saved during execution before the stock write.
Memory failure leaves stock unchanged. If stock fails after memory succeeds, the
relationship can remain; the stock result still reports failure. Receipts and retry
identities prevent a duplicate inventory write.

## Reconciliation

RECONCILE records an actual remaining total, not agreement to an estimated change.
For example, a batch initially recorded as 20 kg can be reconciled to 8 pieces:
initial facts stay unchanged, confirmed becomes 8 pieces, and the estimate is cleared.
Subsequent operations use pieces. An incorrect stocktake is corrected by another
RECONCILE. Reconciliation records a new confirmation even when the total is unchanged.

## Correction and undo

The current release provides no undo workflow for committed inventory operations.
Directly restoring an earlier balance overwrites subsequent stock changes.
An undo implementation must account for those changes and preserve the operation
history.

Users correct stock by entering the actual remaining total through RECONCILE.
The correction creates a new operation record; earlier operations remain in the
history. `UNDONE` and `undone_at` are reserved for an undo workflow.

Cancel applies to a pending Agent proposal before its stock write. It does not
reverse a completed operation. See the
[product scope](../product/README.md#inventory-operation-undo).

## Batches and history

Use ADD to supplement the same stock batch; create a new batch for a purchase with
its own dates. Automatic merging and historical recalculation are outside the
current implementation. Displaying quantities together requires compatible units.

Successful ADD/CONSUME/RECONCILE writes create quantity-operation records. Agent
receipts additionally retain execution identity and the calculation basis snapshot.
Creation does not manufacture an ADD record. Metadata edits, movement, discard and
archive are not a complete event ledger. Memory changes affect future interpretation,
not old operations or current stock.

## Consistency

Preparation changes no stock. Submission checks identity, ownership, state, units,
quantity, expected version and retry identity against current server data. Quantity
updates and their operation records commit together. Agent items commit independently;
manual batch endpoints commit all members together. See [backend consistency rules](BACKEND_DESIGN.md).
