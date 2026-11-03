# Password Change TDD Record

Branch: `feat/password_reset_support`. Started: 3 November 2026.

## Contract and scope

Mobile Profile changes the signed-in user's local password. It verifies the current
password and ends all device sessions. Forgotten-password recovery is separate.
The API, product and security documents describe the target contract; the results
below record implementation progress, not a released feature claim.

## Cases

| Area | Checks |
| --- | --- |
| Password | Correct/wrong current password, length boundaries, same password, spaces, extra fields |
| Sessions | All devices revoked, unrelated users unaffected, missing/revoked/inactive identity, no-session JWT rejected |
| Transactions | Rollback on commit failure; concurrent password changes, login and refresh |
| Abuse and privacy | Separate attempt limit; no password, hash or token in errors/audit records |
| Mobile | Profile entry, submit/loading, errors, expired-token renewal, credential clearing, sign-in and back navigation |
| Regression | Full offline Backend, Flutter unit/widgets, Web unit/UI and browser E2E against local PostgreSQL |

## Runs

| Phase | Result |
| --- | --- |
| Red: Backend | 924 passed, 22 failed, 70 skipped; 21 new cases failed; one archive timestamp mismatch in local timezone |
| Red: Mobile | 285 passed, 4 new cases failed |
| Baseline: Web / browser | 155 unit/UI passed; 8 browser E2E passed |
| Initial implementation | Backend new cases 18 passed / 3 failed; Mobile new cases 2 passed / 2 failed |
| Iteration 2: corrected Backend password tests | 21 passed |
| Iteration 2: Mobile full tests | 289 passed; manual_preview excluded |
| Iteration 2: Flutter analyze | Passed |
| Iteration 2: full offline Backend snapshot | 547 passed, 400 failed, 70 skipped |

The full Backend snapshot preceded the final rollback-test correction; that test
subsequently passed in the 21-case run. Many existing fixtures still create JWTs
without session IDs. Those requests now fail authentication before business checks.
An additional OpenAPI failure reports a missing description on the new endpoint.
The full Backend suite is not green; fixture migration and another full run are required.

Test setup corrections preserved assertions: unique short-password input, transaction
failure after flush with sanitized HTTP 500, complete refresh mock response, and
UI locators matching Change password. The disposable database uses UTC.

All tests used local PostgreSQL 18 and Flutter 3.44.8. Logs remain outside the
repository under `/private/tmp/sayfridge-password-tdd/results/`. No manual device
acceptance or live-model check was performed. Full-app navigation and secure-storage
concurrency checks remain pending. Web and browser results above are baseline runs.

The implementation handoff contains the detailed iteration-2 failure report.

Live-model tests and manual screenshot generators are opt-in tests; their skip
counts are reported separately. No team-hosted service is a test target.


## Iteration 3 — navigation, contract and credential cleanup

OpenAPI: 3 passed. The new request path was added to the exact operation set,
with explicit JSON-schema checks for 400/401/403/429/422 responses.

Targeted Mobile: 10 passed, 2 failed. Real-app widget tests verify same-frame route
ordering, back to guest home and re-login to authenticated home. Controlled refresh
HTTP/save races and confirmed change with storage-clear faults passed.

Two new red cases require implementation: confirmed server logout still reports
failure when local cleanup fails; rejected refresh does not end in-memory login if
secure storage remains unavailable. Existing offline logout semantics must remain.
Full Backend regression is still pending authentication-fixture migration. No new
full regression or device acceptance claim is made for this iteration.


## Iteration 4 — session-end cleanup

Mobile full regression: **300 passed**, manual_preview excluded. Flutter analyze:
**no issues**. Both iteration-3 failures now pass; existing offline logout, password
change and full-app navigation checks pass.

Three additional cases cover coalesced renewal during missing-refresh cleanup,
missing refresh with persistent storage failure, and failed in-flight renewal
followed by confirmed logout. They check public behavior with controlled asynchronous
boundaries; private generation-counter changes are not asserted directly.

Backend authentication-fixture migration and full regression remain outstanding.
This run does not establish whole-project release readiness or on-device acceptance.
Local evidence: `iteration-4-mobile-full.log` and `iteration-4-analyze.log` under
`/private/tmp/sayfridge-password-tdd/results/`.


## Iteration 5 — authentication fixtures and Backend regression

| Check | Result |
| --- | --- |
| OpenAPI and password-change smoke | 24 passed |
| Full offline Backend | 948 passed, 70 skipped; 108.23 seconds |
| Real-browser E2E against local PostgreSQL | 8 passed; 13.0 seconds |
| Follow-up authentication/session regression | 46 passed |

Normal authenticated fixtures now persist AuthSession rows and issue JWTs with
matching session IDs. Business, ownership and response assertions are retained.
Sessionless tokens are rejected explicitly. Deleted/suspended-account cases use
real sessions so authentication setup cannot mask their account-status checks.
Those last two tests were strengthened after the full run and included in the
46-case follow-up. Production code stayed unchanged during testing.

These results supersede the earlier Backend failure snapshot. Mobile remains at
iteration 4's 300 passing tests and clean static analysis; its implementation has
not changed since that run. Opt-in live-model checks remained skipped. This round
did not exercise team-hosted services or physical devices, and did not deploy.

Evidence remains local under `/private/tmp/sayfridge-password-tdd/results/`:
`iteration-5-smoke.log`, `iteration-5-backend-full.log/xml`, `iteration-5-e2e.log`,
and `iteration-5-auth-final.log/xml`. No commit or push was performed.


## Pre-commit verification — 3 November 2026

Mobile full suite including four email-punctuation regressions: **304 passed**
(manual_preview excluded). Email punctuation is preserved in login and signup
fields; the user's emulator input issue was confirmed as an input-method issue.
No product fix was made for that report.

Evidence: `/private/tmp/sayfridge-password-tdd/results/precommit-mobile.log`.
Backend and browser results remain the iteration-5 runs above. Android manual
password-change acceptance has not yet been reported as complete; no hosted
validation was performed.
