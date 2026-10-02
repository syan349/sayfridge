# Agent multimodal verification — 2026-09-26

Tested the working-tree changes on baseline `6e59b51`, using Python 3.11.2,
Pillow 12.3.0 and an isolated PostgreSQL 16 cluster bound to 127.0.0.1:55439.
The database was `multimodal_test`, with UTC timezone and disposable schemas.
No production inventory or remote schema was changed.

## Results

| Check | Result |
| --- | --- |
| Full backend regression, live-model opt-in disabled | 582 passed, 8 skipped; 598.98 seconds |
| Final Agent regression after supplement/overflow/context-policy fixes | 31 passed |
| Real configured model: synthetic image plus forced tool call | Recognized MILK and count 2 |
| Opt-in multimodal model acceptance | 6 passed; 51.19 seconds |
| Syntax, OpenAPI generation, diff whitespace | Passed |

The full run collected 590 cases. One additional supplement-policy regression was
added afterwards; current collection is 591. The final 31-case run covers the last
workflow adjustments and that new test. Groups overlap and must not be added as
a unique-test total. The 8 skipped cases are 2 existing text live-model checks
and 6 multimodal live-model checks, which require explicit opt-in. The six new
multimodal cases were subsequently run separately with opt-in enabled.

The first image-model run passed 5 cases and failed the last because LangChain's
cached HTTP client was reused across closed per-test event loops. The test harness
now keeps its parameterized live-model cases on one event loop; all 6 passed on
rerun. An early overflow unit test found a missing FINISH routing edge; this was
fixed before the full-suite run.

## Behaviors checked

- Text-only request fingerprints remain compatible; image content/order/type are
  included in new request fingerprints. Image-only input and image-only replies
  are accepted; empty messages without attachments are rejected.
- JPEG/PNG/WebP validation, corrupt input, mismatched types, animated PNG,
  excessive dimensions, aggregate size, duplicate IDs and chunked body limits.
- Image-only uploads and visual questions produce no inventory writes in live
  model tests. Single goods, multiple goods, receipts and two views of one object
  produce reviewable new-stock proposals, then create the expected batch count.
- Model omission of image references cannot disable review for creation when
  images remain visible. Unknown source references and unsupported image actions
  are rejected. Backend execution rechecks review even if a preview flag is wrong.
- A text follow-up can use an earlier photo; supplemental images replace the
  proposal and reject stale confirmation. Image supplements cannot keep the old
  text-only action permissions when the model emits no replacement proposal.
- Real PostgreSQL checkpoints restore images after graph reconstruction. A
  simulated crash after stock commit but before checkpoint completion recovers
  using the execution receipt without creating another batch.
- Repeated chat/resume submissions do not duplicate stock. Other users cannot
  read/resume the conversation. Validation errors, public state, SSE and action
  receipts do not contain original image base64 data.
- Model-reported overflow never executes an accepted partial set. Existing
  unresolved commit outcomes remain recoverable rather than being cancelled.
- Completing a visual question does not permanently restrict later unrelated
  text operations; historical images still force review for new stock.

## Reproduction

Set TEST_DATABASE_URL to a separately managed PostgreSQL `_test` database first.
Do not use the application database. From `backend/`:

```powershell
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_messages.py tests/test_agent_multimodal_workflow.py tests/test_agent_multimodal_postgres.py tests/test_agent_workflow.py tests/test_agent_memory.py tests/test_agent_api_postgres.py tests/test_agent_actions_postgres.py
$env:AGENT_LIVE_MODEL='1'
.\.venv\Scripts\python.exe -m pytest -q tests/test_agent_multimodal_live.py
```

## Remaining product acceptance

Live-model fixtures are generated, readable labels and a synthetic receipt. These
verify the model/API workflow, quantities, review and actual writes; they are not
a recognition-accuracy benchmark for real camera photos, blur, glare, handwriting,
occlusion or long receipts. Real-device/photo acceptance and frontend integration
remain frontend/product follow-up work. No Web/Flutter page or production
deployment was changed. Historical image context growth and checkpoint storage
remain bounded by deployment resources rather than automatic image expiry.
