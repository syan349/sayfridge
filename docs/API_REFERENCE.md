# SayFridge API Reference: B01–B09

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
`RESOURCE_CHANGED`, `VERSION_CONFLICT`, `VERSION_LIMIT_REACHED`, and `VALIDATION_ERROR`. Error messages depend on the resource.
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


## 6. Inventory — B07–B09

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
