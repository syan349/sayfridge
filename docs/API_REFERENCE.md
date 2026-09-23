# SayFridge API Reference: B01–B14

Implemented authentication, storage-space, catalog, and inventory contracts.
For setup, see the [backend README](../backend/README.md). For implementation and
locking rules, see the [design handbook](BACKEND_DESIGN.md). Test commands, CI
selection, and acceptance evidence are in the [test index](testing/README.md).
For manual requests, see the [Postman guide](testing/POSTMAN_GUIDE.md).

## 1. Common conventions

- Local base URL: `http://127.0.0.1:8000`; API prefix: `/api/v1`.
- Interactive schemas: `/docs`. `GET /health` returns service health without
  querying the database.
- Paths below omit the API prefix. JSON requests use `Content-Type: application/json`.
- Except registration and login, all endpoints require `Authorization: Bearer <token>`.
  Identity, role, and ACTIVE account state are checked against the current database.
  Deleted, SUSPENDED, or DISABLED accounts cannot use an otherwise valid token.
- IDs are UUIDs. Invalid IDs or request parameters return 422.
- Create/PATCH schemas reject extra fields. List queries reject unknown parameters.
- PATCH changes only submitted fields; empty changes return 422. Explicit null is
  accepted only for inventory dates and notes; other fields reject it.
  Failed writes are atomic. Unchanged edits preserve `updated_at`.
- Archive/restore accept no body, including no `{}` or JSON null.
- Creation is not idempotent. Valid repeated archive/restore requests preserve timestamps.
- Business endpoints below give administrators the same ownership restrictions as
  ordinary users. Public-catalog administrator writes are outside this delivery.

### Pagination

Space/category/definition list endpoints accept `status=ACTIVE|ARCHIVED|ALL` (default ACTIVE),
`page` (integer ≥1, default 1), and `page_size` (1–100, default 20).

```json
{"items": [], "total": 0, "page": 1, "page_size": 20}
```

`total` counts all matching visible rows. Out-of-range pages return empty items
and retain the matching total. Items and total share a consistent database snapshot.
Each resource specifies its ordering and state-filter semantics below.

### Errors

| HTTP | Meaning |
| --- | --- |
| 401 | Missing/invalid/expired identity or unavailable account; Bearer authentication challenge |
| 404 | Missing or inaccessible resource |
| 409 | Name, state, or concurrent relationship conflict |
| 422 | Invalid request; validation responses never echo raw input/passwords |

Authentication errors use `{"detail":"message"}`. Authentication validation uses
`{"detail":[{"type":"...","loc":["body","field"],"msg":"..."}]}`.

Business errors use:

```json
{"detail":{"code":"NOT_FOUND","message":"Resource not found"}}
```

Business validation may include `detail.errors`, with `loc` and `msg` for each
invalid field. Codes: `NOT_FOUND`, `NAME_CONFLICT`, `STATE_CONFLICT`,
`RESOURCE_CHANGED`, `VERSION_CONFLICT`, `VERSION_LIMIT_REACHED`, `VALIDATION_ERROR`,
`IDEMPOTENCY_CONFLICT`, `UNIT_NOT_CONVERTIBLE`, `QUANTITY_TOO_SMALL`, and
`QUANTITY_OUT_OF_RANGE`. Error messages depend on the resource.
Authentication failures on business endpoints retain the authentication format.

## 2. Authentication — B01–B03

### User response

