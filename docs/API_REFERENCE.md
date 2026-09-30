# SayFridge API Reference

Implemented authentication, storage-space, catalog, inventory, administrator-account and Agent V0.2 contracts.
For setup, see the [backend README](../backend/README.md). For implementation and
locking rules, see the [design handbook](BACKEND_DESIGN.md). Test commands, CI
selection, and acceptance evidence are in the [test index](testing/README.md).
For manual requests, see the [Postman guide](testing/POSTMAN_GUIDE.md).

## 1. Common conventions

- Local base URL: `http://127.0.0.1:8000`; API prefix: `/api/v1`.
- Interactive schemas: Swagger UI at `/docs`, ReDoc at `/redoc`, and machine-readable
  OpenAPI at `/openapi.json`.
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
- Ordinary manual creation is not idempotent. Agent actions have per-item receipts and retry identities (section 9). Valid repeated archive/restore requests preserve timestamps.
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

### Public system endpoints

`GET /health` returns `{"status":"ok","service":"sayfridge-backend"}` without
querying the database. It confirms process availability only.

`GET /api/v1/system/version` returns public deployment identity:

```json
{
  "service": "sayfridge-backend",
  "version": "0.1.0",
  "commit_sha": "0123456789abcdef0123456789abcdef01234567"
}
```

`commit_sha` is null outside a deployment that supplies `APP_COMMIT_SHA` or
`VERCEL_GIT_COMMIT_SHA`. Use this endpoint before acceptance testing to confirm
that the expected Git revision is running.

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
- Database effect: create one USER/ACTIVE account with an Argon2id password hash
  and one active `Default Space` of type `FRIDGE` in the same transaction. Do not
  create inventory. Clients cannot set role, state, Space ownership, or ID.
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
- The application allows five attempts per client/account pair in a 60-second sliding
  window by default. The next attempt returns **429**,
  `Too many login attempts; try again later`, with `Retry-After`. A successful login
  clears the pair's window. Deployments with multiple application instances must also
  enforce a shared limit at the hosting edge or gateway.
- Malformed input: **422**.

### GET /auth/me — B03

- Success: **200**, User response; no request body required.
- Database effect: read current user role/state using the token identity;
  request parameters cannot select another user.
- Missing/invalid/expired token or unavailable user: **401**,
  `Invalid or expired access token`, with `WWW-Authenticate: Bearer`.

Profile editing, password change, refresh tokens, cookie login, server-side sessions,
and a logout endpoint are outside this delivery. Clients log out by deleting the
Bearer token. Tokens cannot be revoked individually and remain valid until their
configured expiry unless the account is suspended, disabled, or deleted; each
authenticated request reads the account's current state from the database.

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
creating a definition; the explicit seed SQL initializes the maintained catalog; there is no category write API.

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


<a id="6-inventory--b07b09"></a>

## 6. Inventory — B07–B09, B13, B15, and B22

Inventory requires nullable `inventory_item.notes` in the current table structure.

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

### GET /inventory-items/expiry-summary — B22

Required query: `as_of=YYYY-MM-DD`. Optional query: `days_before` (default 3,
0–365), `storage_space_id`, `category_id`, `bucket=overdue|today|upcoming`, `page`,
and `page_size`. Adding `days_before` to `as_of` must remain within the legal date
range.

**200**, `{"counts":{"overdue":0,"today":0,"upcoming":0},"items":[],"total":0,
"page":1,"page_size":20}`. Each item contains the normal Inventory response plus
its `bucket`. The query includes only the current user's IN_STOCK inventory with a
known expiry date. Archived spaces, definitions, and categories do not hide
existing inventory.

An expiry before `as_of` is overdue; equality is today; a later expiry through
`as_of + days_before` inclusive is upcoming. Later and unknown dates are excluded.
`counts` always covers all three buckets after space/category filtering. `bucket`
filters only `items` and `total`. Results sort by expiry_date then ID ascending and
use the standard pagination contract. Counts, total, and page come from one database
statement. The endpoint writes nothing and sends no reminder or notification.

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

### POST /inventory-items/batch-move — B15

```json
{
  "target_storage_space_id": "<owned active space UUID>",
  "items": [
    {"id":"<inventory UUID>","expected_version":1},
    {"id":"<inventory UUID>","expected_version":4}
  ]
}
```

The body accepts one target space and 1–100 distinct inventory references. Each
reference contains only `id` and a strict integer `expected_version` from 1 through
2147483647. Duplicate IDs return 422 / VALIDATION_ERROR at the second occurrence.
The target must be owned and ACTIVE. Foreign and missing targets both return 404 /
NOT_FOUND; an archived target returns 409 / STATE_CONFLICT.

**200**, `{"items":[InventoryItemRead],"count":2}` in request order. Every item
must be owned and currently IN_STOCK or EMPTY. A moved item receives the target
storage_space_id and increments its version once. Moving an item already in the
target space is a no-op: it still validates ownership, state, version, and the
target's ACTIVE state, but preserves its version and updated_at. A no-op therefore
remains valid at the maximum version; an actual move at that version returns 409 /
VERSION_LIMIT_REACHED.

The entire batch is atomic. Missing or inaccessible items return 404 / NOT_FOUND;
stale versions return 409 / VERSION_CONFLICT; terminal inventory returns 409 /
STATE_CONFLICT. Entry-specific errors include zero-based `item_index`, and any
failure leaves every item in its original space. The operation preserves quantities,
quantity timestamps, item definition, dates, notes, and status, and writes no move
history. There is no idempotent response replay; after a lost response, reload the
items before retrying.

### POST /inventory-items/batch-archive — B15

```json
{
  "items": [
    {"id":"<inventory UUID>","expected_version":1},
    {"id":"<inventory UUID>","expected_version":4}
  ]
}
```

The body accepts only `items`, containing 1–100 distinct inventory references.
Each reference contains only `id` and a strict integer `expected_version` from 1
through 2147483647. Duplicate IDs return 422 / VALIDATION_ERROR at the second
occurrence.

**200**, `{"items":[InventoryItemRead],"count":2}` in request order. Every item
must be owned and currently IN_STOCK or EMPTY. The endpoint changes each status to
ARCHIVED and increments each version once. It preserves storage space, definition,
all quantity and quantity-timestamp fields, dates, notes, and operation history.
Archiving from an already archived source storage space is allowed. No archive
operation-history row is written.

