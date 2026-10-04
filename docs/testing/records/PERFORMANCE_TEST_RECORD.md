# Performance Test Record

**Recorded runs: 2026-09-29 and 2026-10-04.** Tests cover hosted latency,
Backend load, concurrent writes, authentication and real-model Agent responses.

[Testing Strategy and Evidence](../README.md#performance-record)
· [Final Acceptance Record](../reports/FINAL_ACCEPTANCE.md)
· [Performance targets](../../architecture/README.md#capacity-assumptions-and-scaling)

## Case index

| Case | Date | Scenario | Result |
| --- | --- | --- | --- |
| PT-01 | 2026-09-29 | Hosted latency before/after region alignment | Inventory reads: 1.295–1.499s → 0.196–0.277s |
| PT-02 | 2026-10-04 | Large-data REST load | PASS; 3,000 requests, 0 errors, 0 dropped arrivals |
| PT-03 | 2026-10-04 | Concurrent inventory writes | PASS; same-item conflict and separate-item writes |
| PT-04 | 2026-10-04 | Login and session renewal | PASS; 10 login and 10 refresh requests |
| PT-05 | 2026-10-04 | Hosted Vercel/Neon reads | PASS; 120 reads, 0 errors |
| PT-06 | 2026-10-04 | Real-model Agent workflows | 9/10 expected outcomes; 1 provider rate-limit error |

## Run details

| Field | Recorded value |
| --- | --- |
| September Backend commit | `d1f5cdbba0e4f573dd88f3ba9829f2abbaca458c` |
| October local Backend commit | `a370559786f5305a36b0f48d729792451c38eaff` |
| October hosted Backend commit | `e538779976a46e1a218c8e4d59bbbaeb374fa9b3` |
| October source verification | Local and hosted Backend trees match; [source manifest](../../../backend/tests/performance/evidence/2026-10-04-a370559/code-provenance.json) |
| October execution | 14:07:46–14:21:25 NZDT (UTC+13); syan349 |
| Local environment | macOS 26.2, Apple M5, 10 CPUs, 24 GiB RAM; Python 3.12.14; one Uvicorn worker; Docker PostgreSQL 18.6 |
| Hosted environment | HTTPS from Auckland to Vercel and Neon; `https://sayfridge-backend-preview.vercel.app` |
| Timing | REST: request start to full response receipt; p95: nearest rank, excluding setup and warm-up |

## Test cases

### PT-01 — Hosted latency and region alignment

**Setup:** existing hosted stock; Backend commit `d1f5cdb`. Vercel initially ran
in `iad1` (US East), with Neon in Sydney.

**Steps:** measure health, login, inventory, expiry and two read-only Agent prompts;
deploy the same commit to `syd1` (Sydney), verify the function region and repeat.

**Observation:** all recorded REST requests returned HTTP 200. Each inventory
and expiry comparison contains three reads. Each Agent comparison contains one
request per prompt; both streams reached `done`.

| Measurement | Initial `iad1` | Final `syd1` |
| --- | --- | --- |
| Health, three requests | 4.811, 0.393, 0.438s | 0.665, 0.465, 0.524s |
| Login, one request | 5.170s | 0.571s |
| Inventory reads | 1.295–1.499s | 0.196–0.277s |
| Expiry reads | 1.327–1.387s | 0.208–0.448s |
| Agent greeting, first text / stream closed | 12.897 / 14.286s | 6.195 / 6.216s |
| Agent inventory read, first text / stream closed | 14.799 / 15.902s | 6.911 / 7.015s |

The initial health request was slower than subsequent requests. Runtime cold-start
telemetry was not collected. An intermediate redeployment retained `iad1`;
the final deployment verified `syd1`.

**Evidence:** [dated timings, including the intermediate deployment](../../../backend/tests/performance/evidence/2026-09-29-d1f5cdb/hosted-latency-extract.txt).

### PT-02 — Large-data REST load

**Setup:** disposable local schemas with 100 users, 100 spaces, 50,000 inventory
batches and 500,000 operations. One user owns 20,000 batches; 10 users participate.

**Steps:** warm up for 120 seconds; run 5 requests/second for 600 seconds with
80% reads and 20% writes. Read inventory, detail, history and expiry; write
consumption, additions, reconciliation and stock entry. Check responses and final balances.

**Expected:** read p95 ≤500ms; write p95 ≤1,000ms; errors <1%; no dropped arrivals;
correct persisted quantities and versions.

**Observation:** 3,000 requests completed at 5 RPS. Read p95 was **37.64ms**;
write p95 was **30.23ms**; errors and dropped arrivals were **0**. All response
assertions and 10 final batch balance/version checks passed. Maximum concurrent
requests: 2. Global operation history was the slowest endpoint (p95 **215.79ms**).
Database samples every 2 seconds observed at most 4 business connections and
0 lock waiters. Both temporary schemas were removed; Backend source was unchanged.

**Evidence:** [results and environment](../../../backend/tests/performance/evidence/2026-10-04-a370559/local-results.json),
[individual requests](../../../backend/tests/performance/evidence/2026-10-04-a370559/requests.jsonl),
[database samples](../../../backend/tests/performance/evidence/2026-10-04-a370559/db-observations.json).

### PT-03 — Concurrent inventory writes

**Steps:** submit two edits with the same item/version; then write to two separate
items in the same space.

**Expected:** one same-version edit commits and the other returns 409;
separate-item writes both commit.

**Observation:** same-item responses were 200 and 409, with one version increment.
Separate-item writes both returned 200. The deliberate conflict is counted separately
from PT-02 errors.

**Evidence:** [contention results](../../../backend/tests/performance/evidence/2026-10-04-a370559/local-results.json).

### PT-04 — Login and session renewal

**Steps:** measure 10 serial local logins and 10 refresh requests.

**Expected:** successful authentication and session renewal.

**Observation:** all requests passed; login p95 **143.51ms**, refresh p95 **10.90ms**.

**Evidence:** [authentication results](../../../backend/tests/performance/evidence/2026-10-04-a370559/local-results.json).

### PT-05 — Hosted Vercel/Neon reads

**Setup:** `ben.demo`, with 3 in-stock batches; 14:10:08–14:12:21 NZDT on October 4.

**Steps:** log in; warm up six endpoints; perform 20 reads per endpoint with
starts at least one second apart; log out. Read inventory lists, search, space
filters, details, operation history and expiry summaries.

**Expected:** successful authenticated reads and logout.

**Observation:** 120 reads completed with 0 errors; p50 **80.62ms**, p95 **154.61ms**,
maximum **218.74ms**. Login returned 200 in **1,675.10ms**; logout returned 204.
The hosted dataset contains 3 batches; PT-02's large-data load ran locally.

**Evidence:** [hosted request timings and logout](../../../backend/tests/performance/evidence/2026-10-04-a370559/hosted-results.json).

### PT-06 — Real-model Agent workflows

**Setup:** local Backend and isolated dataset; model `gpt-6-luna`; test user owns
303 batches. Each request starts a fresh conversation.

**Steps:** send 10 serial requests covering clarification, inventory reads,
consumption and stock entry. Measure first content and completion; verify saved writes.

**Expected:** clarification asks for missing input; reads complete; writes persist;
streams finish without an error. First content excludes `start` and heartbeat events.

**Observation:** 9/10 expected outcomes. All four consumption/stock-entry writes
persisted correctly. Successful completion took **6.74–12.98s**, with median
**8.08s**. Request 10 returned HTTP 200 followed by SSE `rate_limit_exceeded`
after **4.174s**, without a `done` event. Clarification follow-up replies were not
part of this run.

**Follow-up:** check provider quota and repeat the failed scenario with pacing.
The harness exit code checks REST load and cleanup; this Agent failure is recorded separately.

**Evidence:** [all 10 samples](../../../backend/tests/performance/evidence/2026-10-04-a370559/agent-samples.json),
[Backend log](../../../backend/tests/performance/evidence/2026-10-04-a370559/backend.txt).

## Evidence and rerun

Detailed timings, package versions and configuration remain in the linked files.
Additional records: [migration setup](../../../backend/tests/performance/evidence/2026-10-04-a370559/initialize.txt)
and [Docker environment](../../../backend/tests/performance/evidence/2026-10-04-a370559/docker-environment.json).

From the repository root, use the Backend Python environment and a new output
folder. Local PostgreSQL must be running; `backend/.env.e2e` must select a loopback
database ending `_e2e`. Model settings come from ignored `backend/.env`.

```bash
python backend/scripts/performance/run_performance.py \
  --root "$PWD" --output /tmp/sayfridge-performance-new-run \
  --warmup 120 --duration 600 --rps 5 --agent-samples 10
```

Hosted reruns use the demo credentials in ignored `backend/.env.demo`:

```bash
python backend/scripts/performance/run_hosted_reads.py \
  --root "$PWD" --output /tmp/sayfridge-hosted-performance-new-run
```

For later runs, record the date, commit, environment, workload, result and evidence
folder. Link the selected release run from the Final Acceptance Record.
