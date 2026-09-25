# SayFridge Database Design

> Status: Approved; first-phase database foundations implemented
>
> Database: Neon PostgreSQL
>
> Scope: Individual users, public and private item catalogs, inventory state, operation history, and conversation history

## 1. Overall Structure

The current design consists of eight tables:

~~~text
item_category
└── item_definition
    ├── owner_user_id = NULL       Public item definition
    └── owner_user_id = user.id    User-owned private item definition

user
├── storage_space
│   └── inventory_item
│       ├── item_definition_id → item_definition
│       └── inventory_operation
│
└── conversation
    └── conversation_message
~~~

- A user may own multiple independent storage spaces. Nested spaces and households are not modeled.
- `item_category` is the public category catalog, with entries such as vegetables, dairy products, meat, and household supplies.
- `item_definition` is the item catalog, with entries such as tomatoes, cucumbers, and bananas. An item definition does not represent a barcode, SKU, or specific inventory batch.
- An `item_definition` is public when `owner_user_id` is NULL. When a user ID is present, only that user may view and maintain the private definition.
- `inventory_item` represents a specific inventory batch in a user's storage space. Its name and category are obtained through `item_definition` rather than duplicated in the inventory table.
- `inventory_operation` represents an operation on a single inventory item, initiated through AI or a manual action. It is not a general accounting ledger, and there is no parent operation table organized by receipt.
- When a photo or receipt yields N recognized items, create N independent `inventory_operation` records.
- Conversation history and inventory operation history are not linked by foreign keys.

## 2. User Table: `user`

| Field | Description |
| --- | --- |
| id | User primary key |
| email | Unique email address used for login |
| password_hash | Password hash for local authentication; plaintext passwords must never be stored |
| auth_provider | Authentication provider, such as LOCAL or a third-party identity provider |
| role | User role, such as USER or ADMIN |
| status | Account status, such as ACTIVE, SUSPENDED, or DISABLED |
| voice_limit_seconds | Voice usage allowance, in seconds, for the current quota period |
| voice_used_seconds | Voice usage consumed, in seconds, during the current quota period |
| voice_quota_reset_at | Next scheduled reset time for the voice quota |
| created_at | User creation timestamp |
| updated_at | Last user update timestamp |

## 3. Storage Space Table: `storage_space`

| Field | Description |
| --- | --- |
| id | Storage space primary key |
| user_id | Owning user; foreign key referencing user.id |
| name | User-defined name, such as Kitchen Fridge or Garage Freezer |
| type | Space type, such as FRIDGE, FREEZER, PANTRY, WAREHOUSE, or OTHER |
| status | Space status, such as ACTIVE or ARCHIVED |
| created_at | Space creation timestamp |
| updated_at | Last space update timestamp |

Key constraints and indexes:

- All inventory queries and writes verify ownership against the authenticated user through `storage_space.user_id`.
- Create an index on `(user_id, status)`. Active space names should be unique within each user's spaces.
- Archiving a space must not leave in-stock items without an owning space.

## 4. Public Category Catalog Table: `item_category`

Each row represents a public category available for filtering. Initial seed categories may include vegetables, fruit, meat, dairy products, staple foods, household supplies, and other items.

| Field | Description |
| --- | --- |
| id | Category primary key |
| name | Display name, such as Vegetables |
| normalized_name | Normalized name used for searching and deduplication |
| status | ACTIVE or ARCHIVED |
| sort_order | Display order in the frontend |
| created_at | Creation timestamp |
| updated_at | Last update timestamp |

- Categories are not privately owned by ordinary users. Public categories are initialized by the system or maintained by administrators.
- Categories referenced by item definitions must not be physically deleted; set their status to ARCHIVED instead.

## 5. Item Definition Catalog Table: `item_definition`

Each row represents an item name and its associated category.

| Field | Description |
| --- | --- |
| id | Item definition primary key |
| name | Display name, such as Tomatoes, Cucumbers, or Bananas |
| normalized_name | Normalized name used for searching and deduplication |
| category_id | Associated category; foreign key referencing item_category.id |
| owner_user_id | Nullable; NULL indicates a public definition, while a user ID indicates that user's private definition |
| status | ACTIVE or ARCHIVED |
| created_at | Creation timestamp |
| updated_at | Last update timestamp |

Visibility rule:

~~~text
owner_user_id IS NULL
OR owner_user_id = authenticated_user_id
~~~

Two partial unique indexes are recommended:

- Public definitions: `normalized_name` is unique where `owner_user_id IS NULL`.
- Private definitions: `(owner_user_id, normalized_name)` is unique where `owner_user_id IS NOT NULL`.

## 6. Inventory Item Table: `inventory_item`

