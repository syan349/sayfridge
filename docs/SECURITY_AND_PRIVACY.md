# Security and Privacy

Review date: **2026-09-29**. Scope: SayFridge course demonstration, work items **8.1–8.6**.
Review baseline: `1ac5a5df581b66d659448c109a84a2a9aa04dc12`, plus the security changes
reviewed locally on `syan349_fix_backend_db_issues`.

This document is the single entry point for security controls, privacy disclosures, operational
procedures and verification evidence. It supports course assessment criterion 9: identifying and
mitigating relevant cybersecurity and privacy risks. It does not claim that the system is vulnerability-free.

## Contents

- [Security controls and verification](#security-controls-and-verification)
- [Findings, fixes and verification record](#findings-fixes-and-verification-record)
- [Privacy and third-party data handling](#privacy-and-third-party-data-handling)
- [Logging and secret management](#logging-and-secret-management)
- [Test and audit evidence](#test-and-audit-evidence)
- [Remaining risks and acceptance work](#remaining-risks-and-acceptance-work)

## Security controls and verification

### Authentication, authorization and API security — 8.1–8.2

| Area | Implemented control and verified behaviour |
| --- | --- |
| Authentication | Argon2 password hashing; fixed HS256 JWT verification; required `sub`, `type`, `iat` and `exp` claims. Invalid claims, disallowed algorithms and invalid/expired tokens are rejected. Account status is checked on authenticated requests. |
| Authorization and IDOR | Resource reads/writes are scoped to the authenticated user. Tests cover foreign inventory, spaces, private definitions, history and batch operations. Ordinary users receive 403 from administrator endpoints; missing authentication receives 401. |
| Role escalation | Registration creates a USER. Registration/status-update payload validation rejects unsupported role fields. Tests verify that input cannot create an administrator. |
| Terminal states | Discard/archive and quantity/batch tests reject illegal operations on terminal resources; failed operations do not partially write or restore resources. |
| Agent isolation | Tests cover conversation ownership and repeated/concurrent requests. Model/graph execution uses test doubles; this is not acceptance of the deployed checkpoint service. |
| Authentication coverage | The new route probe enumerated 34 protected OpenAPI method/path pairs, all rejecting missing identity with 401. Registration, login and public version metadata are explicitly excluded. |
| Input and SQL | Pydantic types, ranges and extra-field restrictions; parameterized ORM queries. Tests cover identifiers, quantities, pagination and status values. No input-concatenated business SQL was found in the reviewed code. |
| Token lifecycle | Default expiry is 15 minutes. Clients log out by removing their token; account suspension/disablement blocks subsequent access. Refresh and individual-token revocation are not implemented. |
| CORS | Explicit origin allowlist, no wildcard configuration or cookie credentials. Tests cover allowed/rejected origins and validation/body-limit responses. CORS does not replace authentication. |
| Login throttling | Basic process-local client/account limits exist. This does not provide a shared limit across Vercel instances. |

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

These checks are not antivirus scanning or comprehensive polyglot detection. New model-bound images now have metadata stripped as described in SEC-04; existing checkpoints are not rewritten.

## Findings, fixes and verification record

The following table distinguishes repaired findings from documentation gaps. Deployment acceptance
of these changes was **not performed during this review**; a local pass must not be presented as a
production pass.

| ID | Finding and risk | Fix or response | Verification evidence | Status at review |
| --- | --- | --- | --- | --- |
| SEC-01 | SQLAlchemy exceptions could include bound email/inventory parameters in logs. | Enable `hide_parameters=True` in [database session setup](../backend/app/db/session.py). | `test_sql_exception_representation_hides_bound_private_data` in [security probes](../backend/tests/test_security_review.py): failed before the fix and passed afterward. | Locally verified; deployed behaviour not verified. |
| SEC-02 | Unhandled request exceptions could reach server traceback logs containing sensitive exception text. | Add [SafeErrorsMiddleware](../backend/app/middleware/safe_errors.py): record only random error ID and exception class; return a generic 500 before response start, or end an already-started stream without exposing the exception. CORS wraps this boundary. | `test_exception_details_never_reach_logs_or_response`, two cases in [safe-error tests](../backend/tests/test_safe_errors.py), checks logs, response and CORS. Both passed; no saved pre-fix failing run. | Locally verified; provider/startup logs remain outside this boundary. |
| SEC-03 | Printed settings-validation errors could include sensitive input values. | Set `hide_input_in_errors=True` in [application settings](../backend/app/core/config.py) and [Agent settings](../backend/app/agents/model.py). | `test_settings_validation_does_not_print_input`, two cases in [safe-error tests](../backend/tests/test_safe_errors.py), passed; no saved pre-fix failing run. | Locally verified; structured error exports are not covered by this setting. |
| SEC-04 | Uploaded image metadata could expose private photo information to the model/checkpoint. | Re-encode decoded pixels before constructing model messages; preserve orientation and original-byte request identity. | Four tests in [image privacy tests](../backend/tests/test_image_privacy.py) cover JPEG/PNG/WebP metadata and trailing data, orientation, retries and transparency; passed. | Local verification only; does not erase old checkpoints or client copies. |
| PRIV-02 | Web recovery notice incorrectly claimed the server only retained operations. | Correct the Assistant notice to disclose retained conversation history and images. | Assistant page tests passed, including recovery and literal rendering of hostile model HTML. | Locally verified; not deployed. |
| PRIV-01 | Data destinations, retention and deletion limitations were not consolidated for reviewers/users. | Document data flows, third parties, access and deletion limitations below. | Reviewed against Agent state/persistence/tools, client session storage and voice-input implementation. | Disclosure prepared; not implementation of automatic deletion or a frontend consent screen. |
| OPS-01 | Production Secret and log configuration was not verified during this review. | Document required provider controls and acceptance checks below. | Repository checks and limited secret-pattern scan; no dashboard evidence. | Open: operator verification required. |

SQL parameter hiding does not redact driver-generated error details, SQL literals or arbitrary application
logs. The HTTP boundary cannot cover failures before the application starts. Once a streaming response
has started, its status cannot change; clients must treat missing completion events as interruption.

## Privacy and third-party data handling

### Data stored — 8.4

| Data | Location and purpose |
| --- | --- |
| Email, password hash, role, account status and timestamps | PostgreSQL on Neon for authentication and account administration. Passwords are hashed, not stored as plaintext. |
| Spaces, private item definitions, inventory quantities/dates/notes and operation history | Neon, scoped to the authenticated user. Administrator account inspection does not grant unrestricted inventory access through ordinary inventory APIs. |
| Agent messages, images embedded in messages, pending actions, results and request identifiers | LangGraph PostgreSQL checkpoints for conversation recovery and repeat-operation protection. Base64 is encoding, not encryption. |
| Explicitly requested Agent memories | A user-specific PostgreSQL store namespace. |
| Client session data | Web stores access tokens in memory/sessionStorage. Mobile uses FlutterSecureStorage for tokens and per-user Agent conversation/retry state. Flutter Web storage is subject to browser security and is not equivalent to Android device storage. |

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
- Model-provider retention/training terms depend on the provider and account configuration. The project
  has not verified zero-data-retention guarantees. Reassess this disclosure when changing the model endpoint.

### Access, retention and deletion

Users access data through authenticated APIs. Database/project operators have broader access, which
must be restricted to team members who need it. Shared demo accounts share data: use synthetic data only.

No automatic retention deadline is configured. Accounts, inventory history, checkpoints and memories
remain until explicitly cleaned up. There is no complete self-service account deletion, all-chat deletion
or personal-data export workflow. Inventory archive/discard changes state; it does **not** erase history.
Logout removes a client token; it does **not** delete server data or necessarily clear device chat history.

The Agent can delete an individual memory following an explicit user request. This removes the store
entry, but does not guarantee erasure from old messages, checkpoints, backups or provider logs.

For access/removal requests, contact the team through the course/project communication channel.
An operator must verify ownership, identify related relational data/checkpoints/store entries, coordinate
safe removal and explain backup/provider limitations. This is a manual request procedure, not a tested
one-command deletion service. Resetting an approved isolated demo database is not the normal method
of deleting one user's data.

Before submission, agree a cleanup date, responsible operator and treatment of provider backups/logs.
These decisions are still pending; do not promise automatic expiry to users.

## Logging and secret management

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
These application controls do not prove that provider logs, startup errors or third-party tracing are safe.

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
This review did not rotate live credentials or rewrite history.

## Test and audit evidence

### Recorded local test runs

Environment: Python 3.12 and disposable local PostgreSQL 18, with isolated schemas for database tests.
No live Neon changes, live model calls, Android/iOS builds or full regression were performed for this review.

| Run | Result | Interpretation |
| --- | --- | --- |
| Authentication/security/Agent selection | 149 passed in 6.90 seconds | Includes the initial 60 new security probes. |
| Inventory/space/catalog boundary selection | 314 passed, 183 deselected in 41.68 seconds | Disjoint from the preceding run: together 463 passed. |
| Safe-error/security/config/CORS/Agent-message selection | 90 passed; final rerun 0.82 seconds | Includes four new safe-error cases; overlaps the first run. Do not add 90 to 463. |
| CI selection after both additions | 164 selected out of 722 collected; 558 deselected | Collection count, not a full CI execution result. |

[Security probes](../backend/tests/test_security_review.py) contain 60 new cases;
[safe-error tests](../backend/tests/test_safe_errors.py) contain four. Both are marked `ci`.
Existing evidence includes [auth tests](../backend/tests/test_auth_api.py),
[admin tests](../backend/tests/test_admin_users.py),
[Agent API tests](../backend/tests/test_agent_api_postgres.py) and the inventory/space/catalog suites.
The commands below identify exact selections. Test counts are dated snapshots.

These are recorded local command outcomes. Complete JUnit/CI run artifacts were not captured for those earlier runs. A follow-up below supplies local JUnit artifacts; no deployed acceptance or GitHub CI run is implied.

Run from `backend`, with `TEST_DATABASE_URL` pointing to a disposable PostgreSQL database whose
name ends in `_test`, never the shared Neon integration database:

```bash
python -m pytest -q --strict-markers -p no:cacheprovider \
  tests/test_security_review.py tests/test_security.py tests/test_auth_api.py \
  tests/test_auth_contract.py tests/test_admin_users.py tests/test_cors.py \
  tests/test_login_rate_limit.py tests/test_agent_messages.py tests/test_agent_api_postgres.py \
  tests/test_config.py tests/test_database_target.py tests/test_agent_memory.py

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

| Scope | Result on review date | Evidence and limits |
| --- | --- | --- |
| 75 recorded local Python dependency versions | No known vulnerabilities reported by pip-audit 2.10.1. | [JSON](testing/security/python-audit.json), [audited versions](testing/security/python-audited-versions.txt). Not the actual Vercel installation or a project install lockfile. |
| Web package-lock | npm audit reports zero vulnerabilities at all severity levels. | [JSON](testing/security/web-audit.json). Does not test browser behaviour. |
| 84 hosted packages in Flutter/Dart pubspec.lock | OSV Pub ecosystem query by exact package/version returned no matches. | [Queries/results](testing/security/dart-audit.json). Excludes Flutter/Dart SDKs, SDK packages and native Gradle dependencies. |

No dependency upgrades or lockfile changes were made for these audits. Outdated does not automatically
mean vulnerable; no known advisory is not a guarantee of safety.

Reproduce Python using the recorded version list with
`pip-audit -r docs/testing/security/python-audited-versions.txt --no-deps --disable-pip --format json`
from the repository root; regenerate the list when installed versions change. For npm, run
`npm audit --package-lock-only --json` from `web`.
For Dart, derive hosted packages and exact versions from the current `mobile/pubspec.lock` and POST
`{"queries":[{"package":{"name":"PACKAGE","ecosystem":"Pub"},"version":"VERSION"}]}`
to `https://api.osv.dev/v1/querybatch`; inspect each result and any pagination token.
Network errors are not passing results. Regenerate queries after lockfile changes.

### Secret-pattern checks

An initial scan of 526 tracked text files found no common private-key/API-key pattern matches.
A follow-up limited scan of current source/config/documentation and locally available Git refs also
found no private-key/API-key matches. Its 15 current and 18 historical database-URL matches were
localhost, example or template hosts. See [redacted counts](testing/security/secret-scan.json).
Actual local environment files are ignored; tracked example secrets use placeholders.

This is a heuristic check, not a comprehensive secret scanner. It excludes unavailable/deleted remote
history, forks, screenshots and external artifacts. Provider dashboards were not inspected: the storage
rules above are requirements, not evidence that every deployed setting is correct.

## Remaining risks and acceptance work

| Priority | Remaining item | Next action |
| --- | --- | --- |
| High | Login limits are per-process/client-account; registration and Agent lack shared quotas. | Evaluate shared/edge limits and model cost controls for the public demo. |
| High | No automatic retention or complete deletion workflow. | Agree an owner and cleanup date, expose the privacy notice to users and verify the manual process. |
| High | Provider secrets, log retention, tracing and permissions are unverified. | Inspect Vercel/Render/Neon/GitHub settings and record non-secret acceptance evidence. |
| Medium | No individual-token revocation or refresh; browser storage remains exposed to same-origin XSS. | Document expiry/logout limits; assess revocation needs and perform frontend XSS/browser and Android-device checks. |
| Medium | Python version ranges may resolve differently in deployment; native/SDK dependencies are outside the audit. | Audit deployed versions, consider locking dependencies and review SDK/native dependencies. |
| Medium | Application error controls are not deployed acceptance evidence. | Deploy reviewed changes and verify authentication, ownership, errors and safe logs. Platform/startup errors may still lack CORS. |
| Medium | Gitleaks now covers locally available history and tracked files; external artifacts and remote/deleted history remain outside scope. | Retain local JUnit evidence and add GitHub CI/deployment evidence after publishing. |

Review conclusion: 8.1–8.3 local review/tests, 8.4 disclosure and 8.6 basic audits are complete within
the stated scope. 8.5 repository/application controls are implemented; provider verification is pending.
Documentation does not count as implementation of missing features. No claim of complete security,
provider compliance or successful production deployment is made.

## References

- [OWASP API Security Top 10](https://api-security.owasp.org/editions/2023/en/0x11-t10/)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
- [OWASP File Upload Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html)
- [OWASP Input Validation Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)
- [OSV batch query API](https://google.github.io/osv.dev/post-v1-querybatch/)
- [Dart security guidance](https://dart.dev/security)


## Follow-up local hardening and evidence — 2026-09-29

- New image handling strips metadata before model messages/checkpoint writes. Original-byte digests and
  sizes remain as non-reversible identity metadata to preserve existing retry semantics. The upload body
  exists transiently in request memory; frontend copies and existing database history are unchanged.
- Web model output is tested as literal text: hostile HTML does not create script/image/event-handler
  elements. This is a jsdom component test, not a complete browser penetration test.
- [Backend JUnit](testing/security/backend-security-junit.xml): 159 passed (authentication, security,
  configuration, Agent, image and multimodal selections). This overlaps earlier results.
- [Inventory boundary JUnit](testing/security/inventory-boundaries-junit.xml): 314 passed, 183 deselected. Together with the 159-case selection, 473 distinct Backend cases passed. An initial sandboxed run could not connect to local PostgreSQL; this rerun used the required local access and passed.
- [Web JUnit](testing/security/web-assistant-junit.xml): 7 passed. TypeScript and production Web build passed.
- Official Gitleaks 8.30.1 was checksum-verified and run against all locally available Git history and a
  tracked-file snapshot. [History results](testing/security/gitleaks-history.json) and
  [snapshot results](testing/security/gitleaks-tracked.json) each contain two findings, reviewed as a
  synthetic conversation identifier and an unsubmitted widget-test password. Scanner exit was 1 because
  findings exist; this is a triaged outcome, not an unqualified zero-finding scan. No blanket allowlist was added.
- A broader local directory scan also detected a JWT key in ignored `backend/.env`; this is expected local
  secret storage, not evidence of a Git leak. Its value was never included in the report.
- Android dependency resolution was attempted without building: local Flutter 3.47.3 / Dart 3.13.3 refused
  `flutter pub get --enforce-lockfile` because four SDK-related package versions would change. See the
  [resolution evidence](testing/security/android-audit-blocker.txt). No lockfile was changed; native auditing
  requires a compatible SDK or a separately reviewed SDK/lockfile upgrade. No device verification was performed.

Why remaining work is still open:

| Item | Reason / required next step |
| --- | --- |
| Shared login/registration limits and Agent quota | Requires a new shared counter/quota mechanism and rollout; not an environment-imposed impossibility and not completed by the existing process-local limit. |
| Token revocation/refresh | Additional authentication design and client integration, not a demonstrated failure of existing expiry checks. |
| Retention/deletion | Cleanup date and scope remain undecided. No automatic deletion has been enabled and no live data was deleted. |
| Cloud settings and deployed tests | Requires authenticated provider inspection and deployment of reviewed changes; not performed by local tests. |
| Android native/device verification | SDK/lockfile compatibility blocker above; use matching tooling before native audit/device tests. |

All follow-up artifacts are local evidence. Documentation remains uncommitted pending review.
