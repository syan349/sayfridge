# SayFridge API Reference: B01–B04

This reference covers implemented registration, login, current-user, and B04 storage-space endpoints. Section 8 provides the storage-space Postman workflow. B03 does not include profile editing in this phase. Password change, refresh tokens, cookie login, and logout endpoints are outside this delivery. Design rules are maintained in the [backend design handbook](BACKEND_DESIGN.md).

## 1. Start the backend

Activate a Python 3.11 environment with the required packages installed. The current developer uses `conda activate py311`. Confirm that `backend/.env` contains the Neon application connection settings, then run from your checkout:

```bash
# From the repository root
cd backend
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Keep the terminal running; stop with Ctrl+C. If another backend already occupies port 8000, do not start a duplicate. You can use port 8001 instead and change Postman's base_url accordingly.

- Service: `http://127.0.0.1:8000`
- API documentation: `http://127.0.0.1:8000/docs`
- Health check: `GET http://127.0.0.1:8000/health`

The health check does not access the database. Successful registration, login, or current-user requests verify the respective database behavior. The service runs on your computer and stores data in Neon. Postman does not need the database password or JWT signing secret.

Other team members should first follow the [backend README](../backend/README.md) to create a Python 3.11 environment, install requirements.txt, and configure their own .env. Confirm the target database before running migrations. Do not delete or recreate data merely because the server was started more than once.

## 2. Set up Postman

You can create the requests manually using sections 3–5. Set a collection variable `base_url` to `http://127.0.0.1:8000` and save the login token as `access_token` for subsequent requests.

An optional local collection file, `docs/postman/SayFridge_Auth.postman_collection.json`, is currently available to the developer but is intentionally excluded from the planned documentation commit. These instructions do not require that file to be present in the repository.

If you have the local collection, import it into Postman. Use the desktop application, the VS Code extension, or the web application with a connected Desktop Agent to send requests to localhost. A cloud Agent cannot reach your computer's localhost. In the verified setup, the collection was imported in the web application and synchronized to the VS Code extension.

The optional collection defines base_url, email, password, access_token, and user_id. No separate Postman environment file is needed. Avoid environment variables with those names overriding the collection values. The password is a public demonstration value and must not be reused for a real account.

1. Run request **01 (B01 registration)**. Its script generates a unique email each time and saves the user ID; expect 201.
2. Run **02 (B02 login)**. It uses that email and automatically saves access_token after success; expect 200.
3. Run **03 (B03 current user)**. It uses the Bearer token; expect 200 with the same user ID.
4. Run **04–11** for rejection scenarios and inspect Test Results. You may also execute requests in collection order with the Runner.

The existing local collection's request names include Chinese labels; the numbered descriptions above identify them without requiring that local file to be edited or committed.

Rerunning 01 intentionally creates another demonstration account. Use 04 to check duplicate registration. Registration writes to the database configured for the running backend, and the collection does not clean up those accounts. Clear real tokens before saving a shared copy or exporting/sharing the collection. The original local collection contains no real token. Its `not-a-valid-token` value is intentionally invalid input for the 401 test, not a credential; Postman may flag it during secret scanning.

## 3. B01: register a user

**POST `{{base_url}}/api/v1/auth/register`**

Select **No Auth** under Authorization and **raw → JSON** for Body. Content-Type is application/json.

```json
{
  "email": "postman-demo@example.com",
  "password": "PostmanDemo42!"
}
```

Both email and password are required. Email is trimmed and lowercased. Password length is 8–128 characters with no silent truncation. Do not submit role, status, user_id, or other fields; all extra fields are rejected.

