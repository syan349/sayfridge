# SayFridge API Reference: B01–B03

This reference covers the implemented registration, login, and current-user endpoints only. B03 does not include profile editing in this phase. Password change, refresh tokens, cookie login, and logout endpoints are outside this delivery. Design rules are maintained in the [backend design handbook](BACKEND_DESIGN.md).

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

# All 45 scenarios; requires an isolated test database
python -m pytest -v
```

Database tests read TEST_DATABASE_URL from the process environment or the ignored backend/.env.test file, with the process value taking precedence. They accept only a psycopg direct connection to a database named with the `_test` suffix. They never fall back to the application .env. Each test creates a random auth_test_* schema, applies real Alembic migrations, and cleans only that schema. The current developer's isolated Neon test database is sayfridge_auth_test.

The suite contains 11 database-free scenarios and 34 scenarios with real PostgreSQL fixtures. FakeAsyncSession has been removed. Missing TEST_DATABASE_URL causes database tests to fail rather than silently skip. Local and CI runs use identical test code. CI supplies an environment variable pointing to its temporary PostgreSQL container, not Neon.

CI is configured for Python 3.11 and PostgreSQL 18 on PRs to main, pushes to main, and manual dispatches. Actual remote results must be checked after triggering GitHub Actions. No commit, push, or Issue closure is implied by this document. The user has confirmed successful manual Postman/Neon integration testing; team review remains outstanding.

See [B01–B03 authentication test results](testing/B01-B03_AUTH_TEST_RESULTS.md) for detailed evidence and limitations.