The entire batch is atomic. Missing or inaccessible items return 404 / NOT_FOUND;
stale versions return 409 / VERSION_CONFLICT; DISCARDED or already ARCHIVED items
return 409 / STATE_CONFLICT; and an item at the maximum version returns 409 /
VERSION_LIMIT_REACHED. Entry-specific errors include zero-based `item_index`, and
any failure leaves every item unchanged. There is no idempotent response replay;
after a lost response, reload the items before retrying.

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

## 8. Administrator account management — B25

All endpoints require an authenticated ACTIVE account whose current database role
is ADMIN. Ordinary users receive **403 / FORBIDDEN**. These endpoints never return
password hashes, authentication-provider details, quota fields, inventory, or
private definitions. They do not promote users, change passwords, or create audit
records.

### GET /admin/users

**200**, a paginated object containing `items`, `total`, `page`, and `page_size`.
Each item exposes only `id`, `email`, `role`, `status`, `created_at`, and
`updated_at`. Results sort by `created_at` descending and then ID descending.
Counts and items use one database statement.

| Parameter | Default / meaning |
| --- | --- |
| q | Empty; trimmed literal case-insensitive email substring, at most 100 characters |
| role | ALL; also USER or ADMIN |
| status | ALL; also ACTIVE, SUSPENDED, or DISABLED |
| page, page_size | 1 and 20; page ≥1, page_size 1–100 |

Unknown parameters and invalid values return **422 / VALIDATION_ERROR**.

### GET /admin/users/{id}

**200**, one administrator-safe user response with the same fields as the list.
A missing user returns **404 / NOT_FOUND**. This read does not expose or inspect the
user's inventory.

### PATCH /admin/users/{id}/status

```json
{"status":"SUSPENDED"}
```

The body accepts only `status=ACTIVE|SUSPENDED|DISABLED`. The target must have
`role=USER`; targeting the current or another administrator returns **403 /
ADMIN_TARGET_FORBIDDEN**. A missing target returns **404 / NOT_FOUND**.

**200**, the updated administrator-safe user response. The write changes only
status and updated_at. Repeating the current status is a no-op and preserves
updated_at. A suspended or disabled account is rejected by subsequent authenticated
requests because every request reads current account state. Requests already in
progress are not cancelled.

## 9. Agent V0.2 — chat, resume and recovery

The Agent uses the same backend base URL, `/api/v1` prefix and Bearer authentication
as other APIs. User identity comes from the token, never from client-supplied IDs.
Swagger is available at `<backend-base>/docs` under `agent`; OpenAPI is at
`<backend-base>/openapi.json`. POST request bodies are JSON. Successful chat/resume
responses are SSE (`text/event-stream`); state responses are ordinary JSON.

| User action | Interface | Frontend behavior |
| --- | --- | --- |
| Send a new message/photo | `POST /api/v1/agent/chat` | Show the reply or proposed stock entries |
| Answer, edit, supplement, confirm or cancel a pending item | `POST /api/v1/agent/resume` | Update the existing item using the new response |
| Refresh or recover after losing a response | `GET /api/v1/agent/conversations/{conversation_id}/state` | Restore current progress before retrying |

**A photo request and its confirmation are two separate HTTP requests/streams.**
The first stream ends with `WAITING_INPUT`; the server does not keep it open while
waiting for the user's click. The frontend then starts a new resume request.
A turn has at most 20 independently handled items. One failure does not roll back
other successful items, unlike an atomic manual batch operation.

Text stock requests are recorded as unfinished work before normal model/tool replies.
A purchase with missing storage returns WAITING_INPUT and an action_required item,
plus a short text_delta question. The same question is in display.question on state
and replay. After the user supplies a clear location, exact stock may execute directly
without another confirmation, including first-time product/space creation.

Chat/resume request schemas and event names are unchanged. Internal drafts add
optional clarification_question and new_space_source_text; clients do not supply
these as request fields. Missing new checkpoint fields have defaults. Old confirmation
proposals remain waiting until explicitly answered; completed requests are not rerun.
No database migration is needed.

Stock completion text is derived from actual per-item results (English/Chinese),
not a second model interpretation of whether approval is needed. Estimated remaining
quantities stay labeled as estimates. Queries still use model-generated plain text.

