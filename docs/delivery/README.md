# Build and Deployment

This is the current delivery runbook for Render clients, Vercel Backend, Neon
and Android APKs. Deploy selected, verified commits from `main`. Neon stores
schema/data rather than a Git branch: apply the migrations associated with the
selected code commit. Do not reset shared data to update application code.

## Release selection and order

```bash
git switch main
git pull --ff-only origin main
git status --short
RELEASE_SHA=$(git rev-parse HEAD)
```

Use a clean checkout and record the SHA. Run Full Regression against that commit.
Deployment order is database migration/verification → Backend → browser clients
→ smoke and cross-client acceptance. If main changes during the release, keep
the selected SHA or choose a new one and repeat the applicable checks.

## Platform configuration

| Component | Source/build | Configuration |
| --- | --- | --- |
| React Web / Render | main, root `web`, `npm ci && npm run build`, publish `dist` | `VITE_API_BASE_URL=https://sayfridge-backend-preview.vercel.app/api/v1` |
| Flutter Web / Render | main, root `mobile`, `bash scripts/render-build.sh`, publish `build/web` | `API_BASE_URL=https://sayfridge-backend-preview.vercel.app/api/v1`; script pins Flutter 3.44.8 |
| Backend / Vercel | selected main snapshot, deploy from `backend` | Runtime pooled DATABASE_URL, direct DATABASE_URL_DIRECT, JWT/model secrets, exact CORS origins |
| Neon | business and Agent schemas | Same selected database/branch for backend runtime, direct migration and Agent persistence |
| Android | selected main commit, `lib/main.dart` | Compile-time API_BASE_URL ending `/api/v1` |

Both Render static sites require SPA rewrite `/*` → `/index.html` (200).
Build-time client API URLs are public; database passwords, JWT keys and model keys
belong only in operator/hosting secret stores. API origins contain no database URL.
The Flutter integration site also uses main under the current deployment policy;
confirm that source setting in Render before release.

Vercel runtime and Neon should use the same region where available. Verify the
configured function and database regions in platform settings rather than inferring
them from a project name. Region and cold/warm state belong in performance evidence.
CORS includes the exact React/Flutter browser origins with no path or wildcard.
Native Android does not use browser CORS. AGENT_DATABASE_URL is optional: the
Agent falls back to DATABASE_URL_DIRECT when it is absent.

## Database initialization and migration

Run from `backend/` with ignored operator environment configuration. First confirm
the intended direct database endpoint without printing its password.

For a new environment:

```bash
python scripts/initialize_database.py
```

For an existing database:

```bash
python -m alembic current
python -m alembic heads
python -m alembic upgrade head
python -m alembic check
python scripts/verify_database_schema.py
python scripts/setup_agent_storage.py --check
```

`alembic check` verifies ORM/migration drift; the schema verifier checks actual
business objects. If Agent storage is absent, explicitly initialize it with
`python scripts/setup_agent_storage.py --initialize` after reviewing the target,
then rerun `--check`. Application startup performs no schema creation.

| Operation | Purpose |
| --- | --- |
| Migration | Apply ordered structural changes while retaining existing data |
| Required seed | Initialize the 25 public categories through initialize_database.py |
| Demo seed | Explicitly add deterministic non-production demonstration data |
| Demo reset | Remove eligible deterministic demo rows, retaining unrelated data/schema |
| Restore | Operator recovery from an approved Neon restore point or backup |

### Persistent-login migration

`a261001_sessions` follows `a260929_defaults` and adds auth_session and
auth_refresh_credential. Apply all outstanding migrations before deploying code
that uses sessions. Existing accounts and inventory remain; users sign in again
to obtain refresh sessions. Use `alembic heads` for the selected revision rather
than treating a documented revision as permanently current.

If migration fails, stop the release, inspect its error and current revision, and
resolve the target/configuration before retrying. Do not stamp a failed upgrade as
complete or drop tables to force success. A compatible earlier Backend can be
restored while investigating; additive session tables need not be removed.

### Optional demo data

The deterministic dataset contains 11 accounts, 33 spaces, 25 public definitions,
77 inventory items and 66 operations. It covers exact/estimated balances, states,
expiry, notes and quantity history. Use it only for an explicitly selected
non-production target. Real passwords belong in a private team channel.

```bash
export DEMO_USER_PASSWORD='replace-with-shared-demo-user-password'
export DEMO_ADMIN_PASSWORD='replace-with-shared-demo-admin-password'
python scripts/manage_demo_data.py seed --target predeploy --confirm SEED-DEMO-DATA
python scripts/manage_demo_data.py check --target predeploy
```

