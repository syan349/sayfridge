# Agent Client Integration

This guide owns UI transitions. The [API reference](API_REFERENCE.md#9-agent-v02--chat-resume-and-recovery)
owns request fields, limits, event formats and errors.

## User action and UI transition

| User action | API | UI behavior |
| --- | --- | --- |
| Send text/images | chat | Show processing progress, then answer, clarification or proposal |
| Speak | Client transcription, then chat | Allow editing and explicit sending; upload no audio |
| Supplement or revise a pending item | chat or resume | Update its existing card and use the new proposal ID |
| Supply a label photo for one item | resume | Attach it to that item and recalculate review details |
| Confirm selected items | resume | Display each actual result separately |
| Cancel an item | resume | Cancel pending work; retain other committed results |
| Reload or reconnect | state | Recover current progress before retrying the original request |

A photo-stock request and its later confirmation use separate streams. Uploading
a photo does not authorize stock creation. Complete text stock without a location
uses the active default space. Estimates execute with an approximate label unless
approval was requested; photo/category review waits for confirmation.

## Cards, streams and recovery

Cards show name, category, specification, actual amount/unit, dates, location,
source and review reason. Missing required facts produce a question; a proposal
must not be labeled committed. Revisions replace the card's actionable identifier.
Use each item's outcome rather than treating a partially successful turn as all-success.

Saved `display.question` supports recovery without another generated question.
An ended stream stops loading but can leave confirmation buttons available.
After stream interruption, query server state and retry with the original
request/action identity. State recovery returns current business progress; retain
local thumbnails and in-flight input for chat/image display. Confirmation must bind current interrupt and
proposal IDs. Expired proposals require state refresh.

Continuous chat can supply clarification, revision, cancellation, confirmation or
an independent query while work is pending. Preserve conversation ID across turns;
reuse request ID only for transport retries of the same request. Resume remains
available for structured per-item controls and selected confirmation (up to 20 items).

## Quantity and space display

Use `display_amount`, `display_unit` and `is_estimated`; current units can differ
from initial units. Whole-item estimate rounding is computed by the backend, not
hidden by UI formatting. Confirming a proposed estimate is not RECONCILE.
Space responses expose `is_default`; the default-space endpoint accepts an empty
request body as specified in the API reference.

## Contract references

- [State response](API_REFERENCE.md#get-apiv1agentconversationsconversation_idstate)
- [SSE events and parsing](API_REFERENCE.md#events)
- [Two-stream photo example](API_REFERENCE.md#agent-milk-sse-example)
- [Images, limits and examples](API_REFERENCE.md#multimodal-messages-and-frontend-contract)
- [Category review](API_REFERENCE.md#category-integration-and-agent-confirmation)
- [Graph and persistence](../architecture/AGENT_DESIGN.md)