Success returns **201 Created**, for example:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "postman-demo@example.com",
  "role": "USER",
  "status": "ACTIVE",
  "created_at": "2026-09-11T00:00:00Z"
}
```

The server generates the ID and timestamp; actual values differ. One user row is created, storing only an Argon2id password hash. No space or inventory is created. Registration does not return a token; log in next.

A duplicate email, including case or leading/trailing whitespace differences, returns **409**:

```json
{"detail":"Email is already registered"}
```

An invalid email, short/long password, missing field, or extra field returns **422**. The detail list identifies the invalid field without echoing the submitted password or raw input:

```json
{
  "detail": [{
    "type": "string_too_short",
    "loc": ["body", "password"],
    "msg": "String should have at least 8 characters"
  }]
}
```

## 4. B02: log in

**POST `{{base_url}}/api/v1/auth/login`**

Select **No Auth** and use the same JSON fields and credentials as registration.

Success returns **200 OK**:

```json
{
  "access_token": "<JWT returned by the server>",
  "token_type": "bearer",
  "expires_in": 900,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "postman-demo@example.com",
    "role": "USER",
    "status": "ACTIVE",
    "created_at": "2026-09-11T00:00:00Z"
  }
}
```

expires_in is measured in seconds; the current configuration is 900 seconds (15 minutes). Login reads the account and verifies the password without creating a database session record or setting a cookie.

Unknown email, wrong password, non-local account, missing password hash, and non-ACTIVE account all return **401**:

```json
{"detail":"Invalid email or password"}
```

Malformed requests still return 422 rather than 401.

For a manually created request, add this under **Scripts → Post-response** to save the token:

```javascript
if (pm.response.code === 200) {
  pm.collectionVariables.set("access_token", pm.response.json().access_token);
}
```

The optional collection already contains this logic and clears the previous token before login to avoid reusing it after a failed login. Apply the same precaution to manually configured requests.

## 5. B03: get the current user

**GET `{{base_url}}/api/v1/auth/me`**

Leave Body empty. Select **Bearer Token** under Authorization and enter `{{access_token}}` in the Token field. Do not add the Bearer prefix there; Postman generates:

```http
Authorization: Bearer <access_token>
```

Success returns **200 OK** with the same public user structure as registration, without the password hash, voice quota, or inventory. The token determines identity; request parameters cannot select another user.

Every request reads the current database role and state. A still-unexpired token is rejected if its user was deleted or changed to SUSPENDED / DISABLED.

Missing, invalid, or expired tokens and unavailable accounts return **401**, with `WWW-Authenticate: Bearer`:

```json
{"detail":"Invalid or expired access token"}
```

To observe expiration manually, wait beyond the token lifetime and resend /me. Log in again to obtain a new token. Isolated database tests cover account suspension, deletion, and role changes. Administrator APIs are not delivered in this phase; do not modify other people's real accounts to perform manual tests.

## 6. Postman acceptance checklist

| Scenario | Expected result |
| --- | --- |
| Register with a new email | 201; USER, ACTIVE; no password hash |
| Register with the same email | 409 |
| Invalid email, 7-character or 129-character password | 422; no raw password echoed |
| Submit role=ADMIN | 422; cannot self-register as administrator |
| Correct login | 200; token, lifetime in seconds, and user |
| Wrong password or unknown account | 401 with identical error content |
| Valid token calling /me | 200 with the same user ID |
| Missing, invalid, or expired token | 401 |

If localhost is unreachable, confirm the backend is running, ports match, and requests use a client that can access your computer. For 500/database errors, inspect backend logs, networking, and Neon configuration. Do not hide errors by repeatedly registering or rebuilding tables. Postman desktop requests to B01–B03 do not require CORS configuration.

## 7. Automated verification and delivery status

Run from backend:

```bash
# 11 scenarios that do not require a database
python -m pytest -v -m "not postgres"