Start with the [frontend interaction guide](AGENT_FRONTEND_INTEGRATION.md).
Graph/memory rules: [architecture](ARCHITECTURE.md). Environment and storage:
[backend README](../backend/README.md#agent-configuration-and-storage).

#### Identifier meanings

| Field | Meaning |
| --- | --- |
| conversation_id | Conversation UUID, retained across turns |
| request_id | UUID for one chat or resume submission; reuse only for identical retries |
| item_id | Stable Agent work-item UUID; **not** an inventory record ID |
| proposal_id | Current version of a candidate; changes after edits/supplements |
| interrupt_id | Opaque current pause token returned by the backend; do not generate it |
| image_id | Client-generated UUID bound to immutable image bytes/type in this conversation |
| result.inventory.id | Actual inventory batch UUID, available after successful creation |

`start.request_id` identifies the current HTTP submission. State responses and
`done.data.request_id` identify the original chat turn, even after a resume request.

### POST /api/v1/agent/chat

**Purpose:** send a new text/image message when the conversation is not paused.
Image-only messages can lead to a question about intent; upload is not approval.

**Request fields**

| Field | Required | Meaning |
| --- | --- | --- |
| message | Text or images required | User text, trimmed, up to 8,000 characters; defaults to empty |
| images | Text or images required | Attachment array; defaults to empty; format and limits below |
| conversation_id | No | Existing conversation UUID, or omit for a new conversation |
| request_id | Recommended | Client-generated UUID for safe retries; generated by server if omitted |
| as_of | No | User's local date, YYYY-MM-DD; do not substitute server-local time |

Provide nonempty message, images, or both. Unknown fields are rejected. Existing
text-only clients remain compatible. Supplying request_id without conversation_id
produces a stable initial conversation for that user/request.

**Request example — two bottles of milk**

All examples below use the same illustrative IDs. They are not production records.
The definition, category and fridge already exist. Package size is 500ml each;
stock is entered as 2 bottles. Unknown purchase/expiry dates remain null. Replace
the base64 placeholder with real image bytes before sending; the example IDs for
existing resources must also be replaced with your own resources.

```json
{
  "message": "Please enter these two bottles of milk in my fridge; let me review first.",
  "conversation_id": "00000000-0000-4000-8000-000000000001",
  "request_id": "00000000-0000-4000-8000-000000000002",
  "as_of": "2026-09-27",
  "images": [
    {
      "image_id": "00000000-0000-4000-8000-000000000006",
      "mime_type": "image/jpeg",
      "data_base64": "<replace with actual JPEG base64; no data-URL prefix>"
    }
  ]
}
```

**Response:** HTTP 200, `Content-Type: text/event-stream`. `start` returns the
conversation/request IDs. The milk example emits preview, pause and done events;
the [complete streams](#agent-milk-sse-example) below show their actual structure.

**Error handling**

| HTTP / code | Meaning and next action |
| --- | --- |
| 401 | Missing, expired or invalid Bearer token; use the existing login flow |
| 409 AGENT_INPUT_REQUIRED | Existing turn is paused; use resume with current identifiers |
| 409 AGENT_CONVERSATION_BUSY | Another request is running; do not send competing turns |
| 409 AGENT_RECOVERY_REQUIRED | An unfinished turn exists; recover using its original request |
| 409 REQUEST_ID_CONFLICT | The request ID was reused with different content |
| 409 IMAGE_ID_CONFLICT | An existing image ID was reused with different bytes/type |
| 413 / 422 | Invalid or oversized request; see shared image/validation rules below |
| 503 AGENT_UNAVAILABLE | Agent persistence/setup is unavailable |

After the stream starts, execution errors arrive as SSE `error`; see Events.

### POST /api/v1/agent/resume

**Purpose:** reply to a current pause; do not use this endpoint for unrelated new work.

**Request fields**

| Field | Required | Meaning |
| --- | --- | --- |
| conversation_id | Yes | Conversation UUID from chat/start |
| interrupt_id | Yes | Current pause token from action_required or state |
| request_id | Yes | New UUID for this user response; reuse for identical retries |
| responses | Yes | 1–20 replies, each targeting a distinct pending item |

Each response contains item_id, current proposal_id and decision:

| decision | Accepted additional fields | Behavior |
| --- | --- | --- |
| confirm | None | Execute this reviewed version; cannot include changes |
| cancel | None | Cancel this unexecuted item |
| answer | message, images or selected_inventory_item_id; at least one | Supply missing information |
| edit | message, images or selected_inventory_item_id; at least one | Revise the item and invalidate the previous proposal |

message is nonempty text up to 2,000 characters. selected_inventory_item_id must
come from the current question's candidates; ownership is revalidated. Images can
be the only supplement and apply only to the identified pending item. Partial
replies are allowed; other questions remain pending. Missing information must be
answered before confirmation. Never submit a client-calculated balance or delta.

**Request example — confirm the milk candidate**

```json
{
  "conversation_id": "00000000-0000-4000-8000-000000000001",
  "interrupt_id": "f32fc44597354a7f8fe578bf5ba12bed",
  "request_id": "00000000-0000-4000-8000-000000000003",
  "responses": [
    {
      "item_id": "00000000-0000-4000-8000-000000000004",
      "proposal_id": "00000000-0000-4000-8000-000000000005",
      "decision": "confirm"
    }
  ]
}
```

**Response:** HTTP 200 SSE, on a new connection. The example emits an actual
operation_result, reply text and done. Confirming several items still commits each
independently. [Complete confirmation stream](#agent-milk-sse-example).

**Error handling**

| HTTP / code | Meaning and next action |
| --- | --- |
| 401 | Use the existing authentication flow |
| 409 STALE_INTERRUPT / STALE_PROPOSAL | Reload state and use current identifiers |
| 409 REQUEST_ID_CONFLICT / IMAGE_ID_CONFLICT | Do not reuse IDs with altered content |
| 409 AGENT_CONVERSATION_BUSY | Another request is still running |
| 409 VERIFY_OUTCOME_FIRST | Previous commit outcome is unknown; verify via receipt-first confirmation retry |
| 422 ANSWER_REQUIRED | Supply missing information before confirming |
| 422 INVALID_TARGET_SELECTION | Select only from the current candidates |
| 413 / 422 | Request size, image or schema validation failed |
| 503 AGENT_UNAVAILABLE | Agent persistence/setup is unavailable |

An item marked EXECUTION_UNCERTAIN may already have committed. Confirmation retries
its unchanged receipt first; editing or cancelling it is rejected with
VERIFY_OUTCOME_FIRST. After a stream error/disconnection query state before retrying.

### GET /api/v1/agent/conversations/{conversation_id}/state

**Purpose:** restore business progress after refresh, lost response or interruption.
It does not return full chat history, raw image bytes or internal model messages.

**Request fields:** required conversation_id UUID in the path and the usual Bearer
token. No request body.

**Request example**

```http
GET /api/v1/agent/conversations/00000000-0000-4000-8000-000000000001/state
Authorization: Bearer <token>
```

**Response:** HTTP 200, `Content-Type: application/json`.

| Field | Meaning |
| --- | --- |
| request_id | Original chat turn UUID, not the latest resume UUID |
| status | COMPLETED, WAITING_INPUT or RECOVERABLE |
| items | All work items in this turn, including completed and pending items |
| interrupt_id | Present while interrupted; use the current value for resume |
| pending | Current interrupt payload; pending.items contains items awaiting input |

Item states are DRAFT, READY, NEEDS_INPUT, NEEDS_CONFIRMATION, SUCCEEDED, FAILED
and CANCELLED. Optional fields without values can be omitted. COMPLETED means no
pending work, **not** that every item succeeded. Check each item's status.
RECOVERABLE means the previous execution has unfinished steps; retry the original
chat/resume request with its original ID/body rather than creating new work.

<details>
<summary>Complete JSON: waiting for milk confirmation</summary>

```json
{
  "request_id": "00000000-0000-4000-8000-000000000002",
  "status": "WAITING_INPUT",
  "items": [
    {
      "item_id": "00000000-0000-4000-8000-000000000004",
      "item_key": "milk",
      "proposal_id": "00000000-0000-4000-8000-000000000005",
      "status": "NEEDS_CONFIRMATION",
      "original_text": "MILK 2 bottles",
      "preview": {
        "draft": {
          "item_key": "milk",
          "original_text": "MILK 2 bottles",
          "action": "CREATE_STOCK",
          "inventory_item_id": null,
          "item_query": "Milk",
          "storage_space_id": "00000000-0000-4000-8000-000000000007",
          "item_definition_id": "00000000-0000-4000-8000-000000000008",
          "new_space": null,
          "new_definition": null,
          "quantity_kind": "AMOUNT",
          "quantity_value": "2",
          "quantity_unit": "bottle",
          "purchase_date": null,
          "expiry_date": null,
          "utensil": null,
          "estimate": null,
          "source_image_ids": [
            "00000000-0000-4000-8000-000000000006"
          ],
          "package_description": "500ml per bottle",
          "review_notes": []
        },
        "before": null,
        "display": {
          "item_name": "Milk",
          "space_name": "Fridge",
          "category_id": "00000000-0000-4000-8000-000000000009",
          "category_name": "Dairy"
        },
        "image_policy": {
          "create_only": true,
          "requires_review": true,
          "source_image_ids": [
            "00000000-0000-4000-8000-000000000006"
          ]
        },
        "confirmation_reasons": [
          "IMAGE_REVIEW"
        ],
        "after": {
          "confirmed_current_amount": "2",
          "confirmed_current_unit": "bottle",
          "estimated_current_amount": null
        },
        "calculation_method": "EXACT",
        "affects_state": "CONFIRMED",
        "memory_snapshots": [],
        "requires_confirmation": true,
        "expected_version": null
      },
      "display": {
        "item_name": "Milk",
        "space_name": "Fridge",
        "category_id": "00000000-0000-4000-8000-000000000009",
        "category_name": "Dairy",
        "source_image_ids": [
          "00000000-0000-4000-8000-000000000006"
        ],
        "recognized_text": "MILK 2 bottles",
        "package_description": "500ml per bottle",
        "review_notes": [],
        "missing_fields": [],
        "confirmation_reasons": [
          "IMAGE_REVIEW"
        ]
      }
    }
  ],
  "interrupt_id": "f32fc44597354a7f8fe578bf5ba12bed",
  "pending": {
    "items": [
      {
        "item_id": "00000000-0000-4000-8000-000000000004",
        "item_key": "milk",
        "proposal_id": "00000000-0000-4000-8000-000000000005",
        "status": "NEEDS_CONFIRMATION",
        "original_text": "MILK 2 bottles",
        "preview": {
          "draft": {
            "item_key": "milk",
            "original_text": "MILK 2 bottles",
            "action": "CREATE_STOCK",
            "inventory_item_id": null,
            "item_query": "Milk",
            "storage_space_id": "00000000-0000-4000-8000-000000000007",
            "item_definition_id": "00000000-0000-4000-8000-000000000008",
            "new_space": null,
            "new_definition": null,
            "quantity_kind": "AMOUNT",
            "quantity_value": "2",
            "quantity_unit": "bottle",
            "purchase_date": null,
            "expiry_date": null,
            "utensil": null,
            "estimate": null,
            "source_image_ids": [
              "00000000-0000-4000-8000-000000000006"
            ],
            "package_description": "500ml per bottle",
            "review_notes": []
          },
          "before": null,
          "display": {
            "item_name": "Milk",
            "space_name": "Fridge",
            "category_id": "00000000-0000-4000-8000-000000000009",
            "category_name": "Dairy"
          },
          "image_policy": {
            "create_only": true,
            "requires_review": true,
            "source_image_ids": [
              "00000000-0000-4000-8000-000000000006"
            ]
          },
          "confirmation_reasons": [
            "IMAGE_REVIEW"
          ],
          "after": {
            "confirmed_current_amount": "2",
            "confirmed_current_unit": "bottle",
            "estimated_current_amount": null
          },
          "calculation_method": "EXACT",
          "affects_state": "CONFIRMED",
          "memory_snapshots": [],
          "requires_confirmation": true,
          "expected_version": null
        },
        "display": {
          "item_name": "Milk",
          "space_name": "Fridge",
          "category_id": "00000000-0000-4000-8000-000000000009",
          "category_name": "Dairy",
          "source_image_ids": [
            "00000000-0000-4000-8000-000000000006"
          ],
          "recognized_text": "MILK 2 bottles",
          "package_description": "500ml per bottle",
          "review_notes": [],
          "missing_fields": [],
          "confirmation_reasons": [
            "IMAGE_REVIEW"
          ]
        }
      }
    ]
  }
}
```

</details>

In this example items and pending.items repeat the same item because it is the only
pending entry. In a multi-item turn, items can also include successful/failed items.

<details>
<summary>Complete JSON: milk successfully created</summary>

```json
{
  "request_id": "00000000-0000-4000-8000-000000000002",
  "status": "COMPLETED",
  "items": [
    {
      "item_id": "00000000-0000-4000-8000-000000000004",
      "item_key": "milk",
      "proposal_id": "00000000-0000-4000-8000-000000000005",
      "status": "SUCCEEDED",
      "original_text": "MILK 2 bottles",
      "preview": {
        "draft": {
          "item_key": "milk",
          "original_text": "MILK 2 bottles",
          "action": "CREATE_STOCK",
          "inventory_item_id": null,
          "item_query": "Milk",
          "storage_space_id": "00000000-0000-4000-8000-000000000007",
          "item_definition_id": "00000000-0000-4000-8000-000000000008",
          "new_space": null,
          "new_definition": null,
          "quantity_kind": "AMOUNT",
          "quantity_value": "2",
          "quantity_unit": "bottle",
          "purchase_date": null,
          "expiry_date": null,
          "utensil": null,
          "estimate": null,
          "source_image_ids": [
            "00000000-0000-4000-8000-000000000006"
          ],
          "package_description": "500ml per bottle",
          "review_notes": []
        },
        "before": null,
        "display": {
          "item_name": "Milk",
          "space_name": "Fridge",
          "category_id": "00000000-0000-4000-8000-000000000009",
          "category_name": "Dairy"
        },
        "image_policy": {
          "create_only": true,
          "requires_review": true,
          "source_image_ids": [
            "00000000-0000-4000-8000-000000000006"
          ]
        },
        "confirmation_reasons": [
          "IMAGE_REVIEW"
        ],
        "after": {
          "confirmed_current_amount": "2",
          "confirmed_current_unit": "bottle",
          "estimated_current_amount": null
        },
        "calculation_method": "EXACT",
        "affects_state": "CONFIRMED",
        "memory_snapshots": [],
        "requires_confirmation": true,
        "expected_version": null
      },
      "result": {
        "inventory": {
          "id": "00000000-0000-4000-8000-000000000010",
          "storage_space_id": "00000000-0000-4000-8000-000000000007",
          "storage_space_name": "Fridge",
          "item_definition_id": "00000000-0000-4000-8000-000000000008",
          "item_definition_name": "Milk",
          "category_id": "00000000-0000-4000-8000-000000000009",
          "category_name": "Dairy",
          "purchase_date": null,
          "expiry_date": null,
          "notes": null,
          "status": "IN_STOCK",
          "initial_amount": "2.000",
          "initial_unit": "bottle",
          "confirmed_current_amount": "2.000",
          "confirmed_current_unit": "bottle",
          "confirmed_at": "2026-09-27T01:00:00Z",
          "estimated_current_amount": null,
          "estimated_current_unit": null,
          "estimated_at": null,
          "display_amount": "2.000",
          "display_unit": "bottle",
          "is_estimated": false,
          "version": 1,
          "created_at": "2026-09-27T01:00:00Z",
          "updated_at": "2026-09-27T01:00:00Z"
        },
        "operation": null,
        "replayed": false
      },
      "display": {
        "item_name": "Milk",
        "space_name": "Fridge",
        "category_id": "00000000-0000-4000-8000-000000000009",
        "category_name": "Dairy",
        "source_image_ids": [
          "00000000-0000-4000-8000-000000000006"
        ],
        "recognized_text": "MILK 2 bottles",
        "package_description": "500ml per bottle",
        "review_notes": [],
        "missing_fields": [],
        "confirmation_reasons": [
          "IMAGE_REVIEW"
        ]
      }
    }
  ]
}
```

</details>

The completed response has no interrupt_id/pending. A successful item retains its
old preview: preview.requires_confirmation=true describes the proposal that was
reviewed, not a new request for approval. Render buttons based on item status and
the current interrupt, not this historical flag.

**Error handling:** 401 for invalid identity; 404 NOT_FOUND for an unknown or
another user's conversation; 422 for invalid path UUID; 503 AGENT_UNAVAILABLE when
state cannot be read. Do not display another user's conversation based on client IDs.

### Events

| Event | Payload | Frontend action |
| --- | --- | --- |
| start | conversation_id, request_id | Save request/conversation identifiers |
| text_delta | delta | Append user-facing reply text |
| operation_preview | data: public item, preview and display | Update the candidate card; no write has succeeded yet |
| action_required | data: interrupt_id and items; replay may return full state | Show inputs/confirmation; retain current pause token |
| operation_result | data: item status, actual result or error | Update that item's outcome |
| done | status and data: current public state | End loading; WAITING_INPUT still needs user action |
| error | code and sanitized message | Query state before choosing how to recover |

Only final user-facing content is exposed. Text may arrive in chunks or in one
text_delta after generation; chunk boundaries and wording are not contractual.
Some ordinary replies emit only start/text_delta/done. A request may contain
multiple previews/results, and a retry can replay them. Reconcile by item_id and
replace proposal_id when a candidate changes.

<a id="agent-milk-sse-example"></a>

#### Complete example: photo, review, confirmation

```text
POST chat -> start -> operation_preview -> action_required -> done(WAITING_INPUT)
[First HTTP response closes; the user reviews the candidate]
POST resume -> start -> operation_result -> text_delta -> done(COMPLETED)
```

Each raw event below has an event line and a single JSON data line followed by a
blank line. The objects are complete, not abbreviated. Long lines are intentionally
inside collapsible examples to keep the main flow readable.

<details>
<summary>First HTTP response: chat waits for confirmation</summary>

```text
event: start
data: {"type":"start","conversation_id":"00000000-0000-4000-8000-000000000001","request_id":"00000000-0000-4000-8000-000000000002"}

event: operation_preview
data: {"type":"operation_preview","data":{"item_id":"00000000-0000-4000-8000-000000000004","item_key":"milk","proposal_id":"00000000-0000-4000-8000-000000000005","status":"NEEDS_CONFIRMATION","original_text":"MILK 2 bottles","preview":{"draft":{"item_key":"milk","original_text":"MILK 2 bottles","action":"CREATE_STOCK","inventory_item_id":null,"item_query":"Milk","storage_space_id":"00000000-0000-4000-8000-000000000007","item_definition_id":"00000000-0000-4000-8000-000000000008","new_space":null,"new_definition":null,"quantity_kind":"AMOUNT","quantity_value":"2","quantity_unit":"bottle","purchase_date":null,"expiry_date":null,"utensil":null,"estimate":null,"source_image_ids":["00000000-0000-4000-8000-000000000006"],"package_description":"500ml per bottle","review_notes":[]},"before":null,"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy"},"image_policy":{"create_only":true,"requires_review":true,"source_image_ids":["00000000-0000-4000-8000-000000000006"]},"confirmation_reasons":["IMAGE_REVIEW"],"after":{"confirmed_current_amount":"2","confirmed_current_unit":"bottle","estimated_current_amount":null},"calculation_method":"EXACT","affects_state":"CONFIRMED","memory_snapshots":[],"requires_confirmation":true,"expected_version":null},"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","source_image_ids":["00000000-0000-4000-8000-000000000006"],"recognized_text":"MILK 2 bottles","package_description":"500ml per bottle","review_notes":[],"missing_fields":[],"confirmation_reasons":["IMAGE_REVIEW"]}}}

event: action_required
data: {"type":"action_required","data":{"interrupt_id":"f32fc44597354a7f8fe578bf5ba12bed","items":[{"item_id":"00000000-0000-4000-8000-000000000004","item_key":"milk","proposal_id":"00000000-0000-4000-8000-000000000005","status":"NEEDS_CONFIRMATION","original_text":"MILK 2 bottles","preview":{"draft":{"item_key":"milk","original_text":"MILK 2 bottles","action":"CREATE_STOCK","inventory_item_id":null,"item_query":"Milk","storage_space_id":"00000000-0000-4000-8000-000000000007","item_definition_id":"00000000-0000-4000-8000-000000000008","new_space":null,"new_definition":null,"quantity_kind":"AMOUNT","quantity_value":"2","quantity_unit":"bottle","purchase_date":null,"expiry_date":null,"utensil":null,"estimate":null,"source_image_ids":["00000000-0000-4000-8000-000000000006"],"package_description":"500ml per bottle","review_notes":[]},"before":null,"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy"},"image_policy":{"create_only":true,"requires_review":true,"source_image_ids":["00000000-0000-4000-8000-000000000006"]},"confirmation_reasons":["IMAGE_REVIEW"],"after":{"confirmed_current_amount":"2","confirmed_current_unit":"bottle","estimated_current_amount":null},"calculation_method":"EXACT","affects_state":"CONFIRMED","memory_snapshots":[],"requires_confirmation":true,"expected_version":null},"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","source_image_ids":["00000000-0000-4000-8000-000000000006"],"recognized_text":"MILK 2 bottles","package_description":"500ml per bottle","review_notes":[],"missing_fields":[],"confirmation_reasons":["IMAGE_REVIEW"]}}]}}

event: done
data: {"type":"done","status":"WAITING_INPUT","data":{"request_id":"00000000-0000-4000-8000-000000000002","status":"WAITING_INPUT","items":[{"item_id":"00000000-0000-4000-8000-000000000004","item_key":"milk","proposal_id":"00000000-0000-4000-8000-000000000005","status":"NEEDS_CONFIRMATION","original_text":"MILK 2 bottles","preview":{"draft":{"item_key":"milk","original_text":"MILK 2 bottles","action":"CREATE_STOCK","inventory_item_id":null,"item_query":"Milk","storage_space_id":"00000000-0000-4000-8000-000000000007","item_definition_id":"00000000-0000-4000-8000-000000000008","new_space":null,"new_definition":null,"quantity_kind":"AMOUNT","quantity_value":"2","quantity_unit":"bottle","purchase_date":null,"expiry_date":null,"utensil":null,"estimate":null,"source_image_ids":["00000000-0000-4000-8000-000000000006"],"package_description":"500ml per bottle","review_notes":[]},"before":null,"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy"},"image_policy":{"create_only":true,"requires_review":true,"source_image_ids":["00000000-0000-4000-8000-000000000006"]},"confirmation_reasons":["IMAGE_REVIEW"],"after":{"confirmed_current_amount":"2","confirmed_current_unit":"bottle","estimated_current_amount":null},"calculation_method":"EXACT","affects_state":"CONFIRMED","memory_snapshots":[],"requires_confirmation":true,"expected_version":null},"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","source_image_ids":["00000000-0000-4000-8000-000000000006"],"recognized_text":"MILK 2 bottles","package_description":"500ml per bottle","review_notes":[],"missing_fields":[],"confirmation_reasons":["IMAGE_REVIEW"]}}],"interrupt_id":"f32fc44597354a7f8fe578bf5ba12bed","pending":{"items":[{"item_id":"00000000-0000-4000-8000-000000000004","item_key":"milk","proposal_id":"00000000-0000-4000-8000-000000000005","status":"NEEDS_CONFIRMATION","original_text":"MILK 2 bottles","preview":{"draft":{"item_key":"milk","original_text":"MILK 2 bottles","action":"CREATE_STOCK","inventory_item_id":null,"item_query":"Milk","storage_space_id":"00000000-0000-4000-8000-000000000007","item_definition_id":"00000000-0000-4000-8000-000000000008","new_space":null,"new_definition":null,"quantity_kind":"AMOUNT","quantity_value":"2","quantity_unit":"bottle","purchase_date":null,"expiry_date":null,"utensil":null,"estimate":null,"source_image_ids":["00000000-0000-4000-8000-000000000006"],"package_description":"500ml per bottle","review_notes":[]},"before":null,"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy"},"image_policy":{"create_only":true,"requires_review":true,"source_image_ids":["00000000-0000-4000-8000-000000000006"]},"confirmation_reasons":["IMAGE_REVIEW"],"after":{"confirmed_current_amount":"2","confirmed_current_unit":"bottle","estimated_current_amount":null},"calculation_method":"EXACT","affects_state":"CONFIRMED","memory_snapshots":[],"requires_confirmation":true,"expected_version":null},"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","source_image_ids":["00000000-0000-4000-8000-000000000006"],"recognized_text":"MILK 2 bottles","package_description":"500ml per bottle","review_notes":[],"missing_fields":[],"confirmation_reasons":["IMAGE_REVIEW"]}}]}}}

```

</details>

<details>
<summary>Second HTTP response: resume creates the milk batch</summary>

```text
event: start
data: {"type":"start","conversation_id":"00000000-0000-4000-8000-000000000001","request_id":"00000000-0000-4000-8000-000000000003"}

event: operation_result
data: {"type":"operation_result","data":{"item_id":"00000000-0000-4000-8000-000000000004","item_key":"milk","proposal_id":"00000000-0000-4000-8000-000000000005","status":"SUCCEEDED","original_text":"MILK 2 bottles","preview":{"draft":{"item_key":"milk","original_text":"MILK 2 bottles","action":"CREATE_STOCK","inventory_item_id":null,"item_query":"Milk","storage_space_id":"00000000-0000-4000-8000-000000000007","item_definition_id":"00000000-0000-4000-8000-000000000008","new_space":null,"new_definition":null,"quantity_kind":"AMOUNT","quantity_value":"2","quantity_unit":"bottle","purchase_date":null,"expiry_date":null,"utensil":null,"estimate":null,"source_image_ids":["00000000-0000-4000-8000-000000000006"],"package_description":"500ml per bottle","review_notes":[]},"before":null,"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy"},"image_policy":{"create_only":true,"requires_review":true,"source_image_ids":["00000000-0000-4000-8000-000000000006"]},"confirmation_reasons":["IMAGE_REVIEW"],"after":{"confirmed_current_amount":"2","confirmed_current_unit":"bottle","estimated_current_amount":null},"calculation_method":"EXACT","affects_state":"CONFIRMED","memory_snapshots":[],"requires_confirmation":true,"expected_version":null},"result":{"inventory":{"id":"00000000-0000-4000-8000-000000000010","storage_space_id":"00000000-0000-4000-8000-000000000007","storage_space_name":"Fridge","item_definition_id":"00000000-0000-4000-8000-000000000008","item_definition_name":"Milk","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","purchase_date":null,"expiry_date":null,"notes":null,"status":"IN_STOCK","initial_amount":"2.000","initial_unit":"bottle","confirmed_current_amount":"2.000","confirmed_current_unit":"bottle","confirmed_at":"2026-09-27T01:00:00Z","estimated_current_amount":null,"estimated_current_unit":null,"estimated_at":null,"display_amount":"2.000","display_unit":"bottle","is_estimated":false,"version":1,"created_at":"2026-09-27T01:00:00Z","updated_at":"2026-09-27T01:00:00Z"},"operation":null,"replayed":false},"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","source_image_ids":["00000000-0000-4000-8000-000000000006"],"recognized_text":"MILK 2 bottles","package_description":"500ml per bottle","review_notes":[],"missing_fields":[],"confirmation_reasons":["IMAGE_REVIEW"]}}}

event: text_delta
data: {"type":"text_delta","delta":"Added 2 bottles of milk"}

event: text_delta
data: {"type":"text_delta","delta":" to your fridge."}

event: done
data: {"type":"done","status":"COMPLETED","data":{"request_id":"00000000-0000-4000-8000-000000000002","status":"COMPLETED","items":[{"item_id":"00000000-0000-4000-8000-000000000004","item_key":"milk","proposal_id":"00000000-0000-4000-8000-000000000005","status":"SUCCEEDED","original_text":"MILK 2 bottles","preview":{"draft":{"item_key":"milk","original_text":"MILK 2 bottles","action":"CREATE_STOCK","inventory_item_id":null,"item_query":"Milk","storage_space_id":"00000000-0000-4000-8000-000000000007","item_definition_id":"00000000-0000-4000-8000-000000000008","new_space":null,"new_definition":null,"quantity_kind":"AMOUNT","quantity_value":"2","quantity_unit":"bottle","purchase_date":null,"expiry_date":null,"utensil":null,"estimate":null,"source_image_ids":["00000000-0000-4000-8000-000000000006"],"package_description":"500ml per bottle","review_notes":[]},"before":null,"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy"},"image_policy":{"create_only":true,"requires_review":true,"source_image_ids":["00000000-0000-4000-8000-000000000006"]},"confirmation_reasons":["IMAGE_REVIEW"],"after":{"confirmed_current_amount":"2","confirmed_current_unit":"bottle","estimated_current_amount":null},"calculation_method":"EXACT","affects_state":"CONFIRMED","memory_snapshots":[],"requires_confirmation":true,"expected_version":null},"result":{"inventory":{"id":"00000000-0000-4000-8000-000000000010","storage_space_id":"00000000-0000-4000-8000-000000000007","storage_space_name":"Fridge","item_definition_id":"00000000-0000-4000-8000-000000000008","item_definition_name":"Milk","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","purchase_date":null,"expiry_date":null,"notes":null,"status":"IN_STOCK","initial_amount":"2.000","initial_unit":"bottle","confirmed_current_amount":"2.000","confirmed_current_unit":"bottle","confirmed_at":"2026-09-27T01:00:00Z","estimated_current_amount":null,"estimated_current_unit":null,"estimated_at":null,"display_amount":"2.000","display_unit":"bottle","is_estimated":false,"version":1,"created_at":"2026-09-27T01:00:00Z","updated_at":"2026-09-27T01:00:00Z"},"operation":null,"replayed":false},"display":{"item_name":"Milk","space_name":"Fridge","category_id":"00000000-0000-4000-8000-000000000009","category_name":"Dairy","source_image_ids":["00000000-0000-4000-8000-000000000006"],"recognized_text":"MILK 2 bottles","package_description":"500ml per bottle","review_notes":[],"missing_fields":[],"confirmation_reasons":["IMAGE_REVIEW"]}}]}}

```

</details>

**Parsing and recovery rules**

- Check HTTP status and Content-Type first. Authentication/validation failures
  before streaming return JSON; a successful HTTP 200 stream can still emit error.
- Use a client supporting POST, headers and a JSON body (for Web, fetch or a POST
  SSE library). Native EventSource cannot send this request as required.
- Decode UTF-8 incrementally, buffer incomplete lines/events and parse data only
  after a complete SSE event. A network chunk may split an event or contain several.
- Read until done, error or disconnect. An error ends the response and need not
  be followed by done. Query state after losing a response; a write may have committed.
- A retry uses the same request ID and identical body/image bytes/order. An edit
  uses a new request ID; a replaced image uses a new image ID. Keep originals locally.

Example in-stream failure (HTTP status is already 200):

```text
event: error
data: {"type":"error","code":"AGENT_EXECUTION_FAILED","message":"Execution interrupted; query conversation state and retry with the same request ID"}

```

### Multimodal messages and frontend contract

The same model receives text and images together. There is no OCR endpoint, second
vision model, upload endpoint, or client-supplied `image_kind`. Speech recognition
is a frontend input method: send the text only after the user edits/sends it.

```json
{
  "message": "Please enter these in my fridge",
  "request_id": "<uuid>",
  "conversation_id": "<uuid>",
  "as_of": "2026-09-26",
  "images": [{"image_id": "<uuid>", "mime_type": "image/jpeg", "data_base64": "<raw base64, without data-URL prefix>"}]
}
```

`message` defaults to an empty string; image-only messages are accepted. Images
are data, not authorization: ambiguous uploads prompt a normal conversational
reply, visual questions are answered without stock creation. Send a normal `/chat`
reply when there is no interrupt; use `/resume` only after `action_required`.

Limits apply to all images in one HTTP request (including all resume responses):
at most 4 distinct image IDs, 3 MiB decoded per image, 8 MiB decoded in total,
20 million pixels per image; JPEG/PNG/WebP still images only. Convert HEIC and
compress/rotate on the client. The entire JSON body is limited to 12 MiB, including
base64 expansion; both declared and streamed body sizes are checked.

An image ID is a client-generated UUID bound to immutable bytes/type in this
conversation. Retries keep request ID, image IDs, image ordering, text and bytes
unchanged. A new image/replacement gets a new image ID; edited requests get a new
request ID. Image-only supplement example:

```json
{
  "conversation_id": "<uuid>", "interrupt_id": "<current interrupt>", "request_id": "<new uuid>",
  "responses": [{
    "item_id": "<pending item uuid>", "proposal_id": "<current proposal uuid>",
    "decision": "edit",
    "images": [{"image_id": "<new uuid>", "mime_type": "image/png", "data_base64": "<raw base64>"}]
  }]
}
```

Image tasks support new stock batches only, not modification of existing batches.
Image-derived creation always waits for review; historic images visible to the
model also force review of new-stock proposals, even if the model omits source
references. Sending an image is not confirmation. After completing/cancelling a
stock task, ordinary text operations retain their previous behavior.

Public items in preview/result/waiting/state responses add a `display` object:

| Field | Meaning |
| --- | --- |
| item_name / space_name | Display labels; may be empty before resolving missing information |
| category_id / category_name | Validated category for a prepared new-stock proposal |
| source_image_ids | Validated image references; conservative fallback may include all historical images |
| recognized_text | Model transcription/source wording, not guaranteed OCR truth |
| package_description | Optional label detail, e.g. 500ml per bottle; not a second stock balance |
| review_notes | Model-supplied notes requiring user attention |
| missing_fields | Required fields identified by backend preparation errors |
| confirmation_reasons | IMAGE_REVIEW for new-stock previews; legacy pending proposals may retain NEW_ASSOCIATION |
| question | Optional short plain-text question, checkpointed for waiting items and repeated on replay/state recovery |

Preview `draft` retains quantity_value, quantity_unit, purchase_date, expiry_date,
and storage/item-definition IDs. `after` contains the actual proposed stock amount.
Show quantity/units explicitly. Do not convert package counts on the frontend.
Missing dates remain null. Names and image text must be rendered as text, not HTML.

Up to 20 requested items per turn. A model-reported overflow returns a normal
reply asking for a smaller group; no partial set is accepted. Detection is not a
guarantee that every photographed item or receipt row was recognized.

| HTTP status / code | Frontend action |
| --- | --- |
| 413 REQUEST_TOO_LARGE | Reduce the entire request size before sending with a new request ID |
| 422 INVALID_IMAGE / IMAGE_DIMENSIONS_EXCEEDED / ANIMATED_IMAGE_NOT_SUPPORTED | Replace/convert the image |
| 422 IMAGE_TOO_LARGE / IMAGE_BATCH_TOO_LARGE | Compress images or split the request |
| 422 DUPLICATE_IMAGE_ID | Give separate attachments separate IDs |
| 409 IMAGE_ID_CONFLICT | A reused image ID has different bytes/type; assign a new image ID |
| 409 REQUEST_ID_CONFLICT | Do not reuse an existing request ID with different content |
| 409 STALE_PROPOSAL / STALE_INTERRUPT | Reload state and operate on the current candidate |

422 validation responses use `detail[]` with `type`, `loc`, `msg`; generic schema
errors such as unsupported MIME types and list/string length limits also use this
shape. They never echo image input. HTTP 409/413 errors use `detail.code`. Resume business validation errors such as
ANSWER_REQUIRED and INVALID_TARGET_SELECTION also use `detail.code` with HTTP 422;
distinguish these from the schema-validation `detail[]` shape.
There are no new SSE event names. A `done` event with WAITING_INPUT is not a
successful write. Batch confirmation uses multiple existing confirm responses;
each item commits independently, not as one atomic batch.

The state endpoint does not return images or full chat history. Keep thumbnails
and in-flight request bodies locally for retries; after lost responses fetch
state before choosing chat/resume. Images persist with checkpoints, have no
separate automatic expiry, and are not returned in SSE or written into action
receipt snapshots. The frontend interaction guide is [Agent frontend integration](AGENT_FRONTEND_INTEGRATION.md).
The runnable request example below is maintained here with the API contract.


#### Runnable image request example

<details>
<summary>Python example: send a photo and print SSE events</summary>

在后端虚拟环境运行以下 Python 代码。环境变量 `SAYFRIDGE_TOKEN` 为已登录用户的 token，
`SAYFRIDGE_IMAGE` 为本地图片路径，`SAYFRIDGE_API` 默认为本机服务。此示例只生成待核对候选，
不自动确认；首次调试应使用测试账号。保存 body 以便网络失败后原样重试。

```python
import base64
import json
import mimetypes
import os
from datetime import date
from pathlib import Path
from uuid import uuid4
import httpx

path = Path(os.environ["SAYFRIDGE_IMAGE"])
body = {
    "message": "请把照片里的食品录入库存，先让我核对。",
    "request_id": str(uuid4()),
    "conversation_id": str(uuid4()),
    "as_of": date.today().isoformat(),  # 使用用户设备当地日期
    "images": [{
        "image_id": str(uuid4()),
        "mime_type": mimetypes.guess_type(path.name)[0],
        "data_base64": base64.b64encode(path.read_bytes()).decode("ascii"),
    }],
}
with httpx.stream(
    "POST", os.getenv("SAYFRIDGE_API", "http://127.0.0.1:8000") + "/api/v1/agent/chat",
    headers={"Authorization": "Bearer " + os.environ["SAYFRIDGE_TOKEN"]},
    json=body, timeout=180,
) as response:
    response.raise_for_status()
    for line in response.iter_lines():
        if line.startswith("data: "):
            print(json.loads(line[6:]))
```
</details>

### Category integration and Agent confirmation

Category HTTP response fields are unchanged. Fetch categories from `/item-categories`
and follow pagination; never hardcode seven or 25 names. Display the item-definition
name as the primary inventory label, with category as a secondary label/filter.
A category is not a restriction on the names of items users can create.
UI recommendation: initially offer categories represented in the user's inventory,
plus all categories and search. The paginated inventory response alone is not a
complete category-facet count; do not present one page as the whole inventory.

Agent `list_item_categories` additionally returns `description`, `examples` and
`exclusions` for each real active category. CREATE_STOCK previews expose
`display.category_id` and `display.category_name`, propagated into public item display.
Clear products automatically reuse an existing visible definition or create a private
definition in a real active category; a new definition alone does not require approval.
An explicitly named new storage space with a clear type is also created automatically.
Missing location/quantity or genuine product ambiguity remains NEEDS_INPUT. The user
answers through the existing resume request; no new category-ID field is added.
For an already waiting proposal, `decision: "edit"` can correct the category in a
message. Image-derived stock and estimates still require review. Completed stock
is not silently reclassified by subsequent chat.
Changing a saved definition's category affects all inventory batches referring to
that definition, not just one batch. Public definitions remain subject to existing
ownership restrictions. See [category rules](DATABASE_DESIGN.md#4-public-category-catalog-table-item_category).