Repeat seed preserves compatible existing accounts. Add `--rotate-passwords` to
seed to update deterministic demo credentials without deleting their inventory.
Reset requires a different explicit confirmation:

```bash
python scripts/manage_demo_data.py reset --target predeploy --confirm RESET-DEMO-DATA
```

Reset preserves pre-existing accounts/definitions and seeded accounts that have
acquired non-demo dependent data. Restore and reset serve different purposes.

## Vercel deployment

Use an authenticated operator account with access to `appix2`. Run from the
selected Backend checkout/snapshot, with Node.js 22:

```bash
npx vercel login
npx vercel link --project sayfridge-backend-preview --scope appix2
npx vercel deploy --prod --scope appix2 --env APP_COMMIT_SHA="$RELEASE_SHA"
```

Ensure the linked project deploys this backend directory without a second `backend`
path prefix. CLI login success and project access are separate checks; Not authorized
requires the correct account/team access. Deployment Protection settings must allow
the intended public client/assessor access. A successful build alone is not API acceptance.

Verify the public alias after deployment:

```bash
curl --fail https://sayfridge-backend-preview.vercel.app/health
curl --fail https://sayfridge-backend-preview.vercel.app/api/v1/system/version
```

Match commit_sha to RELEASE_SHA. Inspect platform logs for startup errors without
publishing credentials. Secret changes take effect through a new deployment.

## Render deployment and version checks

Deploy the selected main commit for each configured static site. Confirm API build
variables, publish directories and SPA rewrites before triggering the build.
Flutter Web exposes `/build-info.json` with commit and UTC build time. For React,
record the deployed commit from Render's deployment details. Verify direct navigation
and reload on inventory/expiry/admin routes, then perform authenticated actions.
The archived [Render setup notes](../archive/deployment/RENDER_DEPLOY.md) preserve
earlier branch/Safari investigations; use this runbook for current release settings.

## Android APK build and installation

Run from `mobile/` at the selected main commit:

```bash
flutter pub get --enforce-lockfile
flutter build apk --release -t lib/main.dart \
  --dart-define=API_BASE_URL=https://sayfridge-backend-preview.vercel.app/api/v1
```

Output: `mobile/build/app/outputs/flutter-apk/app-release.apk` from repository root.
The current Gradle release build uses the debug signing configuration. This supports
course sideloading; record that signing choice with the artifact. A store release
requires a separate protected release key. Do not commit keystores or APK build output.

```bash
adb devices
adb -s YOUR_DEVICE_ID install -r build/app/outputs/flutter-apk/app-release.apk
```

Alternatively, transfer the APK to Android, allow installation from that source
and open it. The app uses Vercel directly and Vercel uses Neon. Device camera,
microphone and notification permissions are tested on Android, separately from
browser/widget tests.

Publish an APK as a GitHub Release asset associated with a tag on the selected
main commit. Include version, commit, API endpoint, signing choice, checksum,
installation instructions and tested device/Android version. Releases attach binary
assets to a tag; they do not store the APK in the branch's source tree. A manual
GitHub Android build workflow is optional; this runbook supports local builds.

## Deployment smoke and acceptance

Run from `backend/` using dedicated ordinary/admin accounts and ignored operator secrets:

```bash
export SMOKE_BASE_URL='https://sayfridge-backend-preview.vercel.app'
export SMOKE_USER_EMAIL='deployment-smoke@example.com'
export SMOKE_USER_PASSWORD='replace-with-dedicated-user-password'
export SMOKE_ADMIN_EMAIL='deployment-smoke-admin@example.com'
export SMOKE_ADMIN_PASSWORD='replace-with-existing-admin-password'
python scripts/smoke_deployment.py
```

The ordinary account is registered on first use; the administrator must already
exist. The runner checks health/version, authentication, stock and expiry, and
administrator queries. It reuses dedicated sample resources, does not delete data
or change roles, and returns nonzero on failure. Runner settings are not Vercel
application variables. Compare the version response with the selected SHA.

Record database acceptance with `scripts/record_database_acceptance.py` (use
`--help` for environment/date/output arguments). Keep the revision, seed check,
schema verification, tested commit and initialization date with the release.

Then test Android stock entry/consumption → React view of the same account/data
→ quantity history and expiry → ordinary/admin permission checks. Include renewal,
network interruption and selected device permissions. Record exact environment,
commit, APK and outcome; link that release evidence from the testing guide. Submit
private acceptance credentials through the course-designated application.
