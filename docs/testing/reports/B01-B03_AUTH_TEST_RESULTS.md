# B01–B03 Authentication Test Results

Validation date: 2026-09-11. Work packages: B01 registration, B02 login, B03 current user. Tested target: the local uncommitted working tree. Commit SHA: not recorded.

Design: [Backend design handbook](../../architecture/BACKEND_DESIGN.md). Usage: [API reference](../../reference/API_REFERENCE.md).

## 1. Current test suite and results

This section supersedes the historical test split in section 3. Local development and GitHub CI use the same 45 scenarios: 11 database-free scenarios and 34 scenarios with real PostgreSQL fixtures. FakeAsyncSession has been removed. Requests rejected during validation may execute no SQL, but their tests use the same real database fixture.

| Verification | Result |
| --- | --- |
| Full suite, existing Neon sayfridge_auth_test | 45 passed, 0 skipped, 158.43 seconds |
| Identical suite, disposable PostgreSQL 18 Docker container | 45 passed, 0 skipped, 5.40 seconds |
| Database-free selection | 11 passed, 34 deselected |
| Missing TEST_DATABASE_URL, set explicitly to an empty process value | Selected database test failed at setup with a configuration message, as intended |
| Schema cleanup | No auth_test_* schemas remained in either verified database; the temporary container and its volume were removed |
| Workflow configuration | YAML parsed; PR/main-push/manual triggers and the full-suite command checked |

Commands run from backend using the existing Python 3.11 Conda environment:

```bash
python -m pytest -v
python -m pytest -v -m "not postgres"
```

Local tests load the isolated Neon direct URL from the ignored .env.test file. CI provides TEST_DATABASE_URL for its disposable PostgreSQL 18 service and needs no Neon credentials. Both use the shared database fixture in [conftest.py](../../../backend/tests/conftest.py), which migrates and drops a new random schema per test. The [.env.test.example](../../../backend/.env.test.example) template contains placeholders only. The application .env is not a test-connection fallback.

Execution environment: developer Mac with Docker PostgreSQL 18. Remote Actions execution was not recorded in this run. The user separately confirmed successful Postman-to-Neon authentication integration testing.

## 2. Delivered behavior

| Work package | Implementation and verification |
| --- | --- |
| B01 registration | Preserves email normalization, password hashing, and ordinary-user initialization. Corrects database error classification so only email uniqueness conflicts return 409. Concurrent registration produces one user row |
| B02 login | Preserves LOCAL account, state, and password checks plus short-lived JWTs. Moves hashing/verification work to a thread pool to avoid heavy computation on the async event loop |
| B03 current user | Validates the token and reads current database role/state. Verifies disabled/deleted users and role changes. Does not include profile editing |

Parameter errors retain HTTP 422 and a detail list, but omit raw input and ctx, exposing only type, loc, and msg so passwords are not echoed. Existing success responses and 401/409 messages remain compatible. API summaries, docstrings, comments, and output messages are now in English; the initial delivery used bilingual descriptions.

## 3. Historical automated validation before removing the fake session

The result in this section predates the shared real-database fixtures. Its recorded split is 3 PostgreSQL and 42 offline cases; section 1 records the later real-database fixture selection.

Environment: Python 3.11.16, SQLAlchemy 2.0.52, FastAPI 0.141.1, psycopg 3.3.5. Database: the isolated Neon sayfridge_auth_test database through its direct connection. Cleanup-oriented tests did not run in neondb.

Historical command from backend, using the environment available at that time:

```bash
.venv/bin/python -m pytest -q --tb=short
```

Historical result: **45 passed in 21.88 seconds**, including 3 real PostgreSQL tests and 42 offline tests, with no skips. Coverage included request fields and password boundaries; missing, expired, and forged tokens; inactive accounts; current-role reads; the real registration/login/current-user flow; concurrent email uniqueness; and rollback after a non-email constraint error.

Each real database test created an isolated random schema, applied the initial eight-table migration, and deleted only that schema. Tests checked that registration creates no storage space and stores a password hash. The existing neondb had eight tables plus alembic_version; its structure was not changed during this validation.

`python -m pip check` and `git diff --check` passed during the historical validation. SQLAlchemy's asyncio extra was added to explicitly install the asynchronous ORM dependency.

## 4. HTTP and manual Postman acceptance

An HTTP client sent the same 11 scenarios as the local Postman collection to Uvicorn at http://127.0.0.1:8000 and checked status codes and key fields. All passed:

| Scenario | Status code |
| --- | --- |
| Registration | 201 |
| Login | 200 |
| Current user | 200 |
| Duplicate email | 409 |
| Wrong password | 401 |
| Unknown account | 401 |
| Short password | 422 |
| Self-registration as administrator | 422 |
| Missing token | 401 |
| Invalid token | 401 |
| Invalid email | 422 |

That automated HTTP run is separate from a Postman application or Collection Runner result. It used the application .env pooled connection. Its uniquely created temporary account was cleaned by ID and email without modifying other accounts.

The user subsequently confirmed successful Postman testing against the local FastAPI service and remote Neon database, after importing the collection through Postman Web and synchronizing it to VS Code. Manual verification was confirmed by the user; no Collection Runner export was retained. The collection is currently a local optional artifact excluded from the planned documentation commit. Postman-created accounts are not automatically cleaned by pytest.

## 5. Release verification

Coverage: B01 registration, B02 login and B03 current-user APIs. The recorded
workflow used Python 3.12 with isolated PostgreSQL 18. At the time of release,
record remote CI, Web/Flutter and device acceptance, deployed checks,
performance and security results for the selected commit in the
[Final Acceptance Record](FINAL_ACCEPTANCE.md). Link team review and test results
to the corresponding Issues and PRs.

No database passwords, JWT signing secrets, or real tokens are included in this report. Real .env and .env.test files and generated virtual environments remain ignored by Git. Preserve the date and code revision with future reruns so readers can distinguish results from different versions.
