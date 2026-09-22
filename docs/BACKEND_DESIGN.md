# SayFridge Backend Design Handbook

> Updated: 2026-09-21. This handbook is the shared design reference for the current backend development phase. Unless an endpoint is explicitly identified as already implemented, its content is a planned contract, not evidence of passing tests or applied database migrations.
>
> The development and acceptance plan incorporates the course requirements: tests accompany features, with plans for cloud capacity, security, and deployment. Existing API business rules remain unchanged. Section 10 retains three questions for the project owner to clarify. Editing this handbook does not itself execute tests, migrations, or deployments.

Start with section 1 for scope. Use section 4 when implementing an endpoint, sections 5–7 for quantity, state, and concurrency rules, and sections 8–9 for file responsibilities and acceptance requirements.

## Contents

- [1. Scope and design references](#1-scope-and-design-references)
- [2. Architecture and database foundations](#2-architecture-and-database-foundations)
- [3. Common API contracts](#3-common-api-contracts)
- [4. API contracts by feature](#4-api-contracts-by-feature)
- [5. Quantity calculations and records](#5-quantity-calculations-and-records)
- [6. State and relationship rules](#6-state-and-relationship-rules)
- [7. Transactions, versions, and repeated requests](#7-transactions-versions-and-repeated-requests)
- [8. File responsibilities and database structure](#8-file-responsibilities-and-database-structure)
- [9. Implementation order and acceptance](#9-implementation-order-and-acceptance)
- [10. Questions for the project owner](#10-questions-for-the-project-owner)
- [11. GitHub work package mapping](#11-github-work-package-mapping)

## 1. Scope and design references

### 1.1 Goal for this phase

Implement the backend flow of logging in, managing spaces and item definitions, manually adding stock, querying inventory, adding/consuming/reconciling quantities, and viewing operation history. Also provide batch management, inventory summaries, expiry queries, and basic administrator endpoints.

### 1.2 Features outside this phase

- Reminder settings, user timezone settings, scheduled jobs, device registration, FCM push notifications, notification lists and read status, and their related tables and fields. On-demand expiry queries remain in scope.
- AI Agent, voice and image recognition, conversations, memory, undo, history recalculation, distinguishing manual versus Agent sources, and linking operations to conversations.
- Nicknames, avatars, forgotten-password recovery, token refresh, administrator audit records, complete change history, and historical snapshots.
- Correcting an inventory item's definition association, restoring discarded or archived inventory, physical deletion, merging batches, and recording partial disposal. Space and catalog restoration endpoints remain in scope.
- Frontend page implementation belongs to the Web and Flutter modules. The backend must support contract agreement and integration with both.

These exclusions apply to the current phase; they do not permanently remove features from the project. Backend delivery includes code, related tests, the notes field, API documentation, and cloud deployment preparation. Overall project delivery must also include actual cloud deployment and verification. Deployment can be staged but cannot be excluded indefinitely. The previous instruction to pause testing no longer applies to formal development; see section 9 for environment and acceptance rules.

### 1.3 Agreed design choices

| Topic | Rule and reason for this phase |
| --- | --- |
| History | Record only successful ADD / CONSUME / RECONCILE quantity operations. Initial stock creation does not record ADD; metadata changes, moves, disposal, and archival do not create events. This reduces the complete-history goal for this phase; omitted history cannot reliably be reconstructed later. Section 10.3 retains the question about reconciling the old work package wording on initial operations. |
| Item association | An inventory item's `item_definition_id` cannot change after creation, preventing existing quantity history from becoming associated with another item. See section 4.4 for correcting a wrongly entered item. |
| Quantity precision | Store changes to three decimal places using ROUND_HALF_UP, keeping the consumed amount consistent with the remaining balance. See section 5. |
| Repeated creation | Ordinary creation and batch requests do not guarantee idempotency. Clients must check results after a lost response; automatic safe retry is not promised. |
| Catalog deactivation | Prevent new associations without freezing normal management of existing inventory. |
| Operation source | `input_method` is fixed to MANUAL in this phase. Do not add source fields or operation types. |

### 1.4 How this handbook relates to implementation

This handbook merges the earlier API review draft, API implementation plan, and database implementation draft. Resolved questions are incorporated into the relevant rules without retaining separate question, decision, or file identifiers. Section numbers provide navigation; HTTP method plus path identifies an endpoint. GitHub work package numbers appear only in the mapping in section 11.

Use this handbook for the current scope and endpoint behavior. Consult the references below for database or architectural background not covered here. Merging the documents does not resolve the questions in section 10. If implementation later differs from this handbook, record the difference explicitly and update the design and verification status.

The three source documents are archived in `archive/backend-design-2026-09-11/` for traceability. They are not parallel development specifications.

| Reference | Current role | Use in this design |
| --- | --- | --- |
| [Database design](DATABASE_DESIGN.md) | Tables, fields, and permission relationships | Compare with the ORM and initial migration |
| [Quantity design](QUANTITY_STATE_DESIGN.md) | Confirmed quantities, estimates, reconciliation, and history goals | Define quantity updates; explicitly identify the reduced history scope |
| [Architecture](ARCHITECTURE.md) | Frontend, backend, and Agent boundaries | FastAPI performs all business writes |
| [Database models](../backend/app/db/models.py) | ORM fields and constraints for eight tables | Evidence of local structure, not proof of remote migration |
| [Initial table definition](../backend/migrations/versions/create_initial_tables.py) | Revision `02ec95582dc7`, creating eight tables | Maintain the latest initial table definition, including notes |
| [Database session](../backend/app/db/session.py) | Request-scoped AsyncSession | Supplies sessions without automatically committing business transactions |
| [Application entry point](../backend/app/main.py) | Registers authentication, storage-space and catalog routes, and health check | Register remaining business route groups when implemented |
| [Authentication dependencies](../backend/app/api/dependencies.py) | Validates tokens and reads current user state | Reuse identity checks and add an administrator dependency |
| [Authentication routes](../backend/app/api/routes/auth.py), [schemas](../backend/app/schemas/auth.py), and [service](../backend/app/services/auth.py) | Registration, login, and current-user endpoints already exist | Preserve compatibility and add password change |
| [Backend README](../backend/README.md) | Current startup and verification instructions | Update implemented capabilities and database setup instructions |

At the time of consolidation, health, registration, login, and current-user endpoints existed. Inventory business routes and `inventory_item.notes` did not. Code and migration files describe local structure; they do not prove that a remote database has been migrated or that business tests have passed.

### 1.5 Course requirements and coordination with both frontends

The course reference is the lecturer's *Project Information.pdf*: page 4, item 4 requires distinct reasons for using Web and Mobile; items 5–7 require a shared backend, justification of protocol choices, and consideration of expected demand; items 8–9 require frontend/backend testing and consideration of applicable OWASP security risks. Page 1 includes cloud application design, testing, and deployment objectives. The original is available through the course Canvas [Project Information](https://canvas.auckland.ac.nz/courses/142356/assignments/520538) page. Capacity figures and implementation methods in this handbook are project proposals, not lecturer-specified targets.

Both frontends share the backend defined here; do not duplicate inventory rules by client. Before frontend integration, the team must agree on users and scenarios for each frontend and map user stories to APIs and acceptance tests. Possible directions are batch organization and administration on Web, and quick recording and device capabilities on Flutter. These are discussion options, not agreed product assignments or a decision to bring voice/image features into this phase.

The backend enforces user and administrator permissions; identifying a request as Web or Flutter does not replace authentication. If frontend differences require additional APIs, update scope and contracts before implementation. Flutter owns the required Android/iOS support and multiple device capabilities, with the backend participating in end-to-end verification.

## 2. Architecture and database foundations

```text
Frontend request
  → Route: parse the request model and obtain the current user and database session
  → Service: check ownership, state, and version; calculate changes and manage transactions
  → ORM: read and write rows in the existing tables
  → PostgreSQL: execute SQL and enforce foreign keys, uniqueness, and CHECK constraints
  → Response model: expose only permitted fields
```

Routes handle HTTP parameters, dependencies, response models, and error translation. Put database queries and business rules in feature services, including simple reads, so modules follow the same structure as authentication. Services own write transactions, multi-table writes, quantity calculations, idempotency, and batches. More APIs do not necessarily require more tables. Updating data requires no migration; adding fields requires matching model, table definition, and API updates.

### 2.1 Tables and business ownership

| Table / ORM class | Meaning | Ownership and main API use |
| --- | --- | --- |
| `user` / `User` | Account, role, state, and password hash | Authentication and administrator account management |
| `storage_space` / `StorageSpace` | A user's fridge, freezer, or other space | `user_id` comes from authenticated identity; space APIs |
| `item_category` / `ItemCategory` | Public categories | Administrators write; users read |
| `item_definition` / `ItemDefinition` | Catalog entry, not actual stock | Public entries have `owner_user_id=NULL`; private definitions belong to an individual |
| `inventory_item` / `InventoryItem` | One batch of actual stock and its balance | Ownership follows `storage_space_id → user_id` |
| `inventory_operation` / `InventoryOperation` | One quantity operation | Ownership follows inventory and space; no separate user ID |
| `conversation` / `Conversation` | Conversation | No API in this phase |
| `conversation_message` / `ConversationMessage` | Conversation message | No API in this phase |

A valid foreign key does not imply a valid business relationship. It does not prove that a space belongs to the current user or prevent stock creation in an archived space. The backend must enforce these rules.

### 2.2 Existing constraints and application responsibilities

| Existing database constraint | Remaining backend responsibility |
| --- | --- |
| Active space names are unique per user and `lower(name)` | Trim whitespace, map conflicts to 409, and recheck when restoring a space |
| Category `normalized_name` is globally unique; public definitions are globally unique; private definitions are unique per user | Generate normalized names consistently. Archived catalog entries still reserve their names; do not create duplicates |
| Quantities are nonnegative `NUMERIC(12,3)` | Validate input, conversion results, applied changes, and final balances for range and precision |
| Estimated quantity, unit, and timestamp must be all null or all non-null | Update or clear all three together |
| `version >= 1`, default 1 | Explicitly check and increment it; the model does not automatically implement optimistic locking |
| Idempotency keys are globally unique and at most 128 characters | Isolate users, compare requests, and recover from concurrent conflicts |
| Operation types are limited to ADD / CONSUME / RECONCILE | Do not repurpose them to represent disposal, archival, or moves |
| Applied changes are nonnegative, with amount and unit present together | Store a positive CONSUME amount; `operation_type` indicates direction |
| `updated_at` has ORM `onupdate` behavior | Use consistent ORM updates; do not treat it as complete history or a dedicated disposal timestamp |

Frontends and the Agent perform business writes through FastAPI, not directly against the inventory database.

### 2.3 Cloud deployment and protocol choice

This phase starts with one FastAPI service and PostgreSQL. Web and Flutter access the same API over HTTPS through a cloud ingress or reverse proxy, which forwards to FastAPI and then the database. Retain the existing Neon pooled runtime connection and direct database administration connection. This is the target deployment structure; application hosting has not yet been selected or provisioned.

```text
Web / Flutter
    → HTTPS ingress (cloud ingress or reverse proxy)
    → FastAPI service
    → PostgreSQL
```

Inventory, spaces, and catalog entries support queries and changes on well-defined resources, so this phase uses REST and JSON. HTTP methods express actions, status codes express outcomes, and FastAPI supplies API documentation. Current queries and submissions do not need continuous bidirectional connections. Evaluate WebSocket, SSE, or other streaming protocols separately if future voice or Agent progress features require them. The course does not mandate a dedicated API Gateway, microservices, or autoscaling; do not add them simply to use those terms.

Do not store login sessions or idempotency records only in one application process. Authentication uses JWT and current database user state; quantity idempotency uses database records and unique constraints. Future instances must share keys, configuration, and database access and follow section 7. Adding instances does not remove lock contention on the same inventory item or space.

### 2.4 Capacity assumptions and scaling

Use the following **initial engineering assumptions** to establish a repeatable performance baseline. They have not been validated by user research or measurements. Review them before the first performance test and update both load and acceptance targets when requirements change.

| Topic | Initial assumption and purpose |
| --- | --- |
| Users | 100 registered users, 10 concurrently active users |
| Normal traffic | Aggregate 5 requests/second, approximately 80% reads and 20% writes; test authentication separately |
| Data volume | 50,000 inventory batches and 500,000 quantity operations across several users, including a user with extensive history |
| Hotspots | Test independent spaces, different inventory items in the same space, and concurrent writes to the same item separately |
| Initial performance target | After warm-up, sustain normal load for 10 minutes; read p95 ≤ 500 ms, ordinary single-item write p95 ≤ 1,000 ms, unexpected error rate < 1% |

p95 means 95% of requests complete within that duration. These are targets to verify, not current performance promises. Reports must identify application/database specifications and regions, client location, data volume, connection pools, versions, and commands. Report cold starts, login password hashing, and batch operations separately. Track deliberately induced version/state conflicts separately rather than mixing them into normal-load results to conceal errors.

Measure API latency, errors, database connections, query time, and lock waits before optimizing. For slow queries, inspect execution plans, indexes, and pagination. For connection pressure, adjust per-instance limits so instance count times connection budget stays within database capacity. Consider more application instances when application CPU saturates. Current per-space serialization prioritizes correctness; if it becomes a bottleneck, review lock granularity and rerun consistency tests.

Do not add caches or change indexes preemptively. If measurements justify schema changes, update this handbook, the ORM, and the current table definition, explaining why they exceed the current notes-only schema change.

## 3. Common API contracts

### 3.1 Requests, fields, and pagination

- All endpoints except health use `/api/v1`. All business endpoints except registration and login require valid authentication. A public catalog entry has public ownership, not anonymous access.
- Reject unknown request fields. IDs are UUIDs. The server supplies IDs, user ownership, initial states, versions, timestamps, and calculated operation fields.
- Creation POST returns 201; queries, PATCH, state actions, and password changes return 200. A new quantity operation returns 201; a replay returns 200.
- New business errors use `{"detail":{"code":"VERSION_CONFLICT","message":"Inventory has changed; refresh and retry","item_index":0}}`. Include `item_index` only for batch errors. Preserve existing authentication formats.
- Return 404 for both missing and inaccessible resources; 401 for invalid identity; 403 for non-administrators calling administrator APIs; 422 for invalid parameters; and 409 for version, state, uniqueness, or idempotency conflicts.
- An omitted PATCH field is unchanged. Explicit null clears dates and notes; other fields cannot be null. Reject PATCH with no business fields. `expected_version` is not a business change field.
- Names must be 1–100 characters after trimming. Catalog `normalized_name` uses Unicode NFKC, trim, and casefold consistently. This is a rule for new writes, not a bulk rewrite of existing catalog data. Creation/rename must also compare existing names in the same uniqueness scope using that algorithm. Return NAME_CONFLICT when an older-format equivalent exists; existing database indexes remain the final safeguard. Normalized length must also be 1–100.
- Quantities are ordinary nonnegative decimal strings with at most three decimal places. Reject scientific notation, NaN, and Infinity. Maximum: `999999999.999`.
- Units are 1–16 characters after trimming. Normalize known mass/volume units to g/kg/ml/l. Other units retain their normalized literal form and are compatible only when exactly equal; do not infer equivalence between a local count word and `each`.
- Return timezone-aware ISO 8601 timestamps. Dates remain YYYY-MM-DD; do not replace the user's date with the server's timezone-derived date.
- Lists use `items/total/page/page_size`. Default page size is 20, maximum 100; minimum page is 1. Out-of-range pages return empty items. `total` counts all filtered results.
- Ordinary creation has no idempotency guarantee. Quantity submissions require Idempotency-Key. Batch transactions are atomic but do not promise response replay.

Operation units are trimmed before storage and keep their case. Both trimmed and casefolded lengths must be 1–16 characters; calculations use the casefolded form. See the resolved decision in section 10.2.

### 3.2 Response models

| Model | Fields |
| --- | --- |
| StorageSpaceRead | id, name, type, status, created_at, updated_at |
| ItemCategoryRead | id, name, status, sort_order |
| ItemDefinitionRead | id, name, category_id, status, scope=PUBLIC/PRIVATE; do not expose another user's owner_user_id |
| InventoryItemRead | id, storage_space_id, item_definition_id, current associated names/category, purchase_date, expiry_date, notes, status, initial_*, confirmed_current_*, confirmed_at, estimated_current_*, estimated_at, version, created_at, updated_at |
| Derived inventory display fields | display_amount, display_unit, is_estimated; derive from the non-null estimate-first rule without adding columns. An estimate of zero still takes priority; do not use truthiness |
| InventoryOperationRead | id, inventory_item_id, operation_type, quantity_kind/value/unit, input_method, calculation_method, affects_state, applied_change_*, status, created_at, updated_at, undone_at |
| OperationResult | operation, inventory, replayed; inventory is current when read for the response, not a historical post-operation snapshot |
| OperationPreview | inventory_item_id, based_on_version, before display state, candidate after state, applied change, calculation method, affects_state, rounded; no authorization token that bypasses recalculation |

Do not expose the derived database idempotency key in operation responses. Quantity values are strings. Associated names are current names, not historical snapshots.

The complete nested OperationPreview structure remains open in section 10.1. The table lists only the agreed response content.

### 3.3 Shared query and response rules

- `status` accepts the corresponding database enumeration or ALL. For item definitions, `status=ACTIVE` also requires an ACTIVE category; `status=ARCHIVED` filters only the definition's own state; `status=ALL` filters neither definition nor category state. Detail queries are not restricted by default list filters.
- `q` is a literal substring search of at most 100 characters after trimming; empty means no filter. Bind SQL parameters and escape percent/underscore as literal characters. Return 422 when a date/time range starts after it ends. Time parameters must include a timezone.
- Every PATCH needs at least one business field. `sort_order` is an integer from 0 to 2147483647. Space type is FRIDGE/FREEZER/PANTRY/WAREHOUSE/OTHER. `expected_version` is an integer from 1 to 2147483647; writes must not overflow. Return VERSION_LIMIT_REACHED at the limit.
- ItemDefinitionRead.category_id is the current category. Use category_name, storage_space_name, and item_definition_name consistently for associated names. Inventory responses omit owner_user_id. Display quantities are derived, not stored.
- Single creation, modification, and state actions return their Read model. Batches return an items array and count in input order. Preview returns 200, batch creation 201, batch move/archive 200, new quantity submission 201, and successful replay 200.
- Allow explicit all-state filtering. Archival of an associated space or definition alone must not hide inventory details or operation history.
- Calculate counts and items in one statement or from the same read snapshot. Two queries in an ordinary READ COMMITTED transaction do not guarantee that. Ordinary offset pagination guarantees stable sorting, not an unchanged dataset across requests.

### 3.4 Error responses

Use the business error format above with these stable codes: 422 for VALIDATION_ERROR, UNIT_NOT_CONVERTIBLE, INSUFFICIENT_QUANTITY, QUANTITY_TOO_SMALL, QUANTITY_PRECISION_UNSUPPORTED, and QUANTITY_OUT_OF_RANGE; 409 for VERSION_CONFLICT, VERSION_LIMIT_REACHED, STATE_CONFLICT, NAME_CONFLICT, IDEMPOTENCY_CONFLICT, and RESOURCE_CHANGED; 404 for NOT_FOUND; 403 for ADMIN_REQUIRED. Password-change errors retain authentication's existing detail-string style and the status codes in section 4.

Convert validation errors for new business requests to VALIDATION_ERROR, exposing field locations and explanations only, without raw input, request headers, or passwords. Preserve the existing auth validation format; do not globally alter existing authentication success/error structures.

### 3.5 Security requirements and verification

The course requires consulting at least OWASP Top Ten and addressing applicable risks. This phase uses [OWASP Top 10:2025](https://owasp.org/Top10/2025/0x00_2025-Introduction/) for the checklist below. Measures and evidence are planned work, not completed security acceptance. Record reasons for inapplicable details rather than skipping the entire check.

| Risk category | Project measures and evidence |
| --- | --- |
| Broken access control | Restrict resources through database ownership relationships and authenticate administrators separately. Test lists, details, writes, batches, and history with two users and an administrator; another user's ID must not expose records. |
| Security misconfiguration | HTTPS, explicit CORS origins/headers, least-privilege database access, and no production debug traces. Inspect deployment settings and test browser cross-origin requests. CORS is not authentication. |
| Software supply chain failures | Record deployed dependency versions, check vulnerabilities in CI, and review updates. Limit pipeline permissions and keep credentials out of the repository and logs. |
| Cryptographic failures | Retain password hashing and fixed JWT algorithm validation. Verify transport encryption and key configuration/protection. Do not log passwords, tokens, or database URLs. |
| Injection | Allowlist and type-check request fields and bind query parameters. Test abnormal input and special characters for query/error behavior. |
| Insecure design | Enforce quantity boundaries, idempotency, transactions, and batch limits. Plan login/registration rate limits and request-size limits at cloud ingress; record thresholds with capacity tests without changing normal business semantics. |
| Authentication failures | Test invalid, forged, and expired tokens, wrong passwords, inactive accounts, and administrator targets. Document the absence of immediate token revocation. |
| Software or data integrity failures | Compute critical fields on the server; do not trust client balances or roles. Commit quantity and operation together. Deploy reviewed, tested, traceable commits. |
| Security logging and alerting failures | Log request correlation identifiers, route templates, status codes, duration, and sanitized authentication/authorization error categories. Verify logs omit request bodies and credentials. Configure notification or checking mechanisms for persistent service errors and abnormal authentication failures. |
| Mishandling of exceptional conditions | Verify rollback and session release after database errors, concurrent conflicts, and mid-operation failures. Return stable business errors or generic service errors without SQL or stack traces. |

Operational logs and cloud alerts support fault/security investigation. They are not administrator business audit tables or user inventory reminders/push notifications and do not expand excluded product scope. If ingress rate limiting returns 429, document it in the implemented API reference. Verify settings before release instead of merely listing measures.

Configure CORS when Web and API origins differ, allowing the actual Web origins and required headers such as Authorization. Continue using Bearer tokens; CORS does not introduce cookie login. Native Flutter uses the same authentication, and browser cross-origin rules are not backend permission boundaries.

## 4. API contracts by feature

Paths in this section omit `/api/v1`, except `/health`. All new endpoints validate requests according to section 3; inventory writes also follow sections 5–7. Query endpoints do not write business tables, although protected queries still read the current user for authentication. Single creation, modification, and state actions return the corresponding Read model from section 3.2.

Each API work package includes validation, database behavior, related automated tests, documentation, and review. Select tests according to endpoint risk and use section 9.4 for completion criteria. Do not defer all tests until feature development is finished.

### 4.1 Health and authentication

B01–B03 implementation and verification are documented in the [API reference](API_REFERENCE.md) and [test results](testing/B01-B03_AUTH_TEST_RESULTS.md). Registration/login validation errors retain the 422/detail-list structure and expose only type, loc, and msg, without raw input. Automated results, manual Postman acceptance, remote CI, and team review are recorded separately.

| Existing endpoint | Database reads | Database writes or response |
| --- | --- | --- |
| `GET /health` | None in the current implementation | No writes; returns `status=ok` and `service=sayfridge-backend`. Does not prove database connectivity |
| `POST /auth/register` | Look up `user` by normalized email | Create a user with normalized email, password hash, auth_provider=LOCAL, role=USER, status=ACTIVE; commit and read the new user. Roll back uniqueness conflicts. Do not create spaces or inventory |
| `POST /auth/login` | Read user by email; verify password, LOCAL provider, and ACTIVE state | No user, inventory, or server-side session writes; issue an access token |
| `GET /auth/me` | Validate token, then read user by ID; reject missing/non-ACTIVE users. Read current database role and state | No business writes |

The existing registration/login contract accepts only email and password and rejects unknown fields. Email is trimmed and lowercased; password length is 8–128. Successful registration returns HTTP 201 with id, email, role, status, and created_at; duplicate email returns 409. Login returns access_token, token_type=bearer, expires_in, and user. Unknown accounts, wrong passwords, and unavailable accounts share a 401 response. `/auth/me` returns the same public user structure and rejects missing, invalid, or expired credentials with 401. These rules describe the current implementation and do not automatically apply to every new business endpoint.

#### 4.1.1 `POST /auth/change-password`

- **Request:** old_password, new_password.
- **State and validation:** current ACTIVE LOCAL account; authenticate the user, check the stored hash, and verify the old password.
- **Writes:** password_hash, updated_at.
- **History and retries:** no history; wrong old password 400, unchanged password 422, missing hash/non-local account 409. After a lost response, confirm by logging in again.

Both password fields require 8–128 characters and a valid Bearer token. Success returns `{"changed":true}`. The client clears its local login state and logs in again. The backend does not add token revocation; existing tokens remain valid until natural expiry, which defaults to 15 minutes.

### 4.2 Storage spaces

B04 is implemented in `app/api/routes/storage_spaces.py` and `app/services/storage_spaces.py`. See the [API manual](API_REFERENCE.md#3-storage-spaces--b04) and [B04 verification record](testing/B04_STORAGE_SPACES_TEST_RESULTS.md). No B04 schema migration is required.

| Endpoint | Reads and filters | Response and order |
| --- | --- | --- |
| `GET /storage-spaces`, `GET /storage-spaces/{id}` | Current user's storage_space | Lists default to ACTIVE with optional state filtering; details may include archived spaces. Sort by name, then id ascending |

#### 4.2.1 `POST /storage-spaces`

- **Request:** name, type.
- **State and validation:** current user ACTIVE; check user and active-name conflicts.
- **Writes:** user_id=current user, name/type, status=ACTIVE.
- **History and retries:** none; duplicate name 409; creation is not idempotent.

#### 4.2.2 `PATCH /storage-spaces/{id}`

- **Request:** at least one of name/type.
- **State and validation:** own ACTIVE space; check ownership and name uniqueness.
- **Writes:** name/type, updated_at.
- **History and retries:** none; duplicate name 409; return current state for an unchanged request.

#### 4.2.3 `POST /storage-spaces/{id}/archive`

- **Request:** none.
- **State and validation:** ACTIVE; return current state if already archived. Check ownership and look for IN_STOCK inventory after locking.
- **Writes:** status=ARCHIVED, updated_at.
- **History and retries:** none; return 409 if stock remains.

#### 4.2.4 `POST /storage-spaces/{id}/restore`

- **Request:** none.
- **State and validation:** ARCHIVED; return current state if already active. Check ownership and active-name conflicts.
- **Writes:** status=ACTIVE, updated_at.
- **History and retries:** none; duplicate name 409.

### 4.3 Categories and item definitions

B05–B06 are implemented in `app/api/routes/catalog.py` and `app/services/catalog.py`. Name normalization is shared through `app/core/catalog.py`; request/response models remain in `app/schemas/business.py`. See [API usage](API_REFERENCE.md#5-item-definitions--b06). No additional table, migration, public-catalog write endpoint, or shared-database seed is included.

All authenticated users can read public definitions. Only the owner can read and maintain private definitions. Ordinary users cannot edit public definitions.

| Endpoint | Reads and filters | Response and order |
| --- | --- | --- |
| GET /item-categories | item_category | Default ACTIVE; sort by sort_order, name, id ascending |
| `GET /item-definitions`, `GET /item-definitions/{id}` | Public or own item_definition, joined to category | Lists default to ACTIVE definitions with ACTIVE categories; filter by q, category_id, scope, status. Default scope ALL; stable name, scope, id ascending order (PRIVATE before PUBLIC for equal names). Details may show archived definitions visible to the user |

#### 4.3.1 `POST /item-definitions`

- **Request:** name, category_id.
- **State and validation:** category ACTIVE; validate category and uniqueness within the user's catalog.
- **Writes:** owner_user_id=current user, name, normalized_name, category_id, status=ACTIVE.
- **History and retries:** none; uniqueness conflict 409; not idempotent.

#### 4.3.2 `PATCH /item-definitions/{id}`

- **Request:** name/category_id.
- **State and validation:** own ACTIVE definition; check ownership and uniqueness. A submitted category_id must identify an ACTIVE category. A name-only edit may retain an archived current category because it creates no new association.
- **Writes:** corresponding fields, normalized_name, updated_at.
- **History and retries:** none; conflict 409; current associated display values change accordingly. Unchanged requests preserve updated_at and do not rewrite legacy normalization keys.

#### 4.3.3 `POST /item-definitions/{id}/archive`

- **Request:** none.
- **State and validation:** own definition; verify ownership.
- **Writes:** status=ARCHIVED, updated_at.
- **History and retries:** none; repeated requests return current state.

#### 4.3.4 `POST /item-definitions/{id}/restore`

- **Request:** none.
- **State and validation:** own definition and ACTIVE category; check both ownership and category.
- **Writes:** status=ACTIVE, updated_at.
- **History and retries:** none; archived category 409, including repeated restore of an already ACTIVE definition; valid repeated requests return current state.

### 4.4 Inventory and batch management

B07–B09 list/detail, stock creation, and metadata/location PATCH are implemented in
`app/api/routes/inventory.py`, `app/schemas/inventory.py`, and
`app/services/inventory.py`. The initial table definition includes nullable notes. Batch endpoints
remain planned; B13 inventory discard and archival are implemented. B10 ADD, B11 CONSUME, and B12
RECONCILE submission are implemented under section 4.6.2. See the
[API contract](API_REFERENCE.md#6-inventory--b07b09-and-b13). Shared Neon schema synchronization and manual
acceptance remain separate deployment steps.

Stock entry stores trimmed/casefolded units (1–16 characters before and after
normalization), with no inferred word aliases. Section 10.2 defines case-preserving
unit text for quantity operation records; stock entry itself writes no operation record.

| Endpoint | Reads and filters | Response and order |
| --- | --- | --- |
| `GET /inventory-items`, `GET /inventory-items/{id}` | inventory_item → storage_space.user_id, joined to the current catalog | Default IN_STOCK; filter by q, storage_space_id, category_id, status, purchase_from/to, expiry_from/to. Date boundaries are inclusive. Sort by expiry_date ascending NULLS LAST, then id ascending |

#### 4.4.1 POST /inventory-items: create inventory

1. **Request fields:** storage_space_id, item_definition_id, amount, and unit are required; purchase_date, expiry_date, and notes are optional. amount > 0; notes at most 1,000 characters. Planned model: `InventoryCreate`.
2. **Allowed state:** space ACTIVE; definition and category ACTIVE; definition public or privately owned by the user. Input cannot set status.
3. **Reads and validation:** current user, space ownership, definition visibility, category state, and quantity range. Expired stock may be entered. Do not enforce purchase_date ≤ expiry_date, allowing accurate recording of purchases made after expiry; validate only that dates are legal.
4. **Writes:** one inventory_item row; initial_amount=confirmed_current_amount=amount; initial_unit=confirmed_current_unit=unit; confirmed_at=server time; all three estimate fields NULL; status=IN_STOCK; version=1. Write associations, dates, and notes from the request.
5. **History:** no ADD record in the current plan; the history list may be empty. initial_* preserves initial facts but is not a complete stock-entry event.
6. **Failure and retries:** any validation failure creates no row. A lost success response cannot be reliably deduplicated automatically. Ask the client to check results; do not automatically retry while claiming it is safe.

#### 4.4.2 PATCH /inventory-items/{id}: metadata and location

1. **Request fields:** expected_version is required; at least one of storage_space_id, purchase_date, expiry_date, notes. Reject item_definition_id, quantities, status, initial quantities, and timestamps.
2. **Allowed state:** IN_STOCK and EMPTY can be edited; DISCARDED and ARCHIVED are read-only. EMPTY inventory in an archived space may move to an owned active space or have its dates/notes corrected.
3. **Reads and validation:** inventory ownership and version; a move requires an owned ACTIVE target space. Another user's space is not a valid target.
4. **Writes:** only allowed fields that actually change; increment version and update updated_at. Do not change quantities, confirmed_at, estimated_at, or initial_*. If all values are unchanged, return current state without incrementing version, but still validate expected_version.
5. **History:** no metadata or location change events in this phase.
6. **Failure and retries:** version mismatch 409. Retrying the old request may produce a version conflict; query again. Quantity-operation idempotency does not apply.

This phase provides no inventory definition correction. item_definition_id is immutable after creation. Renaming the definition itself still changes the current display name of all references.

#### 4.4.3 Disposal and archival

Endpoints: `POST /inventory-items/{id}/discard`, `POST /inventory-items/{id}/archive`.

Implementation status: discard and archive are implemented.

1. **Request fields:** expected_version; do not accept quantities or arbitrary status values.
2. **Allowed state:** discard only from IN_STOCK; archive from IN_STOCK or EMPTY. DISCARDED and ARCHIVED are terminal and read-only. Repeated actions return 409 without changing version.
3. **Reads and validation:** ownership, version, and source state.
4. **Writes:** only status=DISCARDED or ARCHIVED, version + 1, and updated_at. Preserve all quantities and quantity timestamps.
5. **History:** no inventory_operation record; do not disguise the action as CONSUME. updated_at cannot support a promise of complete disposal history.
6. **Failure and retries:** no changes on failure. After a lost response, query state. Retrying with the old version returns a conflict without repeating changes.

#### 4.4.4 Three batch endpoints

Endpoints: `POST /inventory-items/batch-create`, `POST /inventory-items/batch-move`, `POST /inventory-items/batch-archive`.

| Topic | batch-create | batch-move | batch-archive |
| --- | --- | --- | --- |
| Request | items: InventoryCreate[] | target_storage_space_id, items: [{id, expected_version}] | items: [{id, expected_version}] |
| State | Same as single creation | IN_STOCK or EMPTY; owned ACTIVE target space | Same as single archive |
| Validation | Every space, definition, and quantity | Every item's ownership/version and target space | Every item's ownership/version/state |
| Writes | Initialize multiple inventory rows | storage_space_id, version, updated_at | status, version, updated_at |
| History | No ADD | No move event | No archive event |
| Failure/retries | Roll back all on any failure; no creation idempotency guarantee | Roll back all on any failure; no response replay guarantee | Roll back all on any failure; no response replay guarantee |

Shared rules: items must contain 1–100 entries. Reject duplicate inventory IDs for move/archive. Do not deduplicate creation by content because identical input can represent separate real batches. Return results in input order, not lock order. Report the first determined error and zero-based item_index; missing and inaccessible resources both use NOT_FOUND. Keep validation order fixed to reduce inconsistent errors for identical input. Moving to the current space is a no-op, but still validate version and ACTIVE target state; do not increment version.

#### 4.4.5 Archive and recreate a wrongly entered item

Use the existing archive endpoint for the “delete and recreate” workflow: remove the old inventory from the default in-stock list, preserve it and its quantity operations, then create a correct new batch. Do not add physical DELETE, delete quantity history, create correction records, or add fields linking the old and new batches.

Archiving and creating the replacement are independent requests with no cross-request rollback guarantee. Archive first, then create. If creation fails, the old batch remains archived and the user can retry entering the new batch. The new batch has its own ID, initial quantity, and version and does not inherit old operations. Already archived/discarded records retain their state without another archive action.

### 4.5 Inventory and expiry summaries

| Endpoint | Reads and filters | Response and order |
| --- | --- | --- |
| GET /inventory-summary | Current user's IN_STOCK inventory | total_batches, by_space, by_category; include only groups with stock and never add quantities with different units |
| GET /expiry-summary | Current user's IN_STOCK inventory with non-null expiry_date | Required as_of; days_before defaults to 3, range 0–365; counts for three buckets and one paginated items list, with bucket on each item |

- Expiry response: counts (overdue/today/upcoming), items, total, page, page_size. total counts all details matching the bucket filter. Return 422 if adding days_before exceeds the legal date range.
- inventory-summary returns total_batches, by_space:[{storage_space_id,name,batch_count}], by_category:[{category_id,name,batch_count}]. Sort groups by name, then id.
- Both summaries support storage_space_id and category_id filters. Counts cover all filtered results, not just the page.
- Expiry items optionally filter by bucket=overdue/today/upcoming. Counts always include all three buckets under the space/category filters. Without bucket, paginate the combined three groups. Sort expiry_date, then id ascending.
- `expiry_date < as_of` is overdue; equality is today; `as_of < expiry_date ≤ as_of+days_before` is upcoming. When days_before=0, upcoming=0. Exclude unknown dates.

Expiry queries return database results only; they send no notifications, store no user timezone, and run no scheduled jobs.

### 4.6 Quantity preview, submission, and history

#### 4.6.1 POST /inventory-items/{id}/operation-preview: preview

1. **Request fields:** same as a quantity submission, including required expected_version; no idempotency key required.
2. **Allowed state:** same as the actual operation.
3. **Reads and validation:** current inventory, ownership, space state, version, quantities, and units.
4. **Writes:** none. Use the same calculation function as submission and return based_on_version and candidate values.
5. **History:** none.
6. **Failure and retries:** version conflict 409; reread and preview again. A successful preview reserves no stock. Submission must check and recalculate; preview is not mandatory before every submission.

#### 4.6.2 POST /inventory-items/{id}/operations: submit a quantity operation

Implementation status: B10 ADD/AMOUNT, B11 CONSUME with AMOUNT or FRACTION, and
B12 RECONCILE/AMOUNT are implemented. No table changes or new
migration scripts are needed. The preview endpoint remains planned pending the
response decision in section 10.1. See API_REFERENCE.md for the implemented contract.

1. **Request fields:** expected_version, operation_type, quantity_kind, quantity_value, quantity_unit; Idempotency-Key header required. Request model: `InventoryOperationCreate`.
2. **Allowed state:** see section 6. RECONCILE confirms the current total; do not treat it as an increment/decrement.
3. **Reads and validation:** identity/ownership → successful idempotency record → new-request version/state → units, precision, and nonnegative balance. Do not accept client after, affects_state, or calculation_method as authoritative write values.
4. **Writes:** update inventory and insert a SUCCESS operation together under section 5; increment version; commit once.
5. **History:** one successful operation. Failures do not create FAILED rows. Database support for FAILED does not require using it in this phase; existing history in other states remains queryable.
6. **Failure and retries:** replay a successful request with the same key and business parameters. Different parameters return 409; new-request version mismatch 409; calculation failure 422. Roll back both inventory and success record. See section 7 for exact ordering.

Detailed preview response fields remain open in section 10.1.

#### 4.6.3 History queries

Implementation status: the item-scoped history endpoint is implemented. The global
history list and operation-detail endpoints remain planned.

| Endpoint | Reads and filters | Response and order |
| --- | --- | --- |
| GET /inventory-items/{id}/operations | Validate inventory ownership, then read operations | created_at, id descending; empty list if none |
| `GET /inventory-operations`, `GET /inventory-operations/{id}` | operation → inventory → space → current user | List filters: inventory_item_id, operation_type, status, created_from/to. Time range includes the start and excludes the end. created_at, id descending |

- History defaults to all existing states; only new SUCCESS records are written. Frontends must not display FAILED/UNDONE as effective consumption. Display reconciliation as “Confirmed remaining quantity: X units,” not an invented delta.
- Quantity history does not promise complete before/after snapshots, historical names, estimate-basis snapshots, metadata changes, or disposal times.

### 4.7 Administration

Use existing administrator accounts; do not automatically promote ordinary users. If none exist, prepare one as a deployment task. This phase excludes administrator audit, role promotion, private inventory inspection, and changing another user's password.

| Endpoint | Reads and filters | Response and order |
| --- | --- | --- |
| `GET /admin/users`, `GET /admin/users/{id}` | user, with administrator permission | Expose id, email, role, status, created_at, updated_at. List filters q/role/status; created_at, id descending. No hashes or inventory |
| GET /admin/item-categories | All public categories | State filter, default all; sort_order, name, id ascending |
| GET /admin/item-definitions | owner_user_id IS NULL | Default all states; q/category_id/status filters; name, id ascending |

#### 4.7.1 `PATCH /admin/users/{id}/status`

- **Request:** status.
- **State and validation:** target role=USER; check current administrator and target account.
- **Writes:** status, updated_at.
- **History and retries:** no audit. Allow transitions among ACTIVE / SUSPENDED / DISABLED. Administrator target returns 403. Repeated requests return current state.

#### 4.7.2 `POST /admin/item-categories`

- **Request:** name; optional sort_order, default 0.
- **State and validation:** administrator; unique name.
- **Writes:** name, normalized_name, sort_order, status=ACTIVE.
- **History and retries:** no audit; conflict 409; not idempotent.

#### 4.7.3 `PATCH /admin/item-categories/{id}`

- **Request:** name/sort_order/status.
- **State and validation:** administrator; archived entries may be maintained; check uniqueness and enumerations.
- **Writes:** allowlisted request fields, updated_at.
- **History and retries:** no audit; conflict 409; no cascading definition changes.

#### 4.7.4 `POST /admin/item-definitions`

- **Request:** name, category_id.
- **State and validation:** administrator; category ACTIVE; validate category and public-name uniqueness.
- **Writes:** owner_user_id=NULL, name, normalized_name, category_id, status=ACTIVE.
- **History and retries:** no audit; conflict 409; not idempotent.

#### 4.7.5 `PATCH /admin/item-definitions/{id}`

- **Request:** name/category_id/status.
- **State and validation:** administrator; public definitions only. Check public ownership and name. Changing category or restoring requires an ACTIVE category.
- **Writes:** allowlisted fields, updated_at.
- **History and retries:** no audit; private targets uniformly return 404; conflict 409.

Administrator state changes affect subsequent authenticated requests because each request reads the user record. They do not promise to cancel requests already executing.

## 5. Quantity calculations and records

### 5.1 Request forms

| Operation | quantity_kind | quantity_value | quantity_unit |
| --- | --- | --- | --- |
| ADD / CONSUME explicit amount | AMOUNT | Positive decimal string | Required unit |
| CONSUME fraction of the current balance | FRACTION | `p/q`, positive integers with p ≤ q, total length ≤ 32 | Fixed to remaining |
| RECONCILE | AMOUNT | Nonnegative decimal string, including 0 | Newly confirmed unit, which may differ from the old unit |

Do not support fractional ADD, fractional reconciliation, QUALITATIVE, or AI_ESTIMATED input. Fractions are expressions and are not subject to the three-decimal input syntax, but calculated results still follow three-decimal storage precision. Preserve the valid literal input in quantity_value; do not rewrite `1/2` to `0.5`. Store the original valid quantity_unit and derive a separate normalized unit for calculation.

### 5.2 Inventory field updates and rounding

| Scenario | confirmed_current_* / confirmed_at | estimated_current_* / estimated_at | initial_* | status |
| --- | --- | --- | --- | --- |
| Stock creation | Initial amount/unit and current time | All NULL | Set first amount/unit | IN_STOCK |
| ADD / CONSUME without an estimate | Add/subtract the converted change from the confirmed quantity; update time | Keep NULL | Unchanged | Exact zero → EMPTY; otherwise IN_STOCK |
| ADD / CONSUME with an estimate | All unchanged | Add/subtract from the estimate; update estimate time | Unchanged | An estimate of zero remains IN_STOCK |
| RECONCILE | Set the submitted total, new unit, and current time | Clear all three fields together | Unchanged | Zero → EMPTY; positive → IN_STOCK |
| Dates, location, or notes | Unchanged | Unchanged | Unchanged | Unchanged |
| discard/archive | Unchanged | Unchanged | Unchanged | Set the corresponding terminal state |

Ordinary additions/subtractions use the current effective balance unit, supporting g↔kg and ml↔l. Reject other differing units. RECONCILE need not convert the new unit to the previous unit.

Input still has at most three decimal places. Round the applied change from conversions or fractions to three places in the effective unit, using ROUND_HALF_UP (half up for nonnegative values). Do not round every quantity to an integer. Calculate fractions using integer ratios to 0.001 unit precision rather than first truncating values such as 1/3. Use Decimal for unit conversion.

Execution order:

1. Calculate the unrounded change. If CONSUME already exceeds the balance, return INSUFFICIENT_QUANTITY; rounding must not conceal over-consumption.
2. Round the change to three decimal places, then add/subtract that change from the current balance to obtain the stored balance. Do not independently round the consumed amount and balance.
3. If a positive change rounds to zero, return QUANTITY_TOO_SMALL without a success record. If an unrounded positive remainder becomes zero after rounding, return QUANTITY_PRECISION_UNSUPPORTED. The user may explicitly consume all or perform a real reconciliation; do not automatically treat a tiny remainder as exhausted.
4. Original input, stored applied change, and final balance must all fit NUMERIC(12,3). Return QUANTITY_OUT_OF_RANGE for overflow instead of relying on database truncation.
5. Preview returns rounded, applied change, and final balance. Submission/replay use OperationResult: quantity_* stores original input, applied_change_* stores rounded results, and inventory returns current balance. Do not infer missing original bases or rounding flags in history/replay; add no database columns.
6. Rounding is a storage-precision rule, not an AI estimate. Without an estimate, update confirmed quantity; with an estimate, update estimated quantity. calculation_method continues to represent exact calculation or rule-based conversion; add no enumeration values.

Example: consuming 1/3 of 1 kg records 0.333 kg consumed and 0.667 kg remaining, with rounded=true. Consuming half of 0.001 kg is rejected because rounding would erase a positive remainder. Merely changing units is not a physical stocktake; do not require false confirmation of a remaining total to bypass precision validation.

### 5.3 Operation record fields

| Field | Server write rule |
| --- | --- |
| inventory_item_id | Current target inventory |
| operation_type | Validated ADD / CONSUME / RECONCILE |
| quantity_kind/value/unit | Preserve valid original quantity expressions; do not present converted values as original input |
| input_method | Fixed to MANUAL in this phase; clients cannot invent VOICE/PHOTO sources |
| calculation_method | EXACT for same-unit amounts, explicit fractions, and direct reconciliation; CONVERTED for deterministic unit conversion |
| affects_state | CONFIRMED for additions/subtractions without an estimate and for reconciliation; ESTIMATED for changes to an estimated balance |
| applied_change_amount/unit | Positive applied ADD/CONSUME amount and stored unit; both NULL for reconciliation, without invented cross-unit deltas |
| status | Fixed to SUCCESS on insertion |
| idempotency_key | Derived per user under section 7.3 |
| created_at/updated_at | Server/database time; undone_at=NULL |

Even if the RECONCILE total equals the existing confirmed total, record the physical stocktake and update confirmation time and version. This is a new confirmation fact, unlike an unchanged metadata PATCH.

### 5.4 Complete example

Inventory A has confirmed=10 each, estimated=NULL, version=4.

```json
{
  "expected_version": 4,
  "operation_type": "CONSUME",
  "quantity_kind": "AMOUNT",
  "quantity_value": "2",
  "quantity_unit": "each"
}
```

The client also supplies Idempotency-Key. In one transaction, update A to confirmed=8 each, confirmed_at=current time, version=5, and insert an operation with CONSUME, AMOUNT, original value 2 each, EXACT, CONFIRMED, applied change 2 each, SUCCESS. On failure, commit neither.

If A instead started at confirmed=10 each and estimated=7 each, the result is confirmed=10 each and estimated=5 each, with affects_state=ESTIMATED. Subtracting exactly 2 does not make an uncertain starting balance certain.

Operation units are stored after trimming, preserving case; their casefolded form is used for calculations. Section 10.2 records this decision.

## 6. State and relationship rules

| Inventory source state | Metadata PATCH / move | ADD | CONSUME | RECONCILE | discard | archive |
| --- | --- | --- | --- | --- | --- | --- |
| IN_STOCK | Allowed | Allowed | Allowed with sufficient effective balance | Allowed | Allowed | Allowed |
| EMPTY | Allowed | Allowed in an ACTIVE space; restores IN_STOCK | Rejected | Zero stays EMPTY; positive requires an ACTIVE space and restores IN_STOCK | Rejected | Allowed |
| DISCARDED | Rejected | Rejected | Rejected | Rejected | Rejected | Rejected |
| ARCHIVED | Rejected | Rejected | Rejected | Rejected | Rejected | Rejected |

Spaces are ACTIVE or ARCHIVED only. IN_STOCK inventory prevents space archival; EMPTY inventory does not. An archived space cannot receive newly created or moved stock. Before adding to or reconciling a positive total for its EMPTY inventory, move that inventory or restore the space. Repeated space archive/restore returns current state successfully. Edit space name/type only while ACTIVE. A conflicting active name on restoration returns 409.

Archiving catalog entries does not delete or freeze existing inventory. Creating inventory or establishing/changing definition associations requires ACTIVE definitions and categories. Existing inventory can still be consumed, reconciled, replenished, and moved; catalog deactivation must not block actual stock management. Restoring a definition requires an ACTIVE category. Archiving a category does not cascade definition state changes. Queries for selectable definitions filter both definition and category state. Archived private definitions can only be restored, not ordinarily edited.

Coordinate concurrent deactivation and new associations. Deactivation does not retroactively invalidate existing references. Ordinary users cannot change owner_user_id; spaces cannot change user_id; inventory cannot move across users.

## 7. Transactions, versions, and repeated requests

### 7.1 Transaction ownership

The outer service owns one commit for each write request and rolls back on failure. Routes do not commit again; internal validation and batch helpers do not commit. Authentication reads can already start a transaction on the same AsyncSession. Do not blindly wrap an existing transaction in `session.begin()`; reuse the request session and make transaction ownership explicit at the write entry point.

The session dependency only yields a session; exiting it does not commit business writes. Preserve the registration service's existing commit behavior and apply consistent transaction ownership to new business writes.

### 7.2 Concurrency protection

- First read target relationships without locks to plan the operation. Then lock relevant spaces, categories, definitions, and inventory in a consistent order, sorting UUIDs within each type. After obtaining locks, recheck ownership, relationships, state, and version.
- Space archival, stock creation, moves, and EMPTY restoration must coordinate on the same space row so stock cannot be added after archival passes its check. If the inventory moved after the planning read, do not continue with the old lock set; roll back and require refresh/retry.
- Compare expected_version after locking inventory, then update and increment. A version-conditional UPDATE is also possible, but cannot replace cross-table space-state protection.
- Catalog deactivation and new associations use the same lock order. Do not merely read ACTIVE and then insert without protection.
- Process batches in lock order and return results in input order. Failed transactions must leave no written sub-items.
- Preview holds no locks across requests. Lists/previews describe state at read time; actual writes recheck it.

After locking, fetch current database values instead of reusing ORM values cached during authentication or planning. Space ownership and catalog ownership are immutable. Lock order is space → category → definition → inventory, with IDs sorted within each type; lock only required records. Administrator changes to a single category/definition also respect relevant ordering. If batch relationships changed during the wait, roll back and return RESOURCE_CHANGED instead of acquiring reverse-order locks while already holding some locks.

This phase favors understandable serialization. Writes in the same space may wait for each other. Refine lock granularity only if performance requires it, with repeated consistency verification.

### 7.3 User-scoped idempotency

1. Header keys contain 1–64 visible ASCII characters, no whitespace, and are case-sensitive.
2. Derive the database key as `current-user-UUID:client-key`, at most 101 characters within the existing 128-character limit. Do not include inventory ID: otherwise reuse across different inventory items would not be detected as a conflict.
3. After identity and target-ownership checks, look up the key. For an existing successful record, compare inventory_item_id, operation_type, and quantity_kind/value/unit. Literal values `2` and `2.0` are different requests; retries preserve the original expression.
4. expected_version is excluded from business-parameter comparison. Successful replay precedes version/terminal-state checks, so a completed request can return its original operation and current inventory even if inventory later changed or was archived. Replay is forbidden if access has since been lost.
5. Only when no record exists, validate new-request state, version, and quantity. Recheck the key after lock waits so a completed equivalent request is not rejected solely because the submitted version is old.
6. Inventory changes and operation insertion share a transaction. The unique constraint is the final safeguard. If the error is confirmed to be that key's uniqueness conflict, roll back fully, then start a read to compare the committed record. Do not treat every IntegrityError as a replay.
7. An existing non-SUCCESS record with the key produces an explicit conflict; do not automatically reapply historical state. This phase records no failed requests, so a key may be retried before any success.
8. No automatic expiry/deletion period is defined; keys remain with operation records. Any future history cleanup must reconsider the idempotency-retention promise.

Spaces, catalog entries, and users have no version. After validation, update only submitted fields; the last write wins. This does not prevent stale edits overwriting metadata. Inventory versioning does not imply system-wide version protection.

### 7.4 Concurrency and failure verification

Verify quantities, versions, locks, and rollback with isolated PostgreSQL, not only simulated sessions. Concurrent requests use independent sessions and controlled entry into critical steps. Inspect database quantities, versions, and operations, not just HTTP responses.

Only one of two different modifications with the same version may succeed; concurrent identical idempotent requests apply once. Space archival racing against stock creation, moves, or EMPTY restoration must not leave invalid state. Verify whole-transaction rollback for mid-batch failure and failure between quantity update and operation insertion. Deliver these tests with the relevant APIs and rerun them after performance tuning or adding instances.

## 8. File responsibilities and database structure

### 8.1 File list

Paths below are relative to `backend/` unless explicitly identified as repository-root documentation paths. The table records feature responsibilities rather than a fixed file count. B04 uses its own service module, following the same route/service separation as authentication. Additional tests, CI, and deployment configuration are not constrained by the original file count. Record actual paths when those approaches are selected; do not pre-create empty directories.

| Change | File | Responsibility | Tables read/written |
| --- | --- | --- | --- |
| Add | `app/api/routes/storage_spaces.py` | Space GET/POST/PATCH and archive/restore | storage_space; check inventory_item |
| Add | `app/api/routes/catalog.py` | Category GET, private item maintenance, visible-definition queries | item_category, item_definition |
| Add | `app/api/routes/inventory.py` | Inventory queries, creation, PATCH, discard/archive, three batch actions, summaries, expiry | inventory_item and related tables |
| Add | `app/api/routes/inventory_operations.py` | Preview, operations POST, three history GET endpoints | inventory_item, inventory_operation |
| Add | `app/api/routes/admin.py` | User state, public category, and public definition management | user, item_category, item_definition |
| Add | `app/schemas/business.py` | Request/response models from sections 3–4, grouped by feature | No database access |
| Add (B04 implemented) | `app/services/storage_spaces.py` | Space queries, ownership, names, state changes, and transactions | storage_space; read inventory_item for archival |
| Add (B05–B06 implemented) | `app/services/catalog.py` | Category/definition queries, writes, states, names | item_category, item_definition |
| Add | `app/services/inventory.py` | Pure quantity calculations, inventory writes, versions, idempotency, batch transactions | inventory_item, inventory_operation; lock/check related spaces/catalog |
| Update | `migrations/versions/create_initial_tables.py` | Include nullable TEXT notes in the latest initial table definition | Fresh database initialization |
| Add | Repository-root `docs/API_REFERENCE.md` | Implemented frontend contracts, examples, and verification status | No database access |
| Modify | `app/main.py` | Register five route groups, CORS, and new business error handling | No direct business writes |
| Modify | `app/api/dependencies.py` | require_admin, reusing current-user lookup | user |
| Modify | `app/api/routes/auth.py`, `app/schemas/auth.py`, `app/services/auth.py` | Password-change request, validation, and update | user.password_hash |
| Modify | `app/db/models.py` | Add InventoryItem.notes only | inventory_item |
| Modify | `app/core/config.py`, `.env.example` | Configurable CORS origins; no real secrets in examples | None |
| Modify | `README.md` | Backend README, not repository-root README | None |

Additional file responsibilities do not add product APIs or tables:

| Location | Work |
| --- | --- |
| `backend/tests/` | Reuse authentication tests and add business-rule, API, PostgreSQL integration, and concurrency tests. Use a repeatable team-selected tool/script for performance tests |
| `.github/workflows/` | Backend checks, isolated database tests, and dependency checks in the course repository; trigger on PRs or agreed events |
| Actual deployment configuration path | Record once hosting is selected; include startup, environment variable names, HTTPS, connection budgets, and logs, without real secrets |
| `backend/README.md` | Update local startup, testing, development database setup and initialization instructions; link this handbook |

### 8.2 Code organization

- Register routes directly in the existing main.py; do not add an aggregate router file.
- Simple read-only queries may live in routes. Put calculations, transactions, and shared rules in services.
- Do not add a Repository layer, generic CRUD framework, background jobs, or documentation-generation scripts.
- Do not mechanically create a request/response pair for every endpoint. Share response models between details/lists and create no request model for bodyless endpoints.
- Group business.py into spaces, catalog, inventory, operations, and administration, with clearly named models.
- File count is not a hard target. Explain any necessary changes to this list rather than silently expanding scope.

Use service functions with business meaning, such as create_inventory_item, move_inventory_items, apply_inventory_operation, and calculate_inventory_operation. Calculation functions do not commit. Batch internals reuse write helpers, not single-item entry points that commit each item. Small handlers in admin.py validate administrator state-update targets and commit once; do not add a generic service for this alone.

Register static paths such as /batch-create, /batch-move, and /batch-archive before /{id} to avoid interpreting them as UUIDs. Map only recognized unique-constraint errors to business conflicts. Roll back other database errors and return a generic service error without SQL or connection parameters.

Do not add a public bootstrap API. CORS_ORIGINS is a string list, default []. Allow GET/POST/PATCH/OPTIONS and Authorization/Content-Type/Idempotency-Key headers. Use Bearer tokens without cookie credentials and do not allow all origins by default.

### 8.3 API descriptions and comments

Use English for all documentation, comments, docstrings, and output messages, in accordance with the project requirement. This replaces the earlier bilingual instruction.

Each endpoint must have:

1. An English summary displayed in Swagger.
2. A short English function description explaining purpose and important limits.
3. Necessary English business comments, such as why ordinary consumption must not overwrite an estimated balance with a confirmed value.

```python
@router.post(
    "/{item_id}/operation-preview",
    summary="Preview inventory change",
)
async def preview_operation(...):
    """Calculate the resulting quantity without changing inventory or history."""
```

### 8.4 Notes field

| Topic | Plan |
| --- | --- |
| Table/field | inventory_item.notes |
| Type | TEXT, nullable=True, no default text |
| Purpose | Persist inventory notes for this phase |
| Existing records | Remain NULL; do not change quantities, versions, or history |
| API limits | At most 1,000 characters; explicit null in PATCH clears it |
| Affected APIs | Single/batch creation and inventory PATCH write it; lists, details, and other InventoryItemRead responses return it |
| ORM | Add only the notes mapping to InventoryItem |
| Development approach | Update the initial table definition and ORM; do not add an incremental notes migration |
| Timing | Synchronize the development database structure before using notes-dependent APIs |

Before the first backend release, maintain the latest database definition, ORM,
and API documentation together. Record table/column changes here, without a
versioned migration or rollback workflow. Existing Alembic infrastructure is used
only to initialize fresh development/test schemas. Updating the initial script
will not change databases that already ran it; synchronize those explicitly.
This document does not authorize deletion or rebuilding of shared data.

Current change: add nullable TEXT `inventory_item.notes`; existing rows have NULL
notes. Add no tables and change no inventory_operation fields or constraints.
The initial schema file is editable in this pre-release phase. Migration lifecycle
planning is deferred until the backend is released.

## 9. Implementation order and acceptance

### 9.1 Implementation order

Testing begins in the first stage and grows with each endpoint. CI, deployment preparation, and frontend contract agreement run alongside feature development.

| Order | Work | Completion condition |
| --- | --- | --- |
| 1 | Test foundations, request models, notes field | Existing authentication tests are repeatable; isolated PostgreSQL works; notes storage verified in a fresh schema; CI foundations established |
| 2 | Spaces and catalog | Ownership, names, states, archival/restoration implemented; related API and database tests pass |
| 3 | Inventory and quantities | Calculations, versions, idempotency, batches, and queries implemented; rollback/concurrency verified with endpoints; performance baseline begins |
| 4 | Administration and password change | Permissions, account states, and password behavior implemented; success/rejection tests pass |
| 5 | Frontend integration and security checks | Documentation matches implementation; key Web/Android/iOS flows have verification records; applicable risks addressed or explicitly outstanding |
| 6 | Cloud deployment and overall verification | Reproducible database setup, startup, initialization, HTTPS, and CORS settings; deployed version passes smoke/performance checks with retained results |

The project owner supplies section 10 decisions. Work independent of undecided fields may proceed, but an unresolved contract cannot be marked complete.

### 9.2 API documentation delivery

This handbook owns design rules. `docs/API_REFERENCE.md` documents implemented requests, responses, and usage examples; do not duplicate design decisions or open-question lists there. Update this handbook when design changes.

The API reference must describe purpose and permissions in English, request/response fields, defaults, enumerations, and error codes. Include examples for login, space creation, item selection, stock entry, preview, consumption, reconciliation, and history. Explain version conflicts, retries, and expiry dates. Link to the backend README for startup/database setup, the Postman guide for client setup, and the test index for actual verification status. Follow the file responsibilities in section 8.

Use FastAPI's built-in /docs, /redoc, and /openapi.json; add no documentation-export script.

### 9.3 Continuous testing and CI

Formal development permits and requires relevant tests, isolated test database creation, and current-schema initialization. Do not run destructive tests on real user data or shared deployment databases. Run relevant checks per change and agreed backend checks before merging. Do not mechanically add tests for documentation or low-risk changes.

| Test level | Content and timing |
| --- | --- |
| Unit tests | Quantity calculations, units/precision, state decisions, passwords, tokens; alongside rule implementation |
| API tests | Requests/responses, authentication, validation errors, pagination, denied access; alongside endpoints |
| PostgreSQL integration and concurrency | Real constraints, schema initialization, transaction rollback, version races, idempotency; alongside database writes, not replaced by fake objects |
| Frontend/device integration | Collaborate on login, stock entry, consumption, reconciliation, history, expired tokens, and errors. Flutter uses Android/iOS devices or simulators and records environments |
| Performance | Section 2.4 data/load/targets for queries, quantity writes, and hotspots; start once key flows work and repeat after optimization |
| Deployment verification | Check service, database reads, protected endpoints, and complete business flows after deployment. A passing /health does not prove database/business health |

Run backend CI in the course GitHub repository. PR checks include tests, necessary import/OpenAPI checks, and dependency checks. Database tests use isolated services and dedicated credentials. Performance testing is repeatable manual or scheduled work, not required in full for every small change. Record commands, code version, and results, and fix failures before completion.

All implemented work packages share one set of test definitions. Local pytest defaults to the full suite; automatic PR/main CI selects high-priority cases using the ci marker, and manual workflow dispatch runs the full suite. Counts are maintained in the test index rather than the design specification. See the [CI selection policy](testing/README.md#ci-selection-policy). Local tests use the isolated database configured in `.env.test`; CI sets TEST_DATABASE_URL for a disposable PostgreSQL service and does not access Neon. Missing test database configuration fails database tests rather than silently skipping them. See [B01–B03 test results](testing/B01-B03_AUTH_TEST_RESULTS.md) for evidence and limits.

Key business checks:

1. Prevent cross-user access to inventory, private definitions, move targets, and history.
2. Ordinary changes, calculations on estimates, reconciliation with unit changes, and clearing estimates follow the field matrix.
3. Only one of two concurrent writes with the same version succeeds; identical concurrent idempotent requests apply at most once.
4. Successful requests replay despite an old version; the same key with different inventory/parameters conflicts; failures leave no partial quantities or success records.
5. Space archival racing with creation/moves/EMPTY restoration never leaves IN_STOCK inventory in an archived space.
6. If batch item N fails, items 1 through N-1 are not persisted; duplicate IDs are rejected.
7. Rounding 1/3, tiny-fraction rejection, unit conversion, maximum values, and out-of-range results follow section 5.2; preview and submission agree.
8. Archived catalog names stay reserved; state transitions, history visibility, and the three expiry buckets are correct.
9. The notes change adds only its intended column. Verify current table structure and API output.

### 9.4 Completion criteria for each API task

Each work package centers on an API and includes implementation, tests, and documentation. Mark it complete only when applicable criteria are satisfied:

- Requests, responses, permissions, and state checks match this handbook; the normal flow works.
- Written fields, side effects, and errors match the contract; verify no partial persistence for multi-step failures.
- Key success, rejection, and boundary tests pass. Version/idempotency/lock changes have passing PostgreSQL concurrency tests.
- API documentation matches implementation and is usable by frontend developers; necessary human decisions are resolved.
- Team review is complete, the Issue links code changes and results, and remaining limitations are recorded.

Completing an API does not complete the project. Cloud deployment, device flows, and overall performance are accepted separately below. Explicitly report failed or unrun tests; syntax checks or an accessible Swagger page do not replace behavioral verification.

### 9.5 Cross-API tasks and deployment delivery

Add the following tasks to the existing GitHub Project and link dependencies to API work packages. This section defines task content only; it does not change GitHub identifiers or status.

| Task | Delivery and acceptance |
| --- | --- |
| Backend architecture and capacity | Confirm frontend scenarios, deployment structure, REST rationale, and initial load; record measurements, bottlenecks, and scaling options |
| Security review | Check section 3.5 measures and record applicability, evidence, outstanding work, and reasons for exclusions |
| Deployment and overall verification | Select hosting and database initialization; complete cloud deployment, frontend/device flows, and performance verification |

For the course deployment, identify the target environment, regions, connection
budget, actual CORS origins, secret configuration, and application version. Ensure
the database matches the current table definition. Initialize administrators and
public categories explicitly; do not promote accounts while serving requests.
Record service URL, commit, and smoke results without credentials or private data.
Pre-release work does not require incremental migration or rollback planning.


### 9.6 Team collaboration and change records

Use the course GitHub repository and Project board for tasks, assignments, and progress. Link each API task to test/review records; identify owners, collaborators, and dependencies for cross-API tasks. Hold at least one full-team meeting weekly, with minutes in the course GitHub Wiki or Project. Members should explain designs and code to one another to prepare for individual interviews about the whole system.

The former blanket instruction against all commits/pushes no longer defines formal development. Use team branches and PRs to retain version-control evidence. This handbook does not authorize automatic commits/pushes during a documentation edit. Preserve scope documents and others' changes; do not modify real .env files, images, or unrelated code. Explain necessary changes to other design documents and synchronize affected rules. Completion reports identify actual changed paths, verification, and limits.

## 10. Questions for the project owner

The consolidation retains these three questions. After the owner decides, update the corresponding rules in the main text rather than leaving answers here while the body remains ambiguous.

### 10.1 Complete quantity-preview response structure

Agreed: return inventory ID, the calculation's base version, before/after state, applied change, calculation method, affects_state, and rounded.

Open: exact nested fields, types, and nullability for before/after, plus final JSON names for applied change and calculation method. See sections 3.2 and 4.6.1.

**Owner's decision:** Pending.

### 10.2 Original units and length validation

**Owner's decision (2026-09-15):** Trim leading/trailing whitespace before storing
quantity_unit; preserve the remaining literal case. The trimmed string must be
1–16 characters. Validate that its casefolded form also fits the 16-character
limit used by calculation units. Do not store or compare surrounding whitespace
for idempotency. For example, " kg " and "kg" match, while "KG" and "kg" remain
different stored business inputs even though their units are convertible.

### 10.3 Initial-history requirement in older work packages

Verified: the [older work package document](SAYFRIDGE_WORK_PACKAGES_ZH.md) exists and requires an initial operation record for new stock batches. The database implementation draft's statement that the file did not exist was inaccurate and is not a premise of this handbook.

The current implementation plan creates no ADD for initial stock entry. This consolidation preserves that rule and its difference from the old work package. The owner must decide how to annotate the phase-specific exception in the old work package and which older design explanations need updating. See sections 1.3, 4.4.1, and the mapping below.

**Owner's decision:** Pending.

## 11. GitHub work package mapping

This table connects project tasks to design sections. It creates no additional design identifiers and changes no GitHub tasks or older work packages. Use section 4 paths; paths in older work packages were preliminary suggestions.

| Original work package | Handbook section | Scope in this phase |
| --- | --- | --- |
| B01, B02 | 4.1 | Registration and login; retain existing implementation |
| B03 | 4.1 | Current user; profile editing excluded |
| B04 | 4.2 | Storage spaces |
| B05, B06 | 4.3 | Category queries and item definitions |
| B07 | 4.4 | Inventory lists and details |
| B08 | 4.4.1, 10.3 | Stock creation; reconcile documentation differences on initial history |
| B09 | 4.4.2 | Inventory metadata maintenance |
| B10, B11, B12 | 4.6, 5 | Submit ADD / CONSUME / RECONCILE through operations; do not add the three earlier separate action paths |
| B13 | 4.4.3, 6 | Disposal, archival, and state |
| B14 | 4.6.3 | Quantity operation history |
| B15 | 4.4.4 | Batch creation, moves, archival; no other batch editing promised |
| B16–B21 | 1.2 | Agent, conversations, media, voice, quotas; later scope |
| B22 | 4.5 | Expiry summary; actual path /expiry-summary |
| B23, B24, B28 | 1.2 | Reminders and push excluded |
| B25 | 4.7 | Administrator account management |
| B26, B27 | 1.2 | Administrator jobs/audit excluded |

Password change, inventory summary, and administrator public-catalog maintenance follow section 4. Do not invent new work package IDs for them; resolve ownership during later task allocation.
