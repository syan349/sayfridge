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
