# B01–B03 Authentication Test Results

Validation date: 2026-09-11. Work packages: B01 registration, B02 login, B03 current user. These results describe the local working-tree implementation at the time of testing, not a claim of completed remote CI or team review. No tested commit SHA was recorded because the changes had not yet been committed.

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

The Docker verification ran on the developer's Mac, not a GitHub-hosted runner. Actual GitHub Actions execution remains pending a push, PR, or manual dispatch. No commit or push was performed as part of that verification. The user separately confirmed successful Postman-to-Neon authentication integration testing.

## 2. Delivered behavior

| Work package | Implementation and verification |
| --- | --- |
| B01 registration | Preserves email normalization, password hashing, and ordinary-user initialization. Corrects database error classification so only email uniqueness conflicts return 409. Concurrent registration produces one user row |
| B02 login | Preserves LOCAL account, state, and password checks plus short-lived JWTs. Moves hashing/verification work to a thread pool to avoid heavy computation on the async event loop |
| B03 current user | Validates the token and reads current database role/state. Verifies disabled/deleted users and role changes. Does not include profile editing |

Parameter errors retain HTTP 422 and a detail list, but omit raw input and ctx, exposing only type, loc, and msg so passwords are not echoed. Existing success responses and 401/409 messages remain compatible. API summaries, docstrings, comments, and output messages are now in English; the initial delivery used bilingual descriptions.

## 3. Historical automated validation before removing the fake session

The result in this section predates the shared real-database fixtures. It is retained for traceability and is not the current test split.

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

The user subsequently confirmed successful Postman testing against the local FastAPI service and remote Neon database, after importing the collection through Postman Web and synchronizing it to VS Code. This is a recorded manual confirmation, not a claim that a Runner report was exported. The collection is currently a local optional artifact excluded from the planned documentation commit. Postman-created accounts are not automatically cleaned by pytest.

## 5. Remaining acceptance and limits

- Remote GitHub Actions results must still be confirmed after submission. The workflow uses Python 3.12 and isolated PostgreSQL 18; the local container run is supporting evidence, not a remote CI run.
- The team must review the changes and link code and test results to GitHub Issues. No commit, push, or task closure is implied by this report.
- Web/Flutter integration and device acceptance, cloud application deployment, performance testing, and full security acceptance remain later project work and are not claimed complete here.
- Unit/API/integration results do not turn every design in the backend handbook into an implemented feature. This report covers B01–B03 only.

No database passwords, JWT signing secrets, or real tokens are included in this report. Real .env and .env.test files and generated virtual environments remain ignored by Git. Preserve the date and code revision with future reruns so readers can distinguish results from different versions.