# Full backend suite; requires an isolated test database
python -m pytest -v
```

Database tests read TEST_DATABASE_URL from the process environment or the ignored backend/.env.test file, with the process value taking precedence. They accept only a psycopg direct connection to a database named with the `_test` suffix. They never fall back to the application .env. Each test creates a random auth_test_* schema, applies real Alembic migrations, and cleans only that schema. The current developer's isolated Neon test database is sayfridge_auth_test.

The suite includes 45 B01–B03 scenarios and 70 B04 scenarios: 11 database-free and 104 with real PostgreSQL fixtures. FakeAsyncSession has been removed. Missing TEST_DATABASE_URL causes database tests to fail rather than silently skip. Local and CI runs use identical test code with different selections: local `python -m pytest -v` runs all 115 cases; automatic PR/main CI uses `-m ci` for 22 core cases; manual workflow dispatch runs all 115. CI supplies an environment variable pointing to its temporary PostgreSQL container, not Neon.

CI is configured for Python 3.11 and PostgreSQL 18 on PRs to main, pushes to main, and manual dispatches. Actual remote results must be checked after triggering GitHub Actions. No commit, push, or Issue closure is implied by this document. The user previously confirmed B01–B03 manual Postman/Neon testing, and PR #61 was merged. B04 manual Postman/Neon acceptance and remote CI are not yet recorded.

See [B01–B03 authentication test results](testing/B01-B03_AUTH_TEST_RESULTS.md) for detailed evidence and limitations.


## 8. B04: storage spaces

All six endpoints require `Authorization: Bearer {{access_token}}`. Use the login
steps in section 4, then select **Bearer Token** in Postman. Each request checks
the user's current ACTIVE account state. Administrators also access only their
own spaces through these endpoints.

No additional database migration is needed beyond the existing initial migration.
Start the backend as in section 1. These requests use the running application's
`.env` database; they do not use the pytest test database or its automatic cleanup.

### 8.1 Create a space

**POST `{{base_url}}/api/v1/storage-spaces`**

Body: **raw / JSON**, Content-Type: **application/json**.

```json
{
  "name": "B04 Postman Fridge",
  "type": "FRIDGE"
}
```

Expected: **201** with `id`, `name`, `type`, `status`, `created_at`, and `updated_at`.
Save the returned `id` as a Postman variable named `space_id`.

- Name is trimmed and must contain 1–100 characters after trimming.
- Types: FRIDGE, FREEZER, PANTRY, WAREHOUSE, OTHER (case sensitive).
- The server assigns user ownership and ACTIVE status. Extra fields are rejected.
- An ACTIVE name is unique per user using PostgreSQL `lower(name)`. Archived
  spaces do not reserve names. Duplicate creation, including different letter
  casing, returns **409 / NAME_CONFLICT**. Creation is not idempotent.

### 8.2 List spaces

**GET `{{base_url}}/api/v1/storage-spaces`**

No body. Default query parameters: `status=ACTIVE`, `page=1`, `page_size=20`.
`status` also accepts ARCHIVED or ALL. Page must be at least 1; page_size is 1–100.
Unknown list query parameters are rejected. Results sort by name and then UUID,
ascending, using the database's ordering.

Example: `{{base_url}}/api/v1/storage-spaces?status=ALL&page=1&page_size=10`

Expected: **200** with this structure:

```json
{
  "items": [],
  "total": 0,
  "page": 1,
  "page_size": 10
}
```

The example above represents an empty result. With the space created in 8.1,
`items` contains its public fields and `total` includes it. The count covers all
matching rows, not just the page. An out-of-range page has empty items while
retaining the total. Count and items are read in one SQL statement/snapshot.

### 8.3 Read one space

**GET `{{base_url}}/api/v1/storage-spaces/{{space_id}}`**

Expected: **200** with the public space fields. Both ACTIVE and ARCHIVED spaces
are readable by their owner. Missing and other users' IDs both return **404**:

```json
{"detail":{"code":"NOT_FOUND","message":"Storage space not found"}}
```

### 8.4 Edit a space

**PATCH `{{base_url}}/api/v1/storage-spaces/{{space_id}}`**

Body: **raw / JSON**.

```json
{
  "name": "B04 Renamed Fridge",
  "type": "FREEZER"
}
```

Expected: **200** with the updated fields. Submit name, type, or both. Omitted
fields remain unchanged. Empty objects, explicit nulls, invalid values, and extra
fields return **422**. Only ACTIVE spaces can be edited; restore an archived
space first. A conflicting active name returns **409 / NAME_CONFLICT**, and no
part of the edit is committed. An unchanged request preserves `updated_at`.

### 8.5 Archive a space

**POST `{{base_url}}/api/v1/storage-spaces/{{space_id}}/archive`**

Select **Body: none**; do not send `{}` or JSON null.

Expected: **200**, `status=ARCHIVED`. Repeat the same request: **200** with unchanged
timestamps. IN_STOCK inventory prevents archival with **409 / STATE_CONFLICT**;
EMPTY, DISCARDED, and ARCHIVED inventory do not. Inventory records are not modified.
The service locks the space before checking inventory. Future inventory writers
must coordinate on that same row lock, as required by the design handbook.

After archival, the space disappears from the default list, remains visible with
`status=ARCHIVED` or `status=ALL`, and remains accessible by its detail URL.

### 8.6 Restore a space

**POST `{{base_url}}/api/v1/storage-spaces/{{space_id}}/restore`**

Select **Body: none**.

Expected: **200**, `status=ACTIVE`. Repeating restore on an ACTIVE space returns
its current state without changing timestamps. If another ACTIVE space belonging
to the same user has claimed its name, return **409 / NAME_CONFLICT** and keep the
original space ARCHIVED. Rename the active namesake before retrying restoration.

### 8.7 Errors and manual checks

Business errors use `detail.code` and `detail.message`. Validation errors may also
include `detail.errors` containing field locations and messages, never raw values.
Authentication errors keep the existing B01–B03 format.

| Check | Expected |
| --- | --- |
| Create, list, detail, edit, archive, restore in order | 201, then 200 for each later operation |
| Repeat unchanged edit/archive/restore | 200; unchanged updated_at |
| Reuse an active name with different casing | 409 / NAME_CONFLICT |
| Archive, create an active namesake, then restore the original | 409; original remains archived |
| Edit an archived space | 409 / STATE_CONFLICT |
| Use another account's space ID or an absent UUID | Identical 404 / NOT_FOUND |
| Invalid UUID, name/type, page parameters, null PATCH, or extra fields | 422 / VALIDATION_ERROR |
| Missing/invalid/expired token or inactive account | 401 |

Automated inventory and lock tests prepare their own fixtures; manually exercising
stock-dependent archival awaits inventory APIs or a controlled test fixture. Do
not alter shared Neon tables just to manufacture an acceptance case. B04 manual
Postman acceptance is pending; automated results are in the [B04 test report](testing/B04_STORAGE_SPACES_TEST_RESULTS.md).
