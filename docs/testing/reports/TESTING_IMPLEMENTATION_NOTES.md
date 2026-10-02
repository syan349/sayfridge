# Recorded Testing Notes

These notes retain their original dates and execution results. Current commands
and workflow selections are maintained in the [testing guide](../README.md).

## Stock category, quantity and expiry acceptance

`test_inventory_expiry.py` covers date precedence, production/opening starting
dates, model output validation, mixed batch failures and unavailable estimation.
`test_agent_stock_policy_postgres.py` uses disposable migrated schemas to verify
private/public classification conflicts, HTTP confirmation/cancellation, atomic
rollback, concurrent edits, receipt replay, creation warnings, frozen previews and
persisted apple quantities. These tests are in the Backend `ci` selection.

`test_agent_stock_policy_live.py` requires explicit `AGENT_LIVE_MODEL=1` plus an
isolated `TEST_DATABASE_URL`; it runs English/Chinese yoghurt, apple weight and
category-correction scenarios through actual chat/resume with the configured model.
Normal regression replaces only optional expiry-model calls with an unavailable
estimator. It never spends model tokens or uses the application database for test
writes. Full regression and remote/deployed acceptance remain separate evidence.

Local verification on 2026-10-02 used Python 3.11 and a dedicated PostgreSQL 16
test cluster: the Backend core selection passed **154** tests (714 deselected),
and the new expiry/stock-policy offline suites passed **24** tests. The final
real-model suite plus date unit tests passed **18** tests, including all **6**
live scenarios and production-date shelf-life calculation. The full offline run
initially reported 797 passed, 63 skipped and one failure: an existing batch-archive
test compared a timestamp string with UTC while the temporary database returned
Pacific/Auckland. Setting only that test database to UTC made its focused rerun
pass; no product-code or remote-database change was used to mask the failure.

The configured remote database passed read-only ORM verification (11 tables,
96 columns); its revision was `a261001_sessions`, with 25 active categories and
105 inventory rows. Runtime/direct connection targets matched. This change has
no ORM or migration edits. These checks do not establish the deployed service's
environment configuration or confirm a code deployment.

## Category and schema verification — 2026-09-26

The targeted repair/category/receipt tests passed: **8 passed**. The full 598-test
collection initially reported **588 passed, 8 skipped, 1 failed and 2 errors**
(one error occurred during teardown of an already counted test). All three
exceptions were database connection failures; their targeted reruns passed.
Across these runs all 590 non-skipped cases passed, but the initial run was not
clean. Original interrupted/failed teardown cleanup was not verified.

Development database writes and authenticated development HTTP acceptance were
not performed. Live-model classification evaluation was not performed; deterministic
tests validate database checks and confirmation, not semantic classification accuracy.

### Fixed model-evaluation cases

These are manual/live-model evaluation expectations, not a rule-based classifier or a measured
accuracy claim. Run with a seeded isolated test database and explicit live-model opt-in; record
model/version, date, category result, clarification, and confirmation behavior.

| Input | Expected result |
| --- | --- |
| 鸡胸肉 / chicken breast / frozen chicken | Meat & Poultry |
| canned tomatoes / 罐装番茄 | Vegetables & Mushrooms |
| tomato sauce / 番茄酱 / 老干妈 | Sauces, Condiments & Spreads |
| frozen pizza / 冷冻披萨 | Prepared Meals & Leftovers |
| oat milk / 燕麦奶 | Milk & Plant-Based Milk |
| coconut milk / 椰奶 (no use indicated) | Clarify drinking versus cooking |
| cooking coconut milk | Sauces, Condiments & Spreads |
| Anchor (brand only) | Ask for product identity |
| CHK BRST 500G, user says chicken breast | Meat & Poultry; do not derive stock count from weight |
| XYZ 2.99 (unexplained receipt text) | Ask; do not silently choose Other |
| Greek yoghurt / 希腊酸奶 | Yoghurt |
| tofu / 豆腐 | Tofu & Meat Alternatives |
| dish soap / 洗洁精 | Household Supplies |
| clearly identified item outside catalog | Propose Other and require confirmation |
| existing private definition with user-selected category | Reuse category; do not reclassify |


## Persistent-login validation — 2026-10-01

Local verification used Python 3.12, Node.js 22 and Flutter 3.44.8. PostgreSQL
sessions and browser E2E used isolated local schemas; these checks did not modify
Neon or deploy to hosted platforms.

- Backend fast CI: 90 passed, 679 deselected.
- Ten [Backend session tests](../../../backend/tests/test_persistent_auth.py) passed:
  rotation, hashed storage, replay revocation, logout, independent devices,
  concurrent rotation, inactive accounts, expired access renewal and session deadlines.
- Web: 108 Vitest cases passed; production build passed. Existing lint warning:
  the triple-slash type reference in `vite.config.ts`.
- Flutter: 165 cases passed with `manual_preview` excluded; analyzer reported no issues.
  Tests cover concurrent renewal, offline behavior, server logout, stream authentication
  and offline preview storage isolation.
- Eight Chromium E2E flows passed, including real session renewal and immediate
  access revocation after logout. The first browser run timed out before executing
  business requests; subsequent complete runs passed.

Deploy migration `a261001_sessions` before the new Backend, then update both
frontends. Existing access-only sessions require login again to use persistent login.