Each row represents a specific inventory item or batch. The same item may have multiple rows when purchase dates, expiry dates, or storage spaces differ.

| Field | Description |
| --- | --- |
| id | Inventory item primary key |
| storage_space_id | Owning storage space; foreign key referencing storage_space.id |
| item_definition_id | Item definition; foreign key referencing item_definition.id |
| purchase_date | Purchase date; nullable |
| expiry_date | Expiry date; nullable. The AI model must not infer an unverified date on its own |
| status | IN_STOCK, EMPTY, DISCARDED, or ARCHIVED |
| initial_amount | Quantity initially added to inventory; ordinary operations do not change it after creation |
| initial_unit | Unit of the initial quantity |
| confirmed_current_amount | Most recent current inventory quantity that the user could confirm |
| confirmed_current_unit | Unit of the confirmed current quantity |
| confirmed_at | Last update timestamp for the confirmed current quantity |
| estimated_current_amount | Current valid estimated inventory quantity; NULL when no valid estimate exists |
| estimated_current_unit | Unit of the current valid estimate; NULL when no valid estimate exists |
| estimated_at | Timestamp when the current estimate was last generated or updated; NULL when no valid estimate exists |
| version | Optimistic locking version; incremented for each committed update |
| created_at | Inventory record creation timestamp |
| updated_at | Last inventory record update timestamp |

Quantity state rules:

~~~text
initial_*
= Immutable historical facts about the initial stock entry

confirmed_current_*
= The most recent actual inventory baseline confirmed by the user

estimated_current_*
= The current result after the confirmed baseline, incorporating uncertain conversions or AI estimates
~~~

- On inventory creation, `confirmed_current_*` equals `initial_*`; `estimated_current_*` and `estimated_at` are all NULL.
- `estimated_current_amount` and `estimated_current_unit` must either both be NULL or both have values. `estimated_at` must be NULL or populated together with them.
- All quantities use `NUMERIC(12,3)`, never floating-point types. Stored quantities must be nonnegative.
- Display `estimated_current_*` when it is non-NULL, labeled "Approximately / AI estimate". Otherwise, display `confirmed_current_*`.
- Automatically change `status` to EMPTY only when the inventory quantity is confirmed to be zero. An estimate of zero may produce a "Possibly used up" indication but must not automatically hide the inventory item.

Ownership relationship:

~~~text
inventory_item.storage_space_id
→ storage_space.user_id
→ Authenticated user
~~~

## 7. Inventory Operation Table: `inventory_operation`

Each row represents a committed addition, consumption, estimate, or reconfirmation for one `inventory_item`. Neither the Agent nor the frontend may bypass this record and modify inventory directly.

| Field | Description |
| --- | --- |
| id | Operation primary key |
| inventory_item_id | Target inventory item; foreign key referencing inventory_item.id |
| operation_type | ADD, CONSUME, or RECONCILE |
| affects_state | CONFIRMED or ESTIMATED; identifies which current quantity state the operation changes |
| input_method | TEXT, VOICE, PHOTO, RECEIPT, or MANUAL |
| quantity_kind | Type of quantity expression provided by the user: AMOUNT, FRACTION, or QUALITATIVE |
| quantity_value | Original user-provided value, such as 2, 1/2, some, or 18.5 after a stock count |
| quantity_unit | Original user-provided unit, such as kg, g, each, cup, or remaining; nullable for qualitative expressions |
| calculation_method | EXACT, CONVERTED, or AI_ESTIMATED |
| applied_change_amount | Quantity change applied by ADD or CONSUME; nullable for RECONCILE |
| applied_change_unit | Unit of applied_change_amount; nullable for RECONCILE |
| status | PENDING_CONFIRMATION, SUCCESS, FAILED, or UNDONE |
| idempotency_key | Idempotency key that prevents retries from creating duplicate operations |
| created_at | Operation creation timestamp |
| updated_at | Last operation update timestamp |
| undone_at | Undo timestamp; NULL if the operation has not been undone |

Semantic rules:

- `quantity_value` and `quantity_unit` preserve the user's original expression and must not be overwritten with standardized units.
- EXACT and CONVERTED indicate calculations that the backend can determine without AI. AI_ESTIMATED requires an AI-proposed value and user confirmation.
- When no valid estimate exists, a deterministic ADD or CONSUME operation updates the CONFIRMED state.
- When a valid estimate exists, subsequent additions and consumption use that estimate as their baseline and update the ESTIMATED state. A deterministic change in the current operation must not discard uncertainty inherited from earlier estimates.
- RECONCILE represents the user reweighing, counting stock, or explicitly stating "X remains now". It updates `confirmed_current_*` and clears `estimated_current_*` and `estimated_at` in the same transaction.
- Only SUCCESS operations affect inventory. PENDING_CONFIRMATION, FAILED, and UNDONE operations do not affect the current state.
- Ordinary ADD and CONSUME operations may be undone using their confirmed changes. An incorrect RECONCILE entry is corrected with a new RECONCILE operation; it does not restore the previous chain of estimates.

