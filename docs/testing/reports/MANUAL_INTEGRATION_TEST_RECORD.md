# Manual Integration Test Record

**Reviewed: 2026-10-03.** This record covers 13 manual integration scenarios across
onboarding, inventory, AI interactions, session renewal and mobile usability.
[Integration tests #139](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/139)
tracks the associated findings and fixes.

[Testing Strategy and Evidence](../README.md#manual-integration-record)
· [Final Acceptance Record](FINAL_ACCEPTANCE.md#manual-cross-client-and-android-validation)
· [Build and Deployment](../../delivery/README.md#deployment-smoke-and-acceptance)

Steps are team-reviewed procedures, including follow-up checks. Observations record
the behavior found during testing; expected results define acceptance. Post-fix
manual retest results have not been entered. Device/build versions and execution
dates are recorded with each confirmed run.

## Case index

The timestamps below identify when findings were logged. Issue track corrective work separately from test outcomes.

| Case | Related issue | Scenario | Finding logged | Reporter | Assigned owner | Issue state |
| --- | --- | --- | --- | --- | --- | --- |
| MT139-01 | [#140](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/140) | New-user default storage onboarding | 2026-10-01 10:53 | weizhou537 | weizhou537 | Closed |
| MT139-02 | [#143](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/143) | Discard expired stock | 2026-10-01 11:27 | syan349 | rhan637 | Open |
| MT139-03 | [#144](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/144) | Agent half-consumption clarification | 2026-10-01 11:33 | syan349 | rhan637 | Open |
| MT139-04 | [#145](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/145) | Apple quantity and units | 2026-10-01 11:36 | syan349 | rhan637 | Closed |
| MT139-05 | [#146](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/146) | Purchase and expiry date picker | 2026-10-01 11:43 | syan349 | UQwinder | Open |
| MT139-06 | [#147](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/147) | Receipt/photo review usability | 2026-10-01 12:08 | syan349 | UQwinder | Open |
| MT139-07 | [#149](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/149) | Session renewal after access expiry | 2026-10-01 12:35 | weizhou537 | syan349 | Closed |
| MT139-08 | [#154](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/154) | Daily Check-in voice and topics | 2026-10-01 15:14 | weizhou537 | weizhou537 | Closed |
| MT139-09 | [#155](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/155) | Choose and identify default space | 2026-10-01 15:20 | syan349 | weizhou537 | Closed |
| MT139-10 | [#157](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/157) | Storage-space isolation on account change | 2026-10-01 15:34 | syan349 | weizhou537 | Closed |
| MT139-11 | [#158](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/158) | Agent classification into existing categories | 2026-10-01 15:37 | syan349 | rhan637 | Closed |
| MT139-12 | [#161](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/161) | Expiry suggestions for new stock | 2026-10-01 16:38 | syan349 | rhan637 | Closed |
| MT139-13 | [#170](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/170) | Reopen Assistant at latest content | 2026-10-02 23:15 | weizhou537 | weizhou537 | Closed |

## Team-reviewed test cases

### MT139-01 — New-user default storage onboarding (#140)

**Setup:** a new ordinary account with no user-created spaces.

**Steps:**

1. Register and sign in.
2. Open Add inventory before creating a custom space.
3. Inspect the selected space, save a valid stock item and reopen inventory.

**Expected:** an active `Default Space` of type `FRIDGE` is available and selected
when it is the only space; the first stock entry succeeds.

**Observation:** new accounts had no default space, blocking first stock entry.
[Finding #140](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/140#issue-5653522619).

**Follow-up:** closed on October 1. The issue records 159 Mobile and 260 Backend
non-database tests passing; PostgreSQL, deployed and manual verification were pending.

### MT139-02 — Discard expired stock (#143)

**Setup:** an in-stock item with an expiry date before the test date.

**Steps:**

1. Find the item through inventory or the expiry view.
2. Open its actions, select Discard and confirm.
3. Reload inventory and inspect the retained record.

**Expected:** an explicit discard action removes the item from active stock and
retains its discarded record. Expiry alone does not delete stock.

**Observation:** there was no explicit discard action; setting quantity to zero
was the removal workaround.
[Finding #143](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/143#issue-5653851824).

**Follow-up:** open; [PR #176](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/pull/176)
references the issue.

### MT139-03 — Agent half-consumption clarification (#144)

**Setup:** one rice batch at 2 kg as repeatable test data.

**Steps:**

1. Send “I consumed half of the rice today” to AI Assistant.
2. Inspect the reply and proposed item/amount; answer any specific clarification.
3. Complete review, then reload the item and operation history.
4. Repeat with multiple matching rice batches to check target clarification.

**Expected:** a single batch produces a 1 kg remaining balance with the correct
unit and one operation. Multiple matches prompt a clear target question.

**Observation:** the reply showed a generic input box without explaining the
missing information.
[Finding and two screenshots #144](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/144#issue-5653899406).

**Follow-up:** open; PR #176 references it. Two
[Backend live-model checks](../evidence/backend-release-readiness/agent-half-consumption-live-2026-10-02.xml)
passed on October 2 for half consumption and clarification/resume, as recorded in
[Backend acceptance](FINAL_ACCEPTANCE.md#backend-release-readiness-verification--2026-10-02).
A manual client retest remains to be recorded.

### MT139-04 — Apple quantity and units (#145)

**Setup:** an ordinary account with an active storage space.

**Steps:**

1. Send “Add 2kg apples” to AI Assistant.
2. Inspect the amount, unit and exact/estimated label.
3. Confirm and compare the saved item with the proposal; reload details.

**Expected:** the 2 kg weight and any estimated item count remain distinct.
Whole-item counts use whole numbers; weight keeps its quantity precision.

**Observation:** the estimated quantity displayed as `18.100`; an integer display
was requested.
[Finding and screenshot #145](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/145#issue-5653928115).

**Follow-up:** closed through [PR #166](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/pull/166)
on October 2. [Stock-policy notes](TESTING_IMPLEMENTATION_NOTES.md#stock-category-quantity-and-expiry-acceptance)
record automated/live-model checks; the native display retest remains to be recorded.

### MT139-05 — Purchase and expiry date picker (#146)

**Setup:** an existing item with editable purchase and expiry dates.

**Steps:**

1. Open Edit and choose Purchase date through the calendar.
2. Choose Expiry date and save.
3. Reopen details to verify both dates; cancel another selection to check preservation.

**Expected:** both fields have a usable date picker; Save persists the dates and
Cancel preserves the previous value.

**Observation:** dates required typed format input without a calendar widget.
[Finding and screenshot #146](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/146#issue-5653983188).

**Follow-up:** open; assigned to UQwinder.

### MT139-06 — Receipt/photo review usability (#147)

**Setup:** a legible receipt with multiple food lines.

**Steps:**

1. Capture or attach the receipt and submit it to AI Assistant.
2. Review recognized items, quantities and spaces.
3. Edit one proposal and confirm eligible items; record repeated confirmation actions.
4. Inspect the saved stock against the approved proposals.

**Expected:** readable cards and explicit controls support review without a typed
“yes” step. Supported batch confirmation preserves per-item editing and unresolved
information review.

**Observation:** receipt entry required typing “yes” followed by individual item
confirmations, repeating work on a long receipt.
[Finding and four screenshots #147](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/147#issue-5654203592).

**Follow-up:** open. [Commit a7d9e70](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/commit/a7d9e70060498637594c38146910adc0aa181f83)
contains item editing and Assistant/photo review improvements.

### MT139-07 — Session renewal after access expiry (#149)

**Setup:** sign in and load protected data; record the configured access expiry.

**Steps:**

1. Log in, then wait beyond the configured access expiry.
2. Open or refresh Inventory and check whether it loads.
3. Press Refresh after a failure and inspect recovery.
4. Check invalid-session handling, concurrent requests and logout as follow-up variants.

**Expected:** access expiry triggers secure renewal and one retry. Invalid sessions
return to sign-in; concurrent requests share renewal and logout revokes the session.

**Observation:** after several minutes, Inventory showed “Invalid or expired access
token”; Refresh did not recover and the app stayed on an authenticated page.
[Finding and reproduction steps #149](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/149#issue-5654439176).

**Follow-up:** closed through [PR #152](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/pull/152)
on October 1. [Persistent-login notes](TESTING_IMPLEMENTATION_NOTES.md#persistent-login-validation--2026-10-01)
record automated Backend, Flutter, Web and browser checks. A manual expiry retest
remains to be recorded.

### MT139-08 — Daily Check-in voice and topic interactions (#154)

**Setup:** an authenticated user on Daily Check-in.

**Steps:**

1. Tap each topic card and inspect its selection and recall prompt.
2. Hold the speech control, speak and release.
3. Review/edit the transcription before sending; repeat with slide-up cancellation.

**Expected:** topics respond with relevant prompts; speech produces editable text
and cancellation sends nothing. Inventory proposals retain user review.

**Observation:** only text input was available; the three topic cards appeared
clickable but did not respond.
[Finding #154](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/154#issue-5655793111).

**Follow-up:** closed on October 1. The issue records 24 related tests and Flutter
analysis passing, with Render deployment and device checks pending.

### MT139-09 — Choose and identify the default space (#155)

**Setup:** an account with two active spaces, labelled Space A and Space B for testing.

**Steps:**

1. Open Manage Storage Spaces and inspect default controls/labels.
2. Set Space B as default, leave and reopen the view.
3. Start stock entry without a location; inspect the selected/proposed space.
4. Explicitly choose Space A and verify that choice takes precedence.

**Expected:** one active default is identifiable, changeable and persisted.
Unspecified-location entry uses it; an explicit location overrides it.

**Observation:** users could neither select nor identify the default space; the
Agent chose a space implicitly.
[Finding #155](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/155#issue-5655852803).

**Follow-up:** closed on October 1; assigned to weizhou537.

### MT139-10 — Storage-space isolation on account change (#157)

**Setup:** two ordinary accounts with distinct spaces.

**Steps:**

1. Register a new account, sign in and inspect the Add inventory space selector.
2. As a follow-up variant, sign in as Account A and load its spaces.
3. Sign out, sign in as Account B and repeat the selector check.

**Expected:** Account B sees only its own spaces. Cached selections and form data
from Account A are cleared on account change.

**Observation:** a newly registered user saw another user's spaces in the dropdown.
[Finding and reproduction steps #157](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/157#issue-5655970653).

**Follow-up:** closed on October 1; linked to
[PR #159](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/pull/159),
[PR #160](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/pull/160)
and [PR #162](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/pull/162).

### MT139-11 — Agent classification into existing categories (#158)

**Setup:** an account with access to the public Yoghurt category.

**Steps:**

1. Verify Yoghurt is selectable during manual stock entry.
2. Use voice input to propose yoghurt through AI Assistant.
3. Review the recognized name/category, confirm and inspect the saved item.
4. Find the item through the category filter.

**Expected:** the recognized item uses the matching existing category and is
filterable by it. Private definitions retain the user's category unless corrected
through explicit review.

**Observation:** manual entry selected the correct category, while voice-assisted
entry did not use the existing Yoghurt category among the 25 public categories.
[Finding #158](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/158#issue-5655994709).

**Follow-up:** closed through PR #166 on October 2.
[Stock-policy notes](TESTING_IMPLEMENTATION_NOTES.md#stock-category-quantity-and-expiry-acceptance)
record automated database and English/Chinese live-model checks. A manual voice
and native presentation retest remains to be recorded.

### MT139-12 — Expiry suggestions for new stock (#161)

**Setup:** a new food item without a supplied expiry date; record the item and date.

**Steps:**

1. Propose stock entry and inspect the expiry suggestion, estimate label and date basis.
2. Confirm, then reload the item and expiry summary.
3. Repeat with an explicit expiry and with estimation unavailable.

**Expected:** supported enrichment supplies a labelled suggestion for review.
Explicit dates take precedence; unavailable optional estimation gives clear feedback
and allows otherwise valid stock entry.

**Observation:** Agent-created items remained at “no expiry”; default dates were requested.
[Finding #161](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/161#issue-5656526773).

**Follow-up:** closed through PR #166 on October 2.
[Expiry-policy notes](TESTING_IMPLEMENTATION_NOTES.md#stock-category-quantity-and-expiry-acceptance)
record date precedence, optional model failures and saved warnings.

### MT139-13 — Reopen Assistant at latest content (#170)

**Setup:** an existing scrollable conversation with replies and a review card.

**Steps:**

1. Leave and reopen Assistant; inspect the initial scroll position.
2. Select an existing conversation from History and check its position.
3. Send with the keyboard open and inspect new reply/review visibility.
4. Read older messages while replies arrive; then inspect a new conversation's welcome view.

**Expected:** existing conversations open at the latest content. Replies remain
visible near the bottom without interrupting a user reading older messages.
New conversations retain the welcome view.

**Observation:** reopening Assistant displayed the first message rather than the latest content.
[Finding #170](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/170#issue-5676020753).

**Follow-up:** the edited issue is Closed while its Project field is Todo. Its title
changed after closure on October 2; the observation date and matching fix need
confirmation. The [source index](../evidence/manual-integration/2026-10-03/source-index.json)
preserves that timeline.

## Evidence and retest entries

Screenshots: [#144 — 2](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/144#issue-5653899406),
[#145 — 1](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/145#issue-5653928115),
[#146 — 1](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/146#issue-5653983188),
[#147 — 4](https://github.com/UOA-CS734-S2-2026/project-implementation-appix/issues/147#issue-5654203592).
Issue #149 mentions a screenshot; the referenced attachment has not been located.
The [source index](../evidence/manual-integration/2026-10-03/source-index.json) retains
report timestamps, ownership, closure events and change links.

For each run, record: **date/time; tester; client/device/OS; APK/source commit;
Backend version/environment; case IDs; observed result; screenshot/log; fix and
retest outcome**. Retain the initial finding alongside its retest. Link selected
release runs from the [Final Acceptance Record](FINAL_ACCEPTANCE.md).
