# SayFridge — Personal Maintenance

<img align="right" src="mobile/assets/launcher/launcher_avatar.png" alt="SayFridge app icon: a green fridge and microphone" width="200" height="200" />

SayFridge is a household inventory system that helps people record what they
have, where it is stored, how much remains, and what will expire soon. The
system combines an Android-focused Flutter application, a React web
application, and a shared FastAPI backend backed by PostgreSQL. An AI assistant
can translate text, editable speech transcripts, and supported image input into inventory actions;
the backend remains responsible for authentication, ownership checks, quantity
rules, and database transactions.

This is an independent personal continuation maintained by **syan349**. SayFridge
was originally developed by **Team Appix** for COMPSCI 734. The team agreed that
members could maintain personal copies. The original implementation is shared
team work; the contributor table below preserves that attribution.

The personal copy currently contains the course implementation and local
privacy/documentation changes. A personal hosted demo and release have not been
configured. Start with the local setup below.

<br clear="right" />

[Repository](https://github.com/syan349/sayfridge) · [Run locally](#local-development-prerequisites) · [My contribution](#maintainer-contribution) ·
[Run tests](#run-the-tests) · [Architecture](#technology-stack-and-architecture) ·
[Documentation](#documentation-and-historical-evidence) · [Publication review](docs/maintenance/PUBLICATION_REVIEW.md)

## Maintainer contribution

My work focused on Backend business APIs and database integration, including
inventory operations and their validation. I also implemented persistent-login
fixes, strengthened JWT verification and security-event logging, and worked on
test and release verification.

| Area | Examples in this copy's history |
| --- | --- |
| Persistent login and authentication | `13c63ce` adds token renewal and revocable sessions; `3e4981b` strengthens JWT verification and security logging. |
| Testing and CI | `ae1f663` fixes an E2E navigation race; `41e314d` coordinates full regression against one commit; `875c52e` adds performance tests and records. |
| Documentation and delivery | `2ccb38c`, `f30e66a` and `808ed67` organize project guides and preserve evidence; `fc0fc1b` records manual integration testing. I also coordinated Vercel/Neon deployment verification and Android release records. |

Architecture, the AI agent and both frontends were developed with the team. The
[original contributors](#original-team-contributors) section distinguishes these roles.

## Personal maintenance direction

The next work is to make the project reproducible under personal infrastructure,
keep the authentication and inventory regression checks current, and improve
deployment instructions. Future feature changes will have their own tests and
release records. This copy's recent work has been privacy cleanup and documentation.

Historical test reports retain their original dates, environments and source
commit identifiers. Git history was rewritten to remove selected personal data,
so original commit IDs in reports refer to the team repository, not this copy.
Links to its Wiki, Issues, PRs and Actions remain historical references and require
access to that repository. They are not required for local setup.

## App screenshots

Home, Inventory, AI inventory query, and Expiry overview show team-supplied
demonstration screenshots from 4 October 2026. Add item and Storage spaces are
Flutter widget renders of the updated UI. Select an image to view it at full size.

| Home dashboard | Inventory | AI inventory query |
| :---: | :---: | :---: |
| <a href="docs/images/readme/mobile-home.jpg"><img src="docs/images/readme/mobile-home.jpg" alt="Home dashboard showing expiry alerts, inventory totals, and assistant navigation" width="240" /></a> | <a href="docs/images/readme/mobile-inventory.jpg"><img src="docs/images/readme/mobile-inventory.jpg" alt="Inventory list with storage locations, expiry status, exact quantities, and AI estimates" width="240" /></a> | <a href="docs/images/readme/mobile-ai-inventory-query.png"><img src="docs/images/readme/mobile-ai-inventory-query.png" alt="AI Assistant answering an inventory query with milk and apple cards" width="240" /></a> |
| Review stock and expiry alerts. | View exact and estimated balances. | Ask what is in your fridge. |

| Add item | Storage spaces | Expiry overview |
| :---: | :---: | :---: |
| <a href="docs/images/readme/mobile-add-item.png"><img src="docs/images/readme/mobile-add-item.png" alt="Updated Add item form with a plain item-name input, category, quantity, dates, storage, and notes" width="240" /></a> | <a href="docs/images/readme/mobile-storage-spaces.png"><img src="docs/images/readme/mobile-storage-spaces.png" alt="Storage-space management with a default fridge, archive and restore actions, and the spaced Add storage space button" width="240" /></a> | <a href="docs/images/readme/mobile-expiry-overview.jpg"><img src="docs/images/readme/mobile-expiry-overview.jpg" alt="Expiry overview listing overdue chicken and milk with their quantities and storage spaces" width="240" /></a> |
| Add stock with quantity and dates. | Organize stock by storage location. | Find overdue and upcoming items. |

## Target users and user need

SayFridge is intended for people who manage food and household supplies across
several storage spaces, such as a fridge, freezer, pantry, or cupboard. It aims
to reduce forgotten stock and duplicate purchases by making these common tasks
easier:

- recording purchases and existing stock;
- checking the current quantity and storage location of an item;
- recording additions, consumption, and physical stocktakes;
- moving, discarding, or archiving inventory;
- finding overdue and soon-to-expire items; and
- managing accounts and account status as an administrator.

## Why there are separate Mobile and Web applications

The two clients share the same accounts, inventory, and FastAPI API, but support
different contexts rather than duplicating the same interface.

| Client | Primary use |
| --- | --- |
| Flutter Mobile | Quick use while shopping or standing near stored items; camera, image selection, voice input, and guided inventory actions. |
| React Web | Large-screen inventory review, search and filtering, batch stock entry and movement, expiry reporting, operation history, and administrator account management. |

The Flutter project also has a Web build so the Mobile UI can run in
a browser. This is a deployment and demonstration entry point; Android device
or emulator testing is still required for native permissions and device
features.

## Core features

- Email/password registration and sign-in with automatic renewal and revocable device sessions.
- Storage spaces with a default location, archive/restore, private item definitions,
  and public or user-owned categories.
- Inventory listing, detail, search, pagination, metadata editing, and movement.
- Atomic batch creation, movement, and archival.
- ADD, CONSUME, and RECONCILE quantity operations with idempotent retries.
- Inventory discard/archive actions and per-item/global operation history.
- Expiry summary and overdue/upcoming inventory views.
- Administrator account listing and permitted status management.
- AI assistant for text and photos, with streamed responses, clarification,
  review cards, explicit user memory, and recovery of unfinished requests.
- Approximate quantities remain visibly estimated until the user records an
  exact physical stocktake. Missing expiry dates can be estimated, with warnings
  when estimation fails.
- Flutter Home, inventory, storage-space, Profile, local reminder, and Daily
  Check-in workflows for Android and Web.

Complete, unambiguous text actions can execute directly. Photo-derived stock,
category-review cases, and user-requested approval require confirmation; missing
facts or ambiguous items require clarification. The AI calls the backend's
allowlisted business services, which validate and authorize inventory changes.

The maintained API contracts and exact endpoint behaviour are documented in
[the API reference](docs/reference/API_REFERENCE.md). Current product scope is documented
in [the project scope](docs/product/README.md).

## Mobile capabilities and user value

| Capability | How it supports the user | Implementation and verification |
| --- | --- | --- |
| Camera and photo library | Capture food or purchase images, preview/remove photos, and review proposed stock before saving. This reduces typing while retaining control over quantities and storage. | Camera/image-picker input and shared review UI; [Mobile guide](mobile/README.md#interaction-and-state), [multimodal test report](docs/testing/reports/AGENT_MULTIMODAL_TEST_RESULTS.md). |
| Speech and touch gestures | Hold to speak while shopping or cooking, release to edit the transcript, slide up to cancel, and send explicitly. Speech recognition supplies editable text to the assistant. | Shared `AgentInputPanel`; [Mobile interaction guide](mobile/README.md#interaction-and-state). |
| Local notifications | Surface expired/upcoming stock and check-in reminders, with per-user settings and permission handling. | [Profile and reminders](mobile/README.md#profile-and-reminders); [manual integration record](docs/testing/reports/MANUAL_INTEGRATION_TEST_RECORD.md). |

Android permission, camera, microphone, and notification behavior must be checked
on a device or emulator; widget tests and the Flutter browser build do not establish
native acceptance. The selected APK/device results belong in the
[Final Acceptance Record](docs/testing/reports/FINAL_ACCEPTANCE.md#manual-cross-client-and-android-validation).

## Technology stack and architecture

The hosting labels below describe the original course deployment. For personal
deployment, configure your own Render/Vercel projects, database and model access.

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Mobile | Flutter / Dart | Android-focused user experience, camera/image/voice input, and mobile inventory workflows. |
| Web | React, TypeScript, Vite, React Router, TanStack Query | Desktop user and administrator workflows. |
| Backend | FastAPI, Pydantic, SQLAlchemy 2.x, Alembic | Versioned REST/SSE API, authentication, validation, business rules, and transactions. |
| Agent | LangGraph and an OpenAI-compatible model API | Interprets user requests and proposes or executes allowlisted inventory actions. |
| Database | PostgreSQL hosted on Neon | Persistent users, storage spaces, catalogue, inventory, operation, and Agent state. |
| Hosting | Render and Vercel | Render serves React/Flutter Web; Vercel runs FastAPI. Android calls the same API directly. |
| CI | GitHub Actions with disposable PostgreSQL | Backend/Web/Flutter fast checks, conditional browser E2E and manual full regression. |

```mermaid
flowchart LR
    Android[Flutter Android] -->|HTTPS REST / SSE| API["FastAPI (including LangGraph Agent)<br/>Hosted on Vercel"]
    MobileWeb[Flutter Web on Render] -->|HTTPS REST / SSE| API
    Web[React Web on Render] -->|HTTPS REST / SSE| API
    API --> Services[Validated business services]
    Services -->|SQLAlchemy / psycopg| DB[(Neon PostgreSQL)]
    API --> Agent[LangGraph workflow]
    Agent --> Services
    Agent -->|HTTPS model API| AI[OpenAI-compatible service]
    Agent -->|Checkpoints and user memory| DB
    CI[GitHub Actions] --> TestDB[(Disposable PostgreSQL)]
```

The browser clients never connect directly to PostgreSQL or the model service.
FastAPI derives the user identity from the bearer token and applies ownership
and role checks before database access. Runtime database traffic uses the Neon
pooled connection; Alembic and setup operations use a direct connection.

### Architecture decisions and tradeoffs

| Choice | Reason and tradeoff |
| --- | --- |
| One modular FastAPI backend | Both clients share validation, authorization, and quantity rules. Routers, schemas, services, and persistence have separate responsibilities without the operational cost of microservices. |
| REST/JSON for inventory resources | HTTP methods, status codes, and generated OpenAPI contracts make integration explicit for both clients. The current resource workflows do not require GraphQL's flexible query layer. |
| Authenticated POST with SSE for assistant replies | Sends prompts/images and streams text, proposals, and results incrementally. Confirmation resumes through a later request; continuous two-way WebSocket sessions are unnecessary for this interaction. |
| PostgreSQL transactions, version checks, and idempotency | Prevent partial manual batches, lost updates, and duplicate quantity changes when requests are retried. Database-backed receipts and sessions work across backend instances. |
| LangGraph checkpoints plus business receipts | Checkpoints restore questions and drafts; receipts establish whether a write committed. Recovery checks both so interrupted replies do not duplicate inventory changes. |
| Pooled runtime connections and direct session connections | Pooling bounds ordinary query connections. Migrations, Agent persistence, and session-level advisory locks use direct connections where session identity matters. |

The [architecture guide](docs/architecture/README.md) records alternatives and
capacity assumptions. The initial workload is 100 users and 5 requests/second
with 50,000 inventory batches and 500,000 operations. The dated
[performance record](docs/testing/records/PERFORMANCE_TEST_RECORD.md) reports
3,000 successful requests in the local 10-minute baseline and 120 successful
hosted reads on 4 October 2026; it also retains a provider rate-limit failure
in one of ten real-model samples. These results describe the tested environments
and revisions. Further scaling requires measuring query, connection, and lock
pressure before changing pool sizes, indexes, or instance counts.

Additional learning in persistent AI workflows, multimodal validation, rotating
sessions, cloud database connections, and realistic browser testing is explained
in [Learning and Design Evolution](docs/learning/README.md), with code and test
evidence for each technique's contribution to the product.

## Documentation and historical evidence

| Topic | Entry point |
| --- | --- |
| Product and quantity rules | [Product scope](docs/product/README.md), [quantity-state design](docs/architecture/QUANTITY_STATE_DESIGN.md) |
| Architecture and API | [Architecture](docs/architecture/README.md), [Backend design](docs/architecture/BACKEND_DESIGN.md), [API reference](docs/reference/API_REFERENCE.md) |
| AI workflow | [Agent design](docs/architecture/AGENT_DESIGN.md), [client integration](docs/reference/AGENT_FRONTEND_INTEGRATION.md) |
| Testing and learning | [Test strategy and records](docs/testing/README.md), [design evolution](docs/learning/README.md) |
| Security and deployment | [Security](docs/security/README.md), [deployment guide](docs/delivery/README.md) |
| Original course evidence | [Acceptance record](docs/testing/reports/FINAL_ACCEPTANCE.md), [archived designs](docs/archive/README.md) |
| Personal publication | [Privacy, links and asset review](docs/maintenance/PUBLICATION_REVIEW.md) |

The reports document the original course work. They do not represent a new
regression run or deployment of this personal copy. Their recorded results and
unfinished fields are retained as found in the copied revision.

## Run your own instance

Use your own local PostgreSQL database or Neon project, an independent JWT secret,
and your own model-provider configuration. The local setup below does not need
team demonstration credentials. Register a local user through the application;
optional demo seeding is described in the [deployment guide](docs/delivery/README.md#optional-demo-data).

The original team URLs in older guides and reports identify course infrastructure.
They are not personal demo endpoints. Personal deployments need their own API URL,
browser CORS origins, database credentials and hosting project settings.

### Suggested local walkthrough

1. Start the Backend and React client, then register an ordinary account.
2. Create a storage space, add an item and record consumption or a stocktake.
3. Run Flutter against the same Backend and check that the saved data agrees.
4. Configure a model provider to try the assistant, photo review and speech input.
5. Run the automated checks and use the manual integration cases for device testing.

## Repository layout

```text
backend/   FastAPI application, migrations, setup scripts, and pytest suite
web/       React/TypeScript web application and Vitest suite
mobile/    Flutter Android/Web application and Flutter tests
docs/      Architecture, API, database, design, and test documentation
.github/   GitHub Actions workflows
```

## Local development prerequisites

- Git
- Python 3.12
- Node.js 22 and npm
- Flutter 3.44.8 with Dart 3.12.2
- Android Studio / Android SDK for Android development
- PostgreSQL, or a Neon PostgreSQL project with pooled and direct connection
  strings

Python 3.12 matches the Backend README and GitHub Actions environment. Commands
below use Bash unless labelled PowerShell; start each component in a separate
terminal. Clone the personal repository, then work from its root:

```bash
git clone https://github.com/syan349/sayfridge.git
cd sayfridge
```

An existing checkout can keep its current directory name.

Real credentials belong only in ignored local environment files or deployment
secret managers. Never commit `.env`, `.env.test`, database passwords, JWT
secrets, or model API keys.

## Run the Backend

From the repository root:

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

On Windows, use this setup instead:

```powershell
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `backend/.env` and set at least:

- `DATABASE_URL`: pooled PostgreSQL URL used by FastAPI;
- `DATABASE_URL_DIRECT`: direct PostgreSQL URL used by Alembic;
- `JWT_SECRET_KEY`: a random secret of at least 32 characters;
- `CORS_ORIGINS`: for local clients, `["http://localhost:5173", "http://localhost:5174"]`; and
- `AGENT_API_KEY` plus the other `AGENT_*` settings when using the Agent.

Both database URLs use the `postgresql+psycopg://` prefix. Initialise and verify
all business tables, the public category catalog, and Agent persistence from
`backend/`:

```bash
python scripts/initialize_database.py
```

The command is safe to repeat and must finish before the API is started against a
fresh database. It does not run implicitly during FastAPI startup. Read
[Agent configuration and storage](backend/README.md#agent-configuration-and-storage)
for the separate inspection and repair commands used with existing databases.

Start the API:

```bash
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Local health and API documentation are then available at:

- <http://127.0.0.1:8000/health>
- <http://127.0.0.1:8000/docs>

Windows setup and additional database details are in the
[Backend README](backend/README.md).

## Run the React Web application

Start the Backend first, then open a second terminal:

```bash
cd web
npm ci
npm run dev
```

Open <http://localhost:5173>. During local development, Vite proxies `/api`
requests to `http://127.0.0.1:8000`. For a deployed build, set
`VITE_API_BASE_URL` to the HTTPS Backend URL including `/api/v1` before running
the build. `VITE_*` values are compiled into browser JavaScript and must never
contain secrets.

See the [Web README](web/README.md) for routes and deployment behaviour.

## Run the Flutter application

Install Flutter and an Android emulator or connect an Android device:

```bash
cd mobile
flutter pub get --enforce-lockfile
flutter run -t lib/main.dart \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`10.0.2.2` is the Android emulator address for the host machine. A physical
device must use an API address reachable from that device. To run the Flutter
Web build locally against the Backend:

```bash
flutter run -d chrome --web-port=5174 -t lib/main.dart \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Add `http://localhost:5174` to the Backend `CORS_ORIGINS` while using this local
browser configuration. See the [Mobile README](mobile/README.md) for Android,
Web, preview, and deployment details.

### Build and install the Android app

From `mobile/`, set your own hosted API URL and build the native app:

```bash
export PERSONAL_API_BASE_URL="https://YOUR-BACKEND-HOST/api/v1"
flutter build apk --release -t lib/main.dart \
  --dart-define=API_BASE_URL="$PERSONAL_API_BASE_URL"
adb devices
adb -s YOUR_DEVICE_ID install -r build/app/outputs/flutter-apk/app-release.apk
```

The output is `mobile/build/app/outputs/flutter-apk/app-release.apk`. You can also
transfer it to Android and install it after allowing installation from that source.
The course build uses the current debug signing configuration for sideloading;
it is not a store-signed release. Publish any distributable APK as a
GitHub Release asset in this personal repository,
with its commit and checksum, rather than committing build output. Device results
and the selected artifact belong in the final acceptance record.

## Run the tests

See the [testing guide and CI policy](docs/testing/README.md) for automated
checks, test scope, and result artifacts. Every PR runs Backend core checks
and the Web/Flutter fast checks. Web lint and Flutter analyze are local checks;
the current frontend workflow runs tests plus Web typecheck/build.

GitHub Actions is the automated entry point: [Core E2E](.github/workflows/core-e2e.yml)
coordinates reusable Backend and Frontend fast checks on every PR. For one
complete automated regression of the same commit, use **Actions →
[Full Regression](.github/workflows/full-regression.yml) → Run workflow**.
It runs the offline Backend suite, all selected Web/Flutter tests and core E2E,
then publishes the aggregate result and commit SHA. See the
[full regression guide](docs/testing/README.md#unified-full-regression).

### Backend

Backend database tests require a direct connection to an isolated PostgreSQL
database whose name ends in `_test`. Copy the template and replace its
placeholders locally:

```bash
cd backend
cp .env.test.example .env.test
python -m pytest -v
```

Useful selections:

```bash
python -m pytest -v -m ci --strict-markers  # fast CI regression
python -m pytest -v -m postgres             # PostgreSQL-backed tests
```

The test fixtures migrate a random schema per database test and remove it after
the test. GitHub Actions supplies a disposable PostgreSQL service and does not
use Neon credentials. Live model tests are opt-in because they consume an API:

```bash
AGENT_LIVE_MODEL=1 python -m pytest -q tests/test_agent_live_model.py
```

### React Web

```bash
cd web
npm ci
npm run lint
npm test
npm run build
```

Vitest and Testing Library use MSW-controlled API responses and do not contact a
deployed Backend.

### Flutter

```bash
cd mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test --exclude-tags manual_preview
flutter build web --release --no-web-resources-cdn \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

### End-to-end acceptance

The [Core E2E guide](docs/testing/README.md#core-e2e) describes the
isolated Playwright/Web/Backend/PostgreSQL environment, eight browser scenarios,
and PR path gates with manual dispatch. After the one-time setup, run from the repository root:

```bash
python backend/scripts/run_e2e.py
```

The automated suite covers authentication, spaces, stock entry, editing/moving,
consumption/history, reconciliation, archival and ownership/admin boundaries.
Deployment order, main revision checks, Neon migration/seed, Android APK build and
installation, and deployed acceptance commands are maintained in
[Build and Deployment](docs/delivery/README.md). Publish APKs as release assets;
keep generated binaries out of source control.

Feature reports and raw results are indexed in the [testing guide](docs/testing/README.md#reports).
The [performance record](docs/testing/records/PERFORMANCE_TEST_RECORD.md) and
[manual integration record](docs/testing/reports/MANUAL_INTEGRATION_TEST_RECORD.md)
retain measured outcomes and development findings. Offline tests, live-model
checks, and native/deployed acceptance have distinct scopes; results from different
selections or revisions are not added together as one release total.

## Original team contributors

| Member | Account | Primary contribution area |
| --- | --- | --- |
| syan349 | `syan349` | Backend business APIs, inventory/storage/catalog services, database integration, and Backend testing |
| weizhou537 | `wzho537` | Flutter state, authentication, inventory/API integration, image/voice functionality, and Mobile/integration testing |
| UQwinder | `qche584` | Flutter UI/UX, Home/Profile, navigation, assistant interaction, and Mobile presentation/deployment integration |
| DaryaRastegar | `dras728` | React user/admin interfaces, Web API integration, components, and frontend testing |
| hrainy | `rhan637` | Architecture, database schema/migrations, authentication foundation, AI workflow/persistence, and Agent testing |

The source project is [Team Appix's course repository](https://github.com/UOA-CS734-S2-2026/project-implementation-appix).
Its Wiki and review records belong to that repository and depend on its access
settings. This personal copy retains contributor handles and the rewritten commit
history. Contributor confirmation to adopt AGPL-3.0-only is recorded below.
Artwork sources and remaining material checks are listed in the
[publication review](docs/maintenance/PUBLICATION_REVIEW.md#licensing-and-material-sources).

For new work, use focused branches, tests and reviewed changes. Keep dependencies,
build output, private configuration and credentials outside source control.

## Privacy and security

Passwords are hashed with Argon2. Short-lived access JWTs and rotating, revocable
refresh sessions support continued login; Mobile uses secure token storage and
Web uses memory/session storage. Every protected API checks current account/session
state, resource ownership, and relevant administrator permissions. Clients receive
neither database credentials nor model API keys.

Input validation, image limits/metadata removal, parameterized ORM access, sanitized
errors/logging, version checks, and idempotent writes address documented API and
data risks. The [Security and Privacy guide](docs/security/README.md) maps relevant
OWASP risks to controls, findings, fixes, and dated tests/audits. See also the
[authentication lifecycle](backend/README.md#persistent-login).

Assistant text, submitted images, and relevant inventory context may be processed
by the configured model provider. Conversation checkpoints can retain messages
and images. Speech recognition produces editable text on the client; the Backend
does not accept raw audio. Archive/discard retains inventory history, and there is
no complete self-service account/data deletion workflow. Use synthetic data for
shared demonstrations and keep instance credentials in ignored environment files
or the hosting secret store. Provider/storage/retention details and the manual removal
procedure are in the security guide.

## Current scope and limitations

- Inventory belongs to one account; shared household inventory and nested spaces
  are outside the delivered scope.
- Native reminders are local. Browser notifications depend on permission and the
  application being open; there is no server push service.
- Profile/reminder preferences are local per user and are not synchronized through
  the Backend. Email/password changes and complete account deletion have no API.
- Model-assisted operations need provider access and can encounter network or
  provider limits; clients retain pending work for explicit recovery.
- Android is the native assessment target. Flutter Web demonstrates the shared UI;
  the repository does not claim final iOS device acceptance.
- No personal release has been validated yet. The [retained acceptance record](docs/testing/reports/FINAL_ACCEPTANCE.md)
  describes course revisions; create a dated record for each future personal release.

See [Product Scope](docs/product/README.md#scope-boundaries) for the full boundary
and [Build and Deployment](docs/delivery/README.md) for final release preparation.

## Licensing and materials

Copyright (C) 2026 SayFridge contributors.

The project's original source code and documentation are licensed under the
**GNU Affero General Public License, version 3 only** (`AGPL-3.0-only`). See
[LICENSE](LICENSE) for the full terms. The maintainer obtained contributor
confirmation to adopt this license on 2 November 2026.

The maintainer identifies the avatars and team image as original team work made
with AI assistance. Artwork provenance and third-party material terms are recorded
separately in the [publication review](docs/maintenance/PUBLICATION_REVIEW.md#licensing-and-material-sources).
Third-party dependencies and materials retain their own notices and terms.
