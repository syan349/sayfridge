# Security and Privacy

Initial review date: **2026-09-29**; subsequent verification notes retain their dates. Scope: SayFridge course demonstration, work items **8.1–8.6**.
Review baseline: `1ac5a5df581b66d659448c109a84a2a9aa04dc12`, plus the security changes
reviewed locally on `syan349_fix_backend_db_issues`. This baseline identifies the
initial audit; current authentication behavior and later results are recorded below.

This document is the single entry point for security controls, privacy disclosures, operational
procedures and verification evidence. It presents completed achievements supporting course assessment
criterion 9: identifying and mitigating relevant cybersecurity and privacy risks.

## Contents

- [Completed achievements](#completed-achievements)
- [Security controls and verification](#security-controls-and-verification)
- [Findings, fixes and verification record](#findings-fixes-and-verification-record)
- [Privacy and third-party data handling](#privacy-and-third-party-data-handling)
- [Logging and secret management](#logging-and-secret-management)
- [Test and audit evidence](#test-and-audit-evidence)
- [Verification scope](#verification-scope)

## Completed achievements

| Relevant risk identified | Achievement | Verification and OWASP relevance |
| --- | --- | --- |
| Invalid credentials or tokens could grant access. | Implemented password hashing, JWT signature/claim/expiry checks and account-status checks. | Authentication and malformed-token tests passed; relates to API2 Broken Authentication. |
| A user could read or change another user's data. | Enforced ownership on inventory, spaces, private definitions, history, batch operations and Agent conversations. | Cross-user access tests passed; relates to API1 Broken Object Level Authorization. |
| A user could gain administrator privileges or call restricted functions. | Restricted administrator endpoints and rejected role injection in registration/update payloads. | Administrator and role-escalation tests passed; relates to API3/API5 property/function authorization. |
| Malformed or oversized input could misuse the API. | Validated identifiers, quantities, text, image format/content, dimensions and request sizes; enforced idempotency and transaction boundaries. | Hostile-input, boundary, replay and rollback tests passed; supports API security and mitigates relevant API4 resource-consumption risks. |
| Logs and errors could disclose credentials or business data. | Hid SQL parameters, sanitized unhandled HTTP errors and suppressed input values in printed settings errors. | Targeted regression tests passed; supports data protection and API8 configuration guidance. |
| Image metadata could disclose private photo information. | Removed metadata before model/checkpoint use while preserving orientation and retry identity. | JPEG/PNG/WebP metadata, orientation, retry and transparency tests passed. |
| Model output could be interpreted as executable HTML. | Verified literal-text rendering of hostile model content in Web chat. | Web component security test passed; supports safe handling of third-party output under API10. |
| Users could misunderstand data retention and third-party processing. | Documented stored data, service providers, text/image/voice handling and actual deletion behaviour; corrected the Web retention notice. | Documentation checked against implementation; Web recovery-notice test passed. |
| Secrets or known vulnerable dependencies could enter the project. | Ran Gitleaks with finding triage and Python/npm/Dart dependency audits; documented secret storage and incident procedures. | Redacted scan/audit attachments retained; no known dependency vulnerabilities reported within the scanned scope. |

Recorded selections: **473 passing Backend tests**, **7 passing Web Assistant tests**,
and a successful Web production build. Linked JUnit/audit files retain the results.
Full Regression and release results are linked from the
[Final Acceptance Record](../testing/reports/FINAL_ACCEPTANCE.md).

## Security controls and verification

### Authentication, authorization and API security — 8.1–8.2

| Area | Implemented control and verified behaviour |
| --- | --- |
| Authentication | Argon2 password hashing; one fixed HS256 JWT verification per protected request; required `sub`, `type`, `iat` and `exp` claims. New login/refresh tokens carry issuer `sayfridge` and audience `sayfridge-api`; incorrect or partial scope claims are rejected. Legacy signed tokens with neither scope claim retain their original expiry and session checks. Account status is checked on authenticated requests. |
| Authorization and IDOR | Resource reads/writes are scoped to the authenticated user. Tests cover foreign inventory, spaces, private definitions, history and batch operations. Ordinary users receive 403 from administrator endpoints; missing authentication receives 401. |
| Role escalation | Registration creates a USER. Registration/status-update payload validation rejects unsupported role fields. Tests verify that input cannot create an administrator. |
| Terminal states | Discard/archive and quantity/batch tests reject illegal operations on terminal resources; failed operations do not partially write or restore resources. |
| Agent isolation | Tests cover conversation ownership and repeated/concurrent requests. Local model/graph execution uses test doubles. Record deployed checkpoint validation in the Final Acceptance Record. |
| Authentication coverage | The new route probe enumerated 34 protected OpenAPI method/path pairs, all rejecting missing identity with 401. Registration, login and public version metadata are explicitly excluded. Refresh and logout use a separate refresh credential; missing or malformed credentials return 422, and refresh rejection returns 401. |
| Input and SQL | Pydantic types, ranges and extra-field restrictions; parameterized ORM queries. Tests cover identifiers, quantities, pagination and status values. No input-concatenated business SQL was found in the reviewed code. |
| Token lifecycle | Access JWTs expire after 15 minutes. Rotating refresh credentials provide a 30-day sliding idle window and a 90-day absolute session limit. PostgreSQL stores only refresh hashes. Server logout and refresh replay revoke the device session; protected requests check revocation and current account status. If the logout request fails over the network, server revocation remains unconfirmed. |
| CORS | Explicit origin allowlist, no wildcard configuration or cookie credentials. Tests cover allowed/rejected origins and validation/body-limit responses. Protected endpoints also require authentication. |
| Login throttling | Client/account limits are process-local; each Vercel instance maintains its own counters. |

### Hostile input and uploads — 8.3

| Scenario | Verified outcome |
| --- | --- |
| SVG, fake PNG, image/MIME mismatch | 422; response does not echo submitted image data or private text. |
| Traversal filename or internal-network URL | The inline-image schema accepts neither filename nor URL fields; extra fields return 422. These probes do not trigger file writes or URL fetching. |
| Oversized image or too many images | Rejected. Limits: 3 MiB per image, 8 MiB combined, four images, 20 million pixels per image. Supported formats are JPEG, PNG and WebP, validated by decoding. |
| Oversized HTTP body | Agent chat/resume reject declared bodies over 12 MiB with 413. A streamed oversized request without Content-Length is also rejected; allowed origins receive CORS headers. |
| Invalid UUID or long text | Invalid Agent conversation/request UUIDs and text over 8,000 characters return 422. Existing tests cover other resource identifiers and field limits. |
| Negative, zero or abnormal quantities/units | Existing invalid/reject tests enforce operation-specific rules; reconciliation is distinguished from additions and consumption. |
| Reused idempotency key | Existing tests cover safe replay, conflicting payload rejection, user isolation and rollback. |

Upload checks validate format, decoded content, dimensions and size. SEC-04 strips
metadata from newly submitted model-bound images; existing checkpoints remain unchanged.

## Findings, fixes and verification record

The following table records identified problems, implemented changes and their verification.
Verification environment: local Python/PostgreSQL and Web component tests.

| ID | Finding and risk | Fix or response | Verification evidence | Recorded verification — 2026-09-29 |
| --- | --- | --- | --- | --- |
| SEC-01 | SQLAlchemy exceptions could include bound email/inventory parameters in logs. | Enable `hide_parameters=True` in [database session setup](../../backend/app/db/session.py). | `test_sql_exception_representation_hides_bound_private_data` in [security probes](../../backend/tests/test_security_review.py): failed before the fix and passed afterward. | Local regression: passed. Deployment verification: pending. |
| SEC-02 | Unhandled request exceptions could reach server traceback logs containing sensitive exception text. | Add [SafeErrorsMiddleware](../../backend/app/middleware/safe_errors.py): record only random error ID and exception class; return a generic 500 before response start, or end an already-started stream without exposing the exception. CORS wraps this boundary. | `test_exception_details_never_reach_logs_or_response`, two cases in [safe-error tests](../../backend/tests/test_safe_errors.py), checks logs, response and CORS. Both passed; retained evidence: post-fix regression results. | Local regression: passed. HTTP scope: request processing after application startup; provider/startup logging requires separate checks. |
| SEC-03 | Printed settings-validation errors could include sensitive input values. | Set `hide_input_in_errors=True` in [application settings](../../backend/app/core/config.py) and [Agent settings](../../backend/app/agents/model.py). | `test_settings_validation_does_not_print_input`, two cases in [safe-error tests](../../backend/tests/test_safe_errors.py), passed; retained evidence: post-fix regression results. | Local regression: passed. Sanitization covers printed errors; structured exports retain input values. |
| SEC-04 | Uploaded image metadata could expose private photo information to the model/checkpoint. | Re-encode decoded pixels before constructing model messages; preserve orientation and original-byte request identity. | Four tests in [image privacy tests](../../backend/tests/test_image_privacy.py) cover JPEG/PNG/WebP metadata and trailing data, orientation, retries and transparency; passed. | Local regression: passed. Processing scope: new submissions; existing checkpoints and client copies remain unchanged. |
| PRIV-02 | Web recovery notice incorrectly claimed the server only retained operations. | Correct the Assistant notice to disclose retained conversation history and images. | Assistant page tests passed, including recovery and literal rendering of hostile model HTML. | Local regression: passed. Deployment: not performed in this review. |
| PRIV-01 | Data destinations, retention and deletion limitations were not consolidated for reviewers/users. | Document data flows, third parties, access and deletion limitations below. | Reviewed against Agent state/persistence/tools, client session storage and voice-input implementation. | Delivered: data-handling disclosure and operator removal procedure. Automatic deletion and a consent screen are outside this implementation. |

SQLAlchemy hides bound parameters. Driver-generated errors, SQL literals, application
logs and startup output require separate logging configuration. After streaming
headers are sent, the status is fixed; treat missing completion events as interruption.

## Privacy and third-party data handling

### Data stored — 8.4

| Data | Location and purpose |
| --- | --- |
| Email, password hash, role, account status and timestamps | PostgreSQL on Neon for authentication and account administration. Passwords are hashed, not stored as plaintext. |
| Device session IDs, expiry/revocation timestamps and refresh credential hashes | PostgreSQL on Neon. Raw refresh credentials are never stored server-side; expiry ends authorization rather than deleting session records. |
| Spaces, private item definitions, inventory quantities/dates/notes and operation history | Neon, scoped to the authenticated user. Administrator account inspection does not grant unrestricted inventory access through ordinary inventory APIs. |
| Agent messages, images embedded in messages, pending actions, results and request identifiers | LangGraph PostgreSQL checkpoints for conversation recovery and repeat-operation protection. Images are stored as Base64-encoded bytes; access is controlled through authenticated APIs and database permissions. |
| Explicitly requested Agent memories | A user-specific PostgreSQL store namespace. |
| Client session data | Web stores access and refresh credentials in memory/sessionStorage. Mobile uses FlutterSecureStorage for tokens and per-user Agent conversation/retry state. Flutter Web storage is subject to browser security and is not equivalent to Android device storage. |

### Third parties, text, images and voice

- **Vercel** runs the Backend and receives API traffic; **Neon** stores database data;
  **Render** serves the deployed frontends. Providers may process IP addresses and access logs;
  their retention is separate from application storage.
- The Agent sends conversation text, submitted images and relevant inventory/tool results or memories
  to the endpoint configured by `AGENT_API_BASE`, intended for OpenAI in this deployment.
  Names, notes and personal information included in those inputs may leave the application database.
  Passwords, JWTs and database credentials are not intended model inputs and must not be pasted into chat.
- Images selected or captured by the client are validated before model use and may remain in checkpoints.
  New submissions are decoded, oriented and re-encoded from pixels before entering model messages, stripping EXIF/GPS, comments and trailing bytes. Existing checkpoints and device-local copies are not cleaned retroactively. Visible personal information inside the pixels is not redacted; do not upload identity documents, private files or unrelated photographs.
- Voice uses device/browser speech recognition through `speech_to_text`. Recognized words become
  editable text; the current Backend does not receive raw audio. Recognition may use a platform vendor's
  cloud service; offline recognition is not enforced. Check the transcript before sending it.
- Provider retention and training follow the configured account and service terms.
  Provider-retention verification: pending. Review these settings when changing the model endpoint.

### Access, retention and deletion

Users access data through authenticated APIs. Database/project operators have broader access, which
must be restricted to team members who need it. Shared demo accounts share data: use synthetic data only.

Accounts, inventory history, checkpoints and memories remain until explicitly
cleaned up; automatic retention cleanup is not configured. Removal requests use
the operator procedure below. Self-service account/all-chat deletion and personal-data
export workflows are not implemented. Archive/discard retains inventory
history. Logout revokes the server session after a successful request and clears
client credentials; stored server data and device chat history have separate lifecycles.

An explicit user request can delete an individual Agent memory from the Store.
Existing messages, checkpoints, backups and provider logs follow their separate
retention and removal procedures.

For access/removal requests, contact the team through the course/project communication channel.
The operator verifies ownership, identifies the user's relational data, checkpoints
and Store entries, coordinates removal, and explains the applicable backup/provider
retention. Handle individual removal requests through this procedure; isolated demo
database resets use the separate reset process.

## Logging and secret management

### Authentication boundary and security events

Protected requests verify the JWT signature and claims once, then pass immutable user/session
UUIDs to the database session check. Current account status, role, session expiry and revocation
remain enforced on every request. Login and refresh issue tokens scoped to issuer `sayfridge`
and audience `sayfridge-api`. Wrong, partial or malformed scope claims are rejected.
Existing signed tokens with neither scope claim remain accepted until their original expiry;
existing session-bearing tokens still undergo the database revocation check. Refresh replaces
these tokens with scoped tokens. This rollout requires no migration or client payload change.

The `app.security.audit` logger records login success/failure, login throttling, authentication
rejection, denied administrator access, refresh rejection/replay and device-session revocation.
Each HTTP event has a server-generated request UUID; replay and revocation events from the same
request share it. Records include only the fixed event name and applicable internal user/session
UUIDs. They exclude email addresses, IP addresses, passwords, access/refresh tokens, token hashes,
request bodies and exception text. Revocation events are emitted after the database commit.

Regression evidence: `backend/tests/test_security.py` checks token scope and malformed session
claims. `backend/tests/test_persistent_auth.py` checks one JWT decode per protected request,
legacy-token compatibility, refresh/logout behavior and correlated credential-free audit records.

Verification on 2 October 2026 on the fresh main-derived Backend readiness branch:
130 selected regression cases and 172 fast CI cases passed against isolated local
PostgreSQL schemas. The selections overlap. They verify issuer/audience scope,
one JWT decode, legacy-token compatibility, refresh/logout, administrator boundaries
and credential-free audit events. The
[Backend readiness record](../testing/reports/FINAL_ACCEPTANCE.md#backend-release-readiness-verification--2026-10-02)
links the fresh-branch JUnit reports and code fingerprints. The earlier hosted smoke
checks deployed main `d402b799`; rollout verification follows the new PR's merge and
deployment from main.

### Logging rules — 8.5

The HTTP error boundary logs only an error ID and exception class, never exception text, traceback,
URL/query, headers or request body. Agent stream failures also log only the exception type.
SQLAlchemy hides bound parameters; settings errors hide inputs in their printed representation.

Do not enable HTTP/SQL/model debug logging, request-body capture or LangSmith tracing without a
separate privacy review. Never log passwords, JWTs/Authorization headers, API keys, complete database
URLs, conversation text or Base64 images. Do not log settings `exc.errors()` or `exc.json()`:
`hide_input_in_errors` does not sanitize those structured exports.

Use error IDs, operation names and exception classes for diagnostics. Reproduce failures locally with
synthetic inputs when more detail is needed. Restrict provider log access and explicitly configure retention.
During deployment acceptance, verify provider log access, retention, startup output
and third-party tracing settings.

### Secret storage and incident procedure

| Environment | Required practice |
| --- | --- |
| Vercel Backend | Store database URLs, JWT signing key and model key as Secret environment variables for the intended environment; redeploy after changing them. |
| Neon | Restrict database roles/credentials; never provide owner credentials to frontend code. |
| Render | Use provider secret environment variables for server-side secrets. Browser bundles, Vite variables and Flutter dart-defines are public: include API base URLs, never Backend credentials. |
| GitHub Actions | Use GitHub Secrets for required external credentials. Normal tests use disposable service credentials, not production Neon/model keys. |
| Local | Protect ignored `.env`/`.env.*` files with OS permissions. Commit only example templates with placeholders for secret values. |

Non-secret example ports, timeouts and model names may remain concrete. Synthetic localhost test
credentials are not production secrets. Do not copy actual secrets into fixtures, documentation,
screenshots, PRs or artifacts.

Submit acceptance credentials through the course-designated submission application and use a private
team channel for operational sharing. Never publish actual demo/admin passwords in a public README.

If a real secret is committed, revoke/rotate it first, update provider settings, redeploy and verify access.
Deleting a file or rewriting history does not revoke a secret. Coordinate any history rewrite with the team.
Review activity: code, test and audit verification. Credential rotation and history
rewrites are operator incident-response steps.

## Test and audit evidence

### Recorded local test runs

Environment: Python 3.12 and disposable local PostgreSQL 18, with isolated schemas for database tests.
Executed selections: local Backend tests, Web Assistant tests and Web production build.
Live Neon/model, Android/iOS and Full Regression execution are recorded separately.

| Run | Result | Interpretation |
| --- | --- | --- |
| Authentication/security/Agent/image selection | 159 passed | [Backend JUnit](../testing/evidence/security/backend-security-junit.xml). |
| Inventory/space/catalog boundary selection | 314 passed, 183 deselected | [Boundary JUnit](../testing/evidence/security/inventory-boundaries-junit.xml); disjoint from the 159-case selection, giving 473 Backend cases. |
| Web Assistant selection | 7 passed | [Web JUnit](../testing/evidence/security/web-assistant-junit.xml); includes hostile-text rendering and retention-notice verification. |
| Web production build | Passed | TypeScript checks and Vite build completed locally. |
| Backend CI collection | 168 selected out of 726 collected | Collection: 168 selected / 726 collected. Execution result: not recorded for this collection check. |

[Security probes](../../backend/tests/test_security_review.py) contain 60 new cases;
[safe-error tests](../../backend/tests/test_safe_errors.py) and
[image privacy tests](../../backend/tests/test_image_privacy.py) contain four each. All are marked `ci`.
Existing evidence includes [auth tests](../../backend/tests/test_auth_api.py),
[admin tests](../../backend/tests/test_admin_users.py),
[Agent API tests](../../backend/tests/test_agent_api_postgres.py) and inventory/space/catalog suites.
Counts are dated snapshots. Earlier overlapping runs are not added to these totals.


Run from `backend`, with `TEST_DATABASE_URL` pointing to a disposable PostgreSQL database whose
name ends in `_test`, never the shared Neon integration database:

```bash
python -m pytest -q --strict-markers -p no:cacheprovider \
  tests/test_security_review.py tests/test_security.py tests/test_auth_api.py \
  tests/test_auth_contract.py tests/test_admin_users.py tests/test_cors.py \
  tests/test_login_rate_limit.py tests/test_agent_messages.py tests/test_agent_api_postgres.py \
  tests/test_config.py tests/test_database_target.py tests/test_agent_memory.py \
  tests/test_safe_errors.py tests/test_image_privacy.py tests/test_agent_multimodal_postgres.py

python -m pytest -q --strict-markers -p no:cacheprovider \
  tests/test_inventory*.py tests/test_storage_spaces*.py tests/test_catalog*.py \
  -k 'foreign or ownership or authentication or terminal or invalid or reject or idempot or replay or private or invisible or rollback or archived'

python -m pytest -q -p no:cacheprovider \
  tests/test_safe_errors.py tests/test_security_review.py tests/test_config.py \
  tests/test_cors.py tests/test_agent_messages.py
```

For future evidence capture, append `--junitxml=/path/to/security-results.xml` and retain the result
with the tested commit, environment and date. Keep sensitive data out of failure output before sharing it.

### Dependency audits — 8.6

| Audited scope | Recorded result — 2026-09-29 | Evidence and coverage |
| --- | --- | --- |
| 75 recorded local Python dependency versions | No known vulnerabilities reported by pip-audit 2.10.1. | [JSON](../testing/evidence/security/python-audit.json), [audited versions](../testing/evidence/security/python-audited-versions.txt). Audited environment: the 75 recorded local package versions; Vercel-installed versions require a separate audit. |
| Web package-lock | npm audit reports zero vulnerabilities at all severity levels. | [JSON](../testing/evidence/security/web-audit.json); npm dependency audit. |
| 84 hosted packages in Flutter/Dart pubspec.lock | OSV Pub ecosystem query by exact package/version returned no matches. | [Queries/results](../testing/evidence/security/dart-audit.json). Excludes Flutter/Dart SDKs, SDK packages and native Gradle dependencies. |

The audits reported no matching advisories for the recorded versions on
2026-09-29. Package versions and lockfiles were unchanged. Rerun the audits after
dependency changes.

Reproduce Python using the recorded version list with
`pip-audit -r docs/testing/evidence/security/python-audited-versions.txt --no-deps --disable-pip --format json`
from the repository root; regenerate the list when installed versions change. For npm, run
`npm audit --package-lock-only --json` from `web`.
For Dart, derive hosted packages and exact versions from the current `mobile/pubspec.lock` and POST
`{"queries":[{"package":{"name":"PACKAGE","ecosystem":"Pub"},"version":"VERSION"}]}`
to `https://api.osv.dev/v1/querybatch`; inspect each result and any pagination token.
Record network errors as incomplete audit attempts and rerun them. Regenerate
queries after lockfile changes.

### Secret-pattern checks

An initial scan of 526 tracked text files found no common private-key/API-key pattern matches.
A follow-up limited scan of current source/config/documentation and locally available Git refs also
found no private-key/API-key matches. Its 15 current and 18 historical database-URL matches were
localhost, example or template hosts. See [redacted counts](../testing/evidence/security/secret-scan.json).
Actual local environment files are ignored; tracked example secrets use placeholders.

Scanned: tracked text, current source/configuration/documentation and locally
available Git refs. Excluded: unavailable/deleted remote history, forks, screenshots
and external artifacts. Hosting-secret configuration verification: pending in this
review; use the storage checklist during deployment acceptance.

## Verification scope

| Activity | Execution in the initial review |
| --- | --- |
| Code review and selected automated tests | Completed locally; evidence linked above |
| Tracked-file/history secret scans and dependency audits | Completed for the stated artifact scopes |
| Full Regression, deployed service and provider-dashboard checks | Separate release verification; see the Final Acceptance Record |
| Full penetration test | Not performed |
| Physical Android device acceptance | Not performed in this review; record results in the Final Acceptance Record |

OWASP categories organize the risk-to-control mapping. Login limits are process-local;
request-size limits bound individual requests. Data retention and removal follow
the procedures above.

## References

- [OWASP API Security Top 10](https://api-security.owasp.org/editions/2023/en/0x11-t10/)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
- [OWASP File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html)
- [OWASP Input Validation Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)
- [OSV batch query API](https://google.github.io/osv.dev/post-v1-querybatch/)
- [Dart security guidance](https://dart.dev/security)


## Supporting verification notes — 2026-09-29

- New image handling strips metadata before model messages/checkpoint writes. Original-byte digests and
  sizes remain as non-reversible identity metadata to preserve existing retry semantics. The upload body
  exists transiently in request memory; frontend copies and existing database history are unchanged.
- jsdom component verification passed: hostile model text renders without executable
  script/image/event-handler elements.
- [Backend JUnit](../testing/evidence/security/backend-security-junit.xml): 159 passed (authentication, security,
  configuration, Agent, image and multimodal selections). This overlaps earlier results.
- [Inventory boundary JUnit](../testing/evidence/security/inventory-boundaries-junit.xml): 314 passed, 183 deselected. Together with the 159-case selection, 473 distinct Backend cases passed. An initial sandboxed run could not connect to local PostgreSQL; this rerun used the required local access and passed.
- [Web JUnit](../testing/evidence/security/web-assistant-junit.xml): 7 passed. TypeScript and production Web build passed.
- Official Gitleaks 8.30.1 was checksum-verified and run against all locally available Git history and a
  tracked-file snapshot. [History results](../testing/evidence/security/gitleaks-history.json) and
  [snapshot results](../testing/evidence/security/gitleaks-tracked.json) each contain two findings, reviewed as a
  synthetic conversation identifier and an unsubmitted widget-test password. Scanner exit code: 1. Both findings were classified as synthetic test values.
  No blanket allowlist was added.
- A broader local directory scan detected a JWT key in ignored `backend/.env`.
  Tracked-file/history findings are listed separately; the key value is omitted.

Verification platform: local Python/PostgreSQL and Web/jsdom. Record Android
acceptance results in the
[Final Acceptance Record](../testing/reports/FINAL_ACCEPTANCE.md#manual-cross-client-and-android-validation).


### Persistent-session verification

The persistent-login change adds database-backed device sessions and single-use
refresh rotation. Tests cover expired access renewal, replay revocation, immediate
logout, inactive accounts, idle/absolute expiry, and the absolute cap. Web and Flutter
client tests cover concurrent renewal, credential replacement, and network failures.
See [Backend tests](../../backend/tests/test_persistent_auth.py),
[Web client tests](../../web/src/api/client.test.ts), and
[Flutter repository tests](../../mobile/test/repositories/auth_repository_test.dart).
Verification environment: local isolated schemas and client tests. Apply the
session migration and verify deployed renewal during release acceptance. Browser
credentials are accessible to same-origin JavaScript; retain literal-text rendering
and other XSS controls.


## Related maintained guides

Current testing strategy and CI execution belong to the [testing guide](../testing/README.md).
Migration, hosting secrets and deployed acceptance commands belong to the
[delivery runbook](../delivery/README.md). This document owns security conclusions,
privacy behavior, findings/fixes and their dated evidence.