## 8. Conversation Table: `conversation`

| Field | Description |
| --- | --- |
| id | Conversation primary key |
| user_id | Owning user; foreign key referencing user.id |
| title | Conversation title |
| created_at | Creation timestamp |
| updated_at | Timestamp of the latest message or conversation metadata update |

Create an index on `(user_id, updated_at DESC)` to list recent conversations.

## 9. Conversation Message Table: `conversation_message`

| Field | Description |
| --- | --- |
| id | Message primary key |
| conversation_id | Owning conversation; foreign key referencing conversation.id |
| role | USER or ASSISTANT |
| content | User message, transcription, or response intended for the user; must not store the model's hidden reasoning |
| created_at | Message creation timestamp |

- Order messages deterministically by `(conversation_id, created_at, id)`.
- Do not store system prompts, hidden reasoning, API keys, or access tokens.
- Conversation records are not a source of inventory facts or inventory audit evidence.

## 10. Quantity State and Display Example

~~~text
Purchase 20 kg of tomatoes
→ confirmed = 20 kg
→ estimated = NULL
→ Display: 20 kg (confirmed)

The user says, "I used half"
→ Deterministic consumption of 10 kg
→ confirmed = 10 kg
→ estimated = NULL
→ Display: 10 kg (confirmed)

The user says, "I used two more"
→ Two individual items cannot be directly converted to kg
→ Estimated consumption of approximately 0.3 kg, confirmed by the user
→ confirmed = 10 kg
→ estimated = 9.7 kg
→ Display: Approximately 9.7 kg (AI estimate)

The user reweighs the stock: "There is 9.5 kg left now"
→ confirmed = 9.5 kg
→ estimated = NULL
→ Display: 9.5 kg (confirmed)
~~~

## 11. Validated Write Workflow

~~~text
User input
→ The Agent extracts the original quantity expression and proposes an operation
→ The backend calculates using the confirmed quantity or valid estimate as the appropriate baseline
→ For an AI_ESTIMATED proposal, show the user the original expression and proposed result
→ User confirmation
→ FastAPI validates identity, visibility, units, quantities, state, version, and the idempotency key
→ A PostgreSQL transaction updates inventory_item and inserts inventory_operation
~~~

Transactions must guarantee that:

- Users can operate only on inventory in their own `storage_space` and can select only public or personally owned `item_definition` entries.
- Without an estimate, deterministic operations update the confirmed state. With an estimate, subsequent additions and consumption update the estimated state.
- RECONCILE atomically updates the confirmed state and clears the estimated state.
- CONSUME cannot reduce the quantity in the affected state below zero.
- The inventory update and SUCCESS operation record are committed together or rolled back together.
- The `idempotency_key` prevents the same validated request from being executed twice.

## 12. Implementation Status

This document is the original database design baseline. Current business API behavior is documented in BACKEND_DESIGN.md; the Agent extension is documented in AGENT_API.md. Local ORM and initial-schema changes do not prove that an existing deployment has been synchronized. Flutter, Web, and the Agent must not bypass backend business services to write inventory.

## 13. Agent business receipts: `agent_inventory_action`

The Agent extension adds a ninth business table. Each row is a committed, independently
replayable action, saved in the same transaction as its inventory changes and any
new private item definition or storage space. Failures and unconfirmed proposals
remain in the LangGraph checkpoint, not successful business history.

| Field | Meaning |
| --- | --- |
| id | Server-generated proposal/action UUID; primary key and retry identity |
| user_id | Owning user foreign key |
| conversation_id / turn_id | Logical LangGraph conversation and original request UUIDs; no conversation-table foreign key |
| action | CREATE_STOCK, ADD, CONSUME or RECONCILE |
| request_fingerprint | SHA-256 of the immutable prepared request |
| request_snapshot | JSONB original expression, resolved target, preview, estimate source and memory snapshots |
| result_snapshot | JSONB actual committed outcome and created inventory/operation identifiers |
| created_at | Committed action creation timestamp |

Existing quantity fields retain their semantics. Agent quantity operations use
input_method=TEXT and retain original expressions in inventory_operation. Initial
stock entry still does not fabricate an ADD operation. This receipt provides
creation provenance and crash recovery without depending on chat history.

For existing databases, `backend/scripts/setup_agent_actions.py --check` checks
the table; `--initialize` explicitly adds it after confirmation. The updated initial
schema includes it for fresh databases. Application startup does not run DDL.
