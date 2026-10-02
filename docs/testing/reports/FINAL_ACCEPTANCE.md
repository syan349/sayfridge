# Final Release Acceptance Record

**Status: awaiting final release execution.** This is the prepared record for the
selected release; no final-release result is recorded yet. Existing test results
remain in the [testing evidence index](../README.md#reports).

## Release identity

Complete this section when selecting the submission release.

| Field | Recorded value |
| --- | --- |
| Acceptance date/time and timezone | Pending |
| Tester(s) | Pending |
| Selected main commit SHA | Pending |
| Release tag and GitHub Release URL | Pending |
| Android APK filename and SHA-256 | Pending |
| APK signing configuration | Pending |
| Android device/emulator model and OS version | Pending |
| React Render deployment commit | Pending |
| Flutter Web Render deployment commit | Pending |
| Backend /system/version commit_sha | Pending |
| Neon branch/endpoint identifier (no credentials) | Pending |
| Alembic revision and category-seed verification | Pending |

## Automated release validation

| Check | Command or entry | Outcome | Evidence |
| --- | --- | --- | --- |
| Same-commit regression | Actions → Full Regression → Run workflow | Not run for final release | Pending run URL and downloaded summary/JUnit/browser artifacts |
| Database verification | verify_database_schema.py; setup_agent_storage.py --check | Not run for final release | Pending output |
| Database acceptance record | record_database_acceptance.py | Not run for final release | Pending credential-free JSON |
| Deployed Backend smoke | smoke_deployment.py | Not run for final release | Pending sanitized output and commit match |

The [delivery runbook](../../delivery/README.md) owns commands, configuration and
deployment order. Run results identify the selected release rather than reusing
older results as if they tested the final commit.

## Backend release-readiness verification — 2026-10-02

The three authentication controls were rebuilt on the fresh main-derived branch
`syan349_fix_backend_readiness`, based on main `d402b79970e005e4922babba1c48d6f1dda5e36c`.
The old fix branch was deleted; its commit was not merged or cherry-picked.
These results test the uncommitted working tree. The
[verification manifest](../evidence/backend-release-readiness/verification-2026-10-02.json)
records the code/test SHA-256 values and preserves earlier same-day verification.

| Check | Actual result | Evidence |
| --- | --- | --- |
| Authentication, permissions, persistent sessions, JWT scope, safe logging, smoke-runner and Agent quantity/dialogue selection | 130 passed in 13.88 seconds; Python 3.12 and isolated local PostgreSQL 18 schemas | [Fresh-branch JUnit](../evidence/backend-release-readiness/auth-regression-fresh-main-2026-10-02.xml) |
| Backend fast CI selection | 172 passed, 743 deselected in 24.85 seconds; same local test environment | [Fresh-branch JUnit](../evidence/backend-release-readiness/fast-ci-fresh-main-2026-10-02.xml) |
| Earlier same-day real-model check for issue #144 | 2 passed in 55.68 seconds; `gpt-6-luna` and isolated local inventory, before recreating the branch | [Live-model JUnit](../evidence/backend-release-readiness/agent-half-consumption-live-2026-10-02.xml) |
| Earlier same-day deployed Backend baseline | Health/version, unauthenticated rejection, ordinary/admin login, categories, stock/expiry reads, administrator denial, refresh rotation, logout revocation and browser CORS passed | [Sanitized smoke result](../evidence/backend-release-readiness/deployment-2026-10-02.json) |
| Existing Neon baseline | Revision `a261002_categories`; 25 active public categories | Included in the sanitized smoke result |

The regression selections overlap; their counts are reported separately. The first
fresh-branch attempt could not connect to local PostgreSQL from the sandbox. After
loopback permission was granted, all 130 cases passed; the manifest records both
attempts. No shared Neon inventory or schema was changed by these fresh runs.

The earlier real-model check verifies that a single 2 kg rice batch becomes 1 kg
after consuming half. With two batches, target clarification is required before
deduction; a new purchase and inventory query preserve the pending task; selecting
the Kitchen batch resumes the deduction once and leaves the Garage batch unchanged.
It verifies Backend dialogue and persistence, with Mobile UI acceptance recorded
separately below. The initial missing-model-configuration attempt and successful
rerun are preserved in the manifest.

The hosted smoke verifies deployed main `d402b799`, before this hardening rollout.
It creates and revokes authentication sessions and performs read-only business and
database queries. After the new changes are committed and merged into main, deploy
that main version, repeat hosted checks and record its production SHA. Final release
identity and cross-client acceptance are recorded in the sections above and below.

## Manual cross-client and Android validation

Use a dedicated ordinary account and an existing administrator account. Store their
passwords only in the course-designated private channel. For each row record the
actual result and screenshot/log reference. Native checks identify the Android
emulator or device used; browser emulation is recorded separately.

| Scenario | Expected result | Outcome | Evidence |
| --- | --- | --- | --- |
| Install and start APK | Installed package opens and reaches configured Vercel API | Not run | Pending |
| Login and automatic renewal | Inventory remains usable after access expiry; invalid session returns to login | Not run | Pending |
| Logout | Current device session is revoked; protected use requires login | Not run | Pending |
| Mobile stock → React inventory | Added item/quantity/location match under the same account | Not run | Pending |
| Consumption and physical reconciliation | Both clients show persisted balance and correct history | Not run | Pending |
| Camera/gallery stock | Photo candidate is reviewed before stock commits | Not run | Pending |
| Speech input | Permission, editable transcription and explicit sending work | Not run | Pending |
| Permission denial | Camera/microphone/notification denial produces usable feedback | Not run | Pending |
| Native reminders | Selected permission and schedule behavior match saved preferences | Not run | Pending |
| Network interruption | Input is retained; Agent state/retry avoids duplicate writes | Not run | Pending |
| Expiry and stock removal | Expiry grouping is correct; archive/discard retain the record | Not run | Pending |
| Ownership and administrator boundary | Foreign data is inaccessible; ordinary account cannot access admin APIs | Not run | Pending |
| Browser direct navigation/reload | Inventory/expiry/admin routes use the SPA rewrite and authenticated API | Not run | Pending |

## Findings and reruns

| Finding | Reproduction and observed result | Fix/issue/commit | Rerun and evidence |
| --- | --- | --- | --- |
| No final-release findings recorded yet | — | — | — |

Keep an initial failure alongside its successful rerun. Record final accepted
behavior and any team scope decision; do not erase earlier evidence.

## Submission links

| Deliverable | Location |
| --- | --- |
| Project overview and setup | [Root README](../../../README.md) |
| Tested release APK and installation instructions | Pending GitHub Release URL |
| Architecture and decisions | [System Architecture](../../architecture/README.md) |
| Technical learning | [Learning and Design Evolution](../../learning/README.md) |
| Security/privacy evidence | [Security and Privacy](../../security/README.md) |
| Historical designs and results | [Project archive](../../archive/README.md) |
| Weekly meetings, decisions and responsibilities | [Team Wiki](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/wiki) |

Complete the record after executing the checks, retain selected Actions artifacts,
and ensure the deliverable documentation and code are merged into main for submission.
