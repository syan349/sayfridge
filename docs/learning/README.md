# Technical Learning and Design Evolution

This document connects the project's additional technical learning to implemented
choices and recorded verification. It supports assessment criterion 3 and the
technical decisions/lessons component of criterion 12. The account is grounded
in repository code, original designs and dated reports. Weekly discussions,
individual contributions and project-management records remain in the
[team Wiki](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/wiki)
and associated Issues/PRs.

## Learning summary

| Topic | Problem addressed | Engineering lesson | Project benefit |
| --- | --- | --- | --- |
| LangGraph persistence and recovery | A stock request can pause, disconnect or finish its write before the response is received | Workflow checkpoints and committed business receipts have different responsibilities | Pending work resumes without duplicating stock changes |
| Structured user memory | User-specific conversions and aliases need context and authorization | Remembered knowledge is conditional evidence, not inventory truth | Reusable preferences and estimates preserve ownership and their original basis |
| Multimodal input | Photos contain uncertain quantities, personal metadata and large payloads | Validate media and require review independently of model interpretation | Camera/gallery stock entry with controlled writes and reduced metadata disclosure |
| PostgreSQL in cloud hosting | Serverless instances and database poolers have different connection/state lifetimes | Persistent consistency belongs in shared storage; session-level operations need direct connections | Cross-instance sessions, receipts and explicit migration/setup |
| Browser E2E and CI composition | Passing mocked client tests does not prove that clients/API/database work together | Use real boundaries in an isolated environment and test an immutable revision | Eight browser flows plus repeatable multi-module regression |
| Rotating authentication sessions | A short access expiry interrupts Mobile use | Access lifetime, continued login and revocation are separate mechanisms | Automatic renewal with hashed refresh credentials and device-session logout |

## LangGraph: resumable work is not a database transaction

The [original Realtime/dual-Agent blueprint](../archive/2026-09-25/ARCHITECTURE_REALTIME_DRAFT.md)
considered a larger real-time architecture. The implemented system uses one
six-node graph with explicit preparation, execution and human interruption.
A stopped stream releases the HTTP request; it does not leave a transaction open
while the user decides.

Checkpoints preserve drafts, questions and proposal IDs. A business receipt proves
that a write committed. Recovering only the graph state would leave a window for
reapplying a successful write whose response/checkpoint update was interrupted.
Stable action IDs and receipt lookup close that window. Each Agent item has its
own transaction; manual batch endpoints retain all-or-nothing semantics.

Implementation: [workflow](../../backend/app/agents/workflow.py),
[persistence](../../backend/app/agents/persistence.py),
[business action service](../../backend/app/services/agent_actions.py).
Evidence: [Agent verification report](../testing/reports/AGENT_V02_TEST_RESULTS.md),
[workflow tests](../../backend/tests/test_agent_workflow.py).

## Memory: separate knowledge from stock facts

A remembered cup/weight relationship is applicable only to its stated product,
measure, space and time conditions. It cannot make an empirical conversion exact.
The Store namespace comes from authenticated identity rather than model output.
Explicit user instructions authorize memory changes, and the preparation step
checks applicability and fingerprints before executing an action.

This separates an evolving preference from a historical calculation: receipts
retain the relationship used at execution, while later memory updates affect
future interpretation. Bounded preloading and per-turn caching reduce repeated
reads without treating omitted entries as nonexistent.

Implementation: [memory service](../../backend/app/agents/memory.py).
Evidence: [memory tests](../../backend/tests/test_agent_memory.py),
[quantity rules](../architecture/QUANTITY_STATE_DESIGN.md).

## Multimodal processing: recognition and authority are separate

The same configured model receives text and still images. Speech recognition
runs in the client and produces editable text; the backend does not process audio.
Image-derived stock remains a review proposal until confirmation. Uploaded image
pixels are decoded, oriented and re-encoded before model/checkpoint use to remove
metadata. Format, decoded size, dimensions and overall request limits bound input.

The recorded live-model image checks also exposed an HTTP-client/event-loop test
fixture problem. Correcting fixture lifetime and rerunning the failed selection
established the result instead of changing product behavior to satisfy the test.
The [multimodal report](../testing/reports/AGENT_MULTIMODAL_TEST_RESULTS.md) preserves
both the failure and successful rerun.

Implementation and controls: [Agent design](../architecture/AGENT_DESIGN.md),
[image privacy tests](../../backend/tests/test_image_privacy.py),
[security and privacy](../security/README.md).

## Cloud PostgreSQL: connection type and schema lifecycle matter

FastAPI business traffic uses a pooled connection. Alembic, Agent persistence and
conversation advisory locks use direct connections. Session-level locks cannot
be treated as ordinary short pooled queries. Database-backed sessions/receipts
also avoid tying authentication or duplicate prevention to a single Vercel process.

Schema upgrades and seed are explicit operator actions. A new code deployment
is not a database reset, and startup does not silently change tables. ORM verification
checks the actual schema; separate environment guards keep regression writes out
of the shared Neon database. These choices turn deployment into a repeatable
sequence rather than manual column repairs.

Implementation: [database initializer](../../backend/scripts/initialize_database.py),
[schema verifier](../../backend/scripts/verify_database_schema.py).
Evidence: [database acceptance](../testing/reports/DATABASE_ACCEPTANCE.md).
Operation: [delivery runbook](../delivery/README.md).

## Playwright and CI: realistic boundaries with controlled cost

MSW and Flutter test doubles verify client behavior quickly. Playwright adds the
actual browser, production Web build, FastAPI process, CORS and migrated PostgreSQL
schemas. Unique accounts and disposable schemas make persistence assertions
repeatable without resetting shared data.

Reusable workflows prevent duplicate fast jobs. A path selector runs browser E2E
for integration-relevant changes after fast checks pass. Full Regression resolves
one commit before parallel jobs, so its summary describes one tested version.
Reports retain failures, screenshots and traces rather than equating workflow
configuration with a passing execution.

Implementation: [isolated runner](../../backend/scripts/run_e2e.py),
[browser scenarios](../../web/e2e/inventory.spec.ts),
[full regression workflow](../../.github/workflows/full-regression.yml).
Evidence and execution policy: [testing guide](../testing/README.md).

## Authentication: sustained login without permanent access tokens

Short access JWTs remain appropriate for API requests, while rotating refresh
credentials maintain the user session. The database stores refresh hashes,
consumption state and idle/absolute deadlines. Replay or logout revokes a device
session; other devices retain their separate sessions. Concurrent client requests
share renewal instead of racing independent rotations.

The current authentication dependency verifies signature, identity, type and
time claims, then session validation decodes the token again for its session ID.
Legacy tokens without a session ID remain usable until their original expiry.
The implemented session lifecycle preserves continued login while allowing
device-session revocation.

Evidence: [session tests](../../backend/tests/test_persistent_auth.py),
[browser auth/renewal flow](../../web/e2e/auth-inventory.spec.ts),
[recorded session verification](../testing/reports/TESTING_IMPLEMENTATION_NOTES.md#persistent-login-validation--2026-10-01).

## Applying these lessons

The implementation favors explicit boundaries: model interpretation versus
business authority, workflow state versus committed facts, mocked UI checks
versus real integration, and code deployment versus schema migration. Original
blueprints and intermediate decisions remain accessible through the
[project archive](../archive/README.md). Current designs are maintained in
[System Architecture](../architecture/README.md), with test and release outcomes
recorded separately.