Shared by registration, current-user lookup, and login's `user` field:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "postman-demo@example.com",
  "role": "USER",
  "status": "ACTIVE",
  "created_at": "2026-09-11T00:00:00Z"
}
```

IDs/timestamps are server-generated. Password hashes and internal quota fields
are never returned. Email input is trimmed and lowercased.

### POST /auth/register — B01

No authentication. Required JSON:

```json
{"email":"postman-demo@example.com","password":"PostmanDemo42!"}
```

- Password: 8–128 characters, without silent truncation; valid email required.
- Success: **201**, User response. No token; log in separately.
- Database effect: create one USER/ACTIVE account with an Argon2id password hash;
  do not create spaces or inventory. Clients cannot set role, state, or ID.
- Duplicate normalized email: **409**, `Email is already registered`.
- Invalid, missing, or extra fields: **422**.

### POST /auth/login — B02

No authentication. Required JSON: the same `email` and `password` fields as registration.

Success: **200**, with these JSON fields:

| Field | Type / value |
| --- | --- |
| access_token | String: JWT |
| token_type | String: `bearer` |
| expires_in | Integer: lifetime in seconds (currently configured as 900) |
| user | User object defined above |

- Database effect: read account and verify password; no session record or cookie.
- Unknown email, wrong password, non-local account, missing hash, or inactive account:
  **401**, `Invalid email or password`.
- Malformed input: **422**.

### GET /auth/me — B03

- Success: **200**, User response; no request body required.
- Database effect: read current user role/state using the token identity;
  request parameters cannot select another user.
- Missing/invalid/expired token or unavailable user: **401**,
  `Invalid or expired access token`, with `WWW-Authenticate: Bearer`.

Profile editing, password change, refresh tokens, cookie login, and logout are
outside this delivery.

## 3. Storage spaces — B04

### Space response and shared rules

Response fields: `id`, `name`, `type`, `status`, `created_at`, `updated_at`.

- `name`: trimmed, 1–100 characters.
- `type`: FRIDGE, FREEZER, PANTRY, WAREHOUSE, OTHER (case sensitive).
- Only the owner can read/write a space, including archived detail reads.
  Missing and foreign IDs produce identical **404 / NOT_FOUND** responses.
- ACTIVE names are unique per owner using PostgreSQL `lower(name)`.
  Archived spaces release their names.

### POST /storage-spaces

```json
{"name":"Kitchen fridge","type":"FRIDGE"}
```

Both fields required. **201**, Space response. Create one space owned by the current
user with ACTIVE status; no inventory is created. Duplicate active name:
**409 / NAME_CONFLICT**.

### GET /storage-spaces

Common pagination/state parameters. Return **200**, page of Space responses.
Filter only the owner's rows by space status; sort by name, then UUID ascending
using database ordering. Read-only.

### GET /storage-spaces/{id}

**200**, Space response. Read an owned ACTIVE or ARCHIVED space. Read-only.

### PATCH /storage-spaces/{id}

JSON: `name`, `type`, or both. **200**, updated Space response.
Only ACTIVE spaces may be edited; otherwise **409 / STATE_CONFLICT**.
Conflicting active name: **409 / NAME_CONFLICT**, with all changes rolled back.

### POST /storage-spaces/{id}/archive

**200**, Space response with ARCHIVED status. Change only the space state;
leave inventory unchanged. Existing IN_STOCK inventory blocks archival with
**409 / STATE_CONFLICT**; EMPTY, DISCARDED, and ARCHIVED inventory do not.
Repeated archival succeeds without timestamp changes. Archived spaces remain
available through detail and ARCHIVED/ALL lists.

### POST /storage-spaces/{id}/restore

**200**, Space response with ACTIVE status. An already ACTIVE space is unchanged.
If another owned ACTIVE space holds the name, return **409 / NAME_CONFLICT** and
keep the original archived. Rename the active namesake before retrying.

## 4. Categories — B05

### GET /item-categories

Common pagination/state parameters. **200**, page of category objects:
`id`, `name`, `status`, `sort_order`.

Read public categories filtered by category status; sort by `sort_order`, name,
then UUID ascending. No writes. An ACTIVE category must already exist before
creating a definition; this delivery adds no category initialization or write API.

## 5. Item definitions — B06

### Definition response and shared rules

Response fields: `id`, `name`, `category_id`, `status`, `scope` (PUBLIC or PRIVATE).
Owner IDs and internal normalized keys are omitted.

- Read public definitions and the current user's private definitions only.
- PATCH/archive/restore accept only owned private definitions. Public, foreign,
  and missing IDs produce identical **404 / NOT_FOUND** responses.
- `name`: trimmed, 1–100 characters. NFKC → trim → casefold produces its
  normalized name, which must also contain 1–100 characters.
- Private normalized names are unique per owner across categories and states;
  archived names remain reserved. Public/other-owner equivalent names are allowed.
  Legacy-equivalent names also conflict without rewriting existing data.
- Mutations preserve inventory references. Later joined reads reflect the current
  definition name/category. Conflicting writes roll back atomically.
- If the category relationship changes during a write's lock acquisition, return
  **409 / RESOURCE_CHANGED**; reload and retry. Lock implementation is in the handbook.

### GET /item-definitions

Common pagination/state parameters, plus:

| Parameter | Default | Meaning |
| --- | --- | --- |
| scope | ALL | PUBLIC, PRIVATE (current user), ALL |
| category_id | Omitted | Category UUID; nonexistent ID yields empty results |
| q | Empty | Trimmed literal case-insensitive name substring, at most 100 characters |

**200**, page of Definition responses; read-only. Sort by name, scope, UUID
ascending (PRIVATE before PUBLIC when names match). `%`, `_`, slash, and backslash
in `q` are literal; empty/whitespace-only `q` adds no name filter.

- ACTIVE: both definition and category must be ACTIVE.
- ARCHIVED: definition must be ARCHIVED; category state is unrestricted.
- ALL: no state filtering.
- Every filter/count retains public/current-user visibility.

### GET /item-definitions/{id}

**200**, Definition response. Read a visible definition, including archived
records and definitions in archived categories. Foreign/missing IDs: **404 / NOT_FOUND**.

### POST /item-definitions

```json
{"name":"Brown rice","category_id":"<category UUID>"}
```

Both fields required. **201**, Definition response. Create one private ACTIVE
definition owned by the current user. Server assigns ownership/state/normalized key.
Category must exist (**404 / NOT_FOUND**) and be ACTIVE (**409 / STATE_CONFLICT**).
Duplicate private name: **409 / NAME_CONFLICT**. No inventory is created.

### PATCH /item-definitions/{id}

JSON: `name`, `category_id`, or both. **200**, updated Definition response.

- Definition must be ACTIVE; otherwise **409 / STATE_CONFLICT**.
- Submitted category must exist and be ACTIVE (404/409 respectively).
  A name-only edit may retain an existing archived category.
- A changed name stores its normalized form. Unchanged requests preserve the
  existing normalized key and timestamp.
- Duplicate private name: **409 / NAME_CONFLICT**, rolling back all changes.

### POST /item-definitions/{id}/archive

**200**, Definition response with ARCHIVED status. Archive only the definition;
preserve inventory and reserve the name. Repeated archival leaves timestamps unchanged.

### POST /item-definitions/{id}/restore

**200**, Definition response with ACTIVE status. The current category must be
ACTIVE, even when the definition is already active; otherwise **409 / STATE_CONFLICT**.
A valid repeated restore leaves timestamps unchanged.


## 6. Inventory — B07–B09 and B13

Inventory requires nullable `inventory_item.notes` in the current table structure.
See the backend README for development database synchronization; Neon is unchanged.

### Inventory response and shared rules

| Fields | Meaning |
| --- | --- |
| id, storage_space_id, item_definition_id | UUID identifiers |
| storage_space_name, item_definition_name, category_id, category_name | Current associated names/category, not historical snapshots |
| purchase_date, expiry_date, notes | Nullable YYYY-MM-DD dates; nullable notes |
| status, version | IN_STOCK/EMPTY/DISCARDED/ARCHIVED; positive integer version |
| initial_amount, initial_unit | Original stock facts |
| confirmed_current_amount, confirmed_current_unit, confirmed_at | Confirmed balance and timezone-aware timestamp |
| estimated_current_amount, estimated_current_unit, estimated_at | Estimate trio, all nullable |
| display_amount, display_unit, is_estimated | Use a non-null estimate, including zero; otherwise confirmed balance |
| created_at, updated_at | Timezone-aware timestamps |

Amounts are decimal strings. Only the space owner can read/write inventory;
foreign and missing item IDs return identical 404 / NOT_FOUND. Archived associated
spaces/definitions/categories do not hide existing stock or prevent metadata edits.
No owner IDs are returned. These APIs do not create operation history.

### GET /inventory-items — B07

**200**, paginated Inventory responses. Read-only; count/items share one snapshot.
Sort by expiry_date ascending, NULLS LAST, then UUID ascending.

| Parameter | Default / meaning |
| --- | --- |
| status | IN_STOCK; also EMPTY, DISCARDED, ARCHIVED, ALL |
| page, page_size | 1 and 20; page ≥1, page_size 1–100 |
| q | Empty; trimmed literal case-insensitive substring of item definition name, at most 100 characters |
| storage_space_id, category_id | Optional UUID filters; inaccessible/nonexistent matches yield empty results |
| purchase_from, purchase_to | Optional inclusive YYYY-MM-DD boundaries |
| expiry_from, expiry_to | Optional inclusive YYYY-MM-DD boundaries |

Reversed date ranges return 422. Date filters exclude NULL dates. List defaults
filter inventory state only, not associated resource states.

### GET /inventory-items/{id} — B07

**200**, Inventory response in any inventory state. Read-only.

### POST /inventory-items — B08

```json
{"storage_space_id":"<space UUID>","item_definition_id":"<definition UUID>","amount":"2.5","unit":"kg"}
```

Required fields above; optional purchase_date, expiry_date, notes (≤1,000 characters).
Amount must be a positive ordinary decimal string with at most three decimal places,
at most 999999999.999; numeric JSON values, exponents, and nonfinite values are rejected.
Units are trimmed, 1–16 characters, and casefolded; the stored result must fit 16
characters. g/kg/ml/l symbols are canonicalized by casing; no word aliases or count
unit equivalences are inferred. Other literal units remain distinct. Dates must
use YYYY-MM-DD. Expired stock and purchase dates after expiry are allowed.

**201**, Inventory response. Space must be owned/ACTIVE; definition must be visible
(public or owned private) and ACTIVE; its category must be ACTIVE. Missing/foreign
associations return 404; archived associations return 409 / STATE_CONFLICT.

Insert one IN_STOCK row: initial and confirmed amounts/units equal validated input,
confirmed_at is server time, estimates are NULL, version is 1. No ADD event is created.
State checks coordinate with concurrent archival. Relationship changes during lock
acquisition return 409 / RESOURCE_CHANGED. Creation has no idempotency guarantee.

### POST /inventory-items/batch-create — B15

```json
{
  "items": [
    {"storage_space_id":"<space UUID>","item_definition_id":"<definition UUID>","amount":"2.5","unit":"kg"},
    {"storage_space_id":"<space UUID>","item_definition_id":"<definition UUID>","amount":"3","unit":"each","notes":"Second package"}
  ]
}
```

The body accepts only `items`, containing 1–100 `InventoryCreate` objects. Each
entry follows the same amount, unit, date, notes, ownership, visibility, and ACTIVE
association rules as `POST /inventory-items`. Identical entries are allowed because
they may represent separate physical stock batches.

**201**, `{"items":[InventoryItemRead],"count":2}`. Returned items remain in input
order. Every row starts IN_STOCK at version 1 with equal initial and confirmed
quantities, no estimate, and no ADD operation history.

The complete request is one transaction: validation or database failure for any
entry rolls back every insertion. Batch business errors include the zero-based
`item_index` of the first determined failing entry; request-level errors such as an
empty or oversized `items` list have no item index. Missing and inaccessible
associations both return 404 / NOT_FOUND; archived associations return 409 /
STATE_CONFLICT; relationships changed during lock acquisition return 409 /
RESOURCE_CHANGED. The endpoint has no idempotency guarantee, so retry only after
checking whether a response was received.

### PATCH /inventory-items/{id} — B09

```json
{"expected_version":1,"notes":"Opened today"}
```

Required expected_version: integer 1–2147483647. Supply at least one of
storage_space_id, purchase_date, expiry_date, notes. Null clears dates/notes only.
Definition ID, quantities, states, and timestamps cannot be changed here.

**200**, Inventory response. Only IN_STOCK/EMPTY may be edited; terminal states
return 409 / STATE_CONFLICT. A move needs an owned ACTIVE destination (404/409).
EMPTY stock can move out of an archived space. Version mismatch returns
409 / VERSION_CONFLICT, including otherwise unchanged requests.

Apply actual changes together and increment version once. Unchanged requests
preserve version/timestamps. A change at the maximum version returns
409 / VERSION_LIMIT_REACHED. Location changes during lock acquisition return
409 / RESOURCE_CHANGED. Preserve all quantity/confirmation/estimate fields and
initial facts; write no metadata/move event. After conflicts, reload before retrying.

### POST /inventory-items/{id}/discard — B13

```json
{"expected_version":1}
```

The body accepts only `expected_version`, a strict integer from 1 through
2147483647. Bearer authentication and ownership are required; foreign and missing
IDs both return **404 / NOT_FOUND**.

**200**, Inventory response with status `DISCARDED` and version incremented once.
Only `IN_STOCK` inventory may be discarded. `EMPTY`, `DISCARDED`, and `ARCHIVED`
return **409 / STATE_CONFLICT**. A stale version returns **409 / VERSION_CONFLICT**,
and a successful write at the maximum version is rejected with
**409 / VERSION_LIMIT_REACHED**. Discard remains allowed when the containing space
or catalog association is archived.

The transition changes only status, version, and updated_at. It preserves initial,
confirmed, and estimated quantities and their timestamps, location, catalog
association, dates, and notes. It creates no inventory operation record. Concurrent
requests using the same version have one successful transition; later requests must
reload the inventory state.

### POST /inventory-items/{id}/archive — B13

```json
{"expected_version":1}
```

The request contract, ownership rules, version errors, preserved fields, and
single-winner concurrency behavior are the same as discard. **200** returns the
Inventory response with status `ARCHIVED` and version incremented once.

Archive accepts `IN_STOCK` and `EMPTY` inventory. `DISCARDED` and `ARCHIVED` return
**409 / STATE_CONFLICT**. The transition is allowed when the containing space or
catalog association is archived. It creates no inventory operation record and does
not alter quantities or quantity timestamps.


## 7. Inventory quantity operations and history — B10–B12 and B14

### POST /inventory-items/{id}/operations

**201** for a new operation; **200** for a successful replay. Bearer authentication
and an owned inventory item are required. Preview and history endpoints remain planned.

Required header: `Idempotency-Key`, 1–64 visible ASCII characters, without spaces.
Keys are case-sensitive and scoped to the current user across all inventory items.

```json
{
  "expected_version": 1,
  "operation_type": "ADD",
  "quantity_kind": "AMOUNT",
  "quantity_value": "500.0",
  "quantity_unit": "g"
}
```

All five fields are required; extra fields are rejected. expected_version is a
strict integer from 1 to 2147483647. For AMOUNT, quantity_value is an ordinary
decimal string, at most 32 characters and three decimal places, no greater than
999999999.999. ADD and CONSUME require a positive value; RECONCILE permits zero.
Scientific notation and numeric JSON values are rejected. Preserve
literal quantity text ("2" differs from "2.0"). Trim unit whitespace before storage,
retain case, and require 1–16 characters both before and after casefolding.

| Operation | Quantity kind | Input | Allowed state |
| --- | --- | --- | --- |
| ADD | AMOUNT | Decimal string and unit | IN_STOCK; EMPTY only in an ACTIVE space |
| CONSUME | AMOUNT | Decimal string and unit | IN_STOCK only |
| CONSUME | FRACTION | `p/q`, positive integers with p ≤ q; unit `remaining` | IN_STOCK only |
| RECONCILE | AMOUNT | Nonnegative confirmed total and its unit | IN_STOCK; EMPTY with zero, or positive only in an ACTIVE space |

Fraction text is limited to 32 characters and preserved literally: `1/2` and
`2/4` are different retry inputs. For example, consume one third with:

```json
{"expected_version": 1, "operation_type": "CONSUME", "quantity_kind": "FRACTION", "quantity_value": "1/3", "quantity_unit": "remaining"}
```

A physical stocktake that confirms 6 kg uses:

```json
{"expected_version": 1, "operation_type": "RECONCILE", "quantity_kind": "AMOUNT", "quantity_value": "6", "quantity_unit": "kg"}
```

**Effect:** lock the space then inventory; check version and allowed state.
Archived definitions/categories do not block operations on existing stock;
IN_STOCK consumption is also allowed in an archived space. Update the estimated balance
and timestamp if an estimate exists (including zero); otherwise update the
confirmed balance and timestamp. Preserve initial quantities and the other balance.
Confirmed zero becomes EMPTY; estimated zero remains IN_STOCK. Otherwise set
IN_STOCK. Increment version/update time and insert one SUCCESS operation in
the same transaction. Any failure rolls back both writes.

RECONCILE replaces the confirmed total and unit, updates confirmed_at, clears all
three estimated fields, and sets EMPTY for zero or IN_STOCK for a positive total.
It performs no conversion against the old unit. Even an unchanged total records a
new physical confirmation and increments version.

**Calculation:** convert g↔kg or ml↔l to the current effective unit; identical
casefolded units are exact. Reject other differing units. Round the applied change
to three places using ROUND_HALF_UP before addition/subtraction. Reject changes rounded to zero
and amounts outside NUMERIC(12,3). A valid 0.5 g addition to kg stock applies 0.001 kg;
a raw 0.0005 kg input is invalid because it has four decimal places.

For consumption, check the unrounded change against the balance first; rounding
must not hide over-consumption. Fractions use exact integer-ratio arithmetic.
Reject rounding that erases a positive remainder. Consuming `1/3` of 1 kg applies
0.333 kg and leaves 0.667 kg; consuming `1/2` of 0.001 kg is rejected. Explicitly
consuming all of 0.001 kg is allowed. Applied changes are positive; operation_type
indicates addition or subtraction.

**Response:** `{operation, inventory, replayed}`. inventory uses the response in
section 6. operation includes id, inventory_item_id, operation_type,
quantity_kind/value/unit, input_method, calculation_method, affects_state,
applied_change_amount/unit, status, created_at, updated_at, and undone_at.
For new records: input_method=MANUAL and status=SUCCESS. ADD/CONSUME use
calculation_method=EXACT or CONVERTED and affect the effective balance.
RECONCILE uses calculation_method=EXACT, affects_state=CONFIRMED, and stores NULL
applied_change_amount/unit because it confirms a total rather than a reliable delta.
Decimal amounts serialize as strings. Internal idempotency keys are never returned.

**Retry:** resend the same key, inventory ID, and literal business input. A matching
successful operation returns its unchanged record plus current inventory, even if
version/state changed since the original request. expected_version is not compared
for replay. No quantities, versions, or timestamps change on replay. Access is
still checked. Different input, another inventory ID, or a non-SUCCESS record for
the same key returns IDEMPOTENCY_CONFLICT. Failed requests do not reserve keys.

**Errors:** 401 unauthenticated; 404 NOT_FOUND; 409 VERSION_CONFLICT,
VERSION_LIMIT_REACHED, STATE_CONFLICT, RESOURCE_CHANGED, IDEMPOTENCY_CONFLICT;
422 VALIDATION_ERROR, UNIT_NOT_CONVERTIBLE, QUANTITY_TOO_SMALL, QUANTITY_OUT_OF_RANGE,
INSUFFICIENT_QUANTITY, QUANTITY_PRECISION_UNSUPPORTED.

Manual verification: GET the inventory version, submit this request with a new key,
then resend it unchanged. Expect 201 followed by 200, the same operation ID, and
only one quantity change. No database initialization change is needed for B10–B12.

### GET /inventory-items/{id}/operations — B14

**200**, an array containing every operation for the owned inventory item. Results
are ordered by `created_at` descending and then operation `id` descending, providing
stable newest-first output. An item with no operation records returns `[]`.

The endpoint remains available for `IN_STOCK`, `EMPTY`, `DISCARDED`, and `ARCHIVED`
inventory. It returns all stored operation states, including historical
`PENDING_CONFIRMATION`, `FAILED`, and `UNDONE` records; clients must not display
those states as effective quantity changes. Each element uses the operation response
fields documented above. Internal idempotency keys are omitted.

Authentication and inventory ownership are required. Foreign and missing inventory
IDs return identical **404 / NOT_FOUND** responses. This endpoint is read-only and
does not change inventory, operation records, versions, or timestamps.

### GET /inventory-operations — B14

**200**, a paginated object containing `items`, `total`, `page`, and `page_size`.
Only operations belonging to the current user's inventory are visible. Results use
the same public operation fields and `created_at DESC, id DESC` ordering as the
item-scoped endpoint.

| Parameter | Default / meaning |
| --- | --- |
| inventory_item_id | Optional UUID; inaccessible or nonexistent values produce an empty page |
| operation_type | Optional ADD, CONSUME, or RECONCILE |
| status | Optional PENDING_CONFIRMATION, SUCCESS, FAILED, or UNDONE |
| created_from | Optional timezone-aware timestamp; inclusive |
| created_to | Optional timezone-aware timestamp; exclusive |
| page, page_size | 1 and 20; page ≥1, page_size 1–100 |

When both time boundaries are supplied, `created_from` must be earlier than
`created_to`. Naive timestamps, invalid enums, reversed/equal ranges, and unknown
query parameters return **422 / VALIDATION_ERROR**. Counts cover the complete
filtered result, including when the requested page is empty.

### GET /inventory-operations/{id} — B14

**200**, one public operation response. The associated inventory may be in any
state and may belong to archived associations. Foreign and missing operation IDs
return identical **404 / NOT_FOUND** responses. Internal idempotency keys are not
returned. This endpoint is read-only.
