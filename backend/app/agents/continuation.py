"""Interpret chat supplements without giving the model authority to write stock."""
import json
import re
from typing import Literal
from pydantic import BaseModel, Field, ConfigDict
from langchain_core.messages import SystemMessage, ToolMessage
from app.agents.messages import human_message
from app.agents.prompts import UNDERSTANDING_RULES


class ContinuationAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_id: str = ""
    item_key: str | None = None
    decision: Literal["answer", "edit", "confirm", "cancel", "retry"]
    message: str = ""
    evidence: str
    image_ids: list[str] = Field(default_factory=list, max_length=4)
    selected_inventory_item_id: str | None = None
    selected_space_name: str | None = None


class Continuation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mode: Literal["CONTINUE", "NEW", "QUERY", "UNCLEAR", "REPLAY"]
    responses: list[ContinuationAnswer] = Field(default_factory=list, max_length=20)
    question: str | None = Field(default=None, max_length=250)
    replay_item_ids: list[str] = Field(default_factory=list, max_length=20)
    candidate_item_keys: list[str] = Field(default_factory=list, max_length=20)


def explicit_group_confirmation(message):
    """Only a complete, affirmative instruction about all displayed proposals."""
    return bool(re.fullmatch(
        r"\s*(?:确认(?:以上|全部|所有|这些|上述)(?:所有|全部)?(?:商品|物品|操作)?(?:入库|保存|执行)?"
        r"|confirm\s+(?:all|everything)(?:\s+(?:items|changes|proposals))?)\s*[。.!！]?\s*",
        message, re.I))


async def interpret_continuation(model, items, message, *, images=(), messages=(), unresolved=None, completed=()):
    if not images and explicit_group_confirmation(message):
        return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=i["item_id"],
            decision="confirm", evidence=message) for i in items if i["status"] == "NEEDS_CONFIRMATION"])
    tool = {"type": "function", "function": {"name": "route_pending_message",
        "description": "Associate current user text with pending items without executing actions.",
        "parameters": Continuation.model_json_schema()}}
    buffered = ({"message": unresolved.get("message"), "candidate_item_ids": unresolved.get("candidate_item_ids")}
                if unresolved else None)
    routing_items = [{k: i[k] for k in ("item_id", "item_key", "status", "draft", "error", "question") if k in i}
                     for i in items]
    finished_items = [{k: i[k] for k in ("item_id", "item_key", "status", "draft") if k in i} for i in completed]
    inputs = [
        SystemMessage(content="Classify this user message. CONTINUE supplements/edits/confirms/cancels existing items. "
            "NEW is an independent inventory request; QUERY is a question unrelated to completing the pending items. "
            "Pending work never blocks NEW or QUERY. Do not demand an old target/quantity answer before accepting a clearly independent purchase. "
            "An unrelated new purchase must use NEW with responses=[]; do not put a promise to add it inside an UNCLEAR question. "
            "UNCLEAR means the target cannot be resolved. Preserve unmentioned items. 'All in fridge' applies to all pending creations. "
            "confirm/cancel require explicit current user words; evidence must be an exact substring. "
            "Use the actual current images and recent conversation to associate supplements. An image alone may answer a pending item; use image_ids as evidence. "
            "A duplicate photo does not add sale rows or authorize confirmation. If the target is unclear, use UNCLEAR and a short question identifying the choice. "
            "A buffered answer was already supplied: after the user selects its target, apply that answer without asking them to repeat it. "
            "For answer/edit, message must contain only the user's supplement, not an invented restatement. "
            "Prefer each pending item's stable item_key in responses; leave item_id empty and the server maps it. On UNCLEAR list only plausible candidate_item_keys, not unrelated tasks. "
            "selected_inventory_item_id must be a real candidate ID shown in that item's validation error; never invent or pick an ambiguous batch. "
            "For a batch chosen by its storage name, prefer selected_space_name copied exactly from storage_space_name in the candidates. The server maps it only if that space has one candidate. "
            "For an EXECUTION_UNCERTAIN item, an explicit request to retry/check the same save uses decision=retry, preserving the original operation. Never edit, cancel or recreate that uncertain operation. "
            "REPLAY identifies a repeated supplement/confirmation clearly referring to completed items, with no new operation intention. Supply their replay_item_ids and no responses. Mere product/quantity similarity is insufficient. A new purchase, including '又买了', is NEW. "
            + UNDERSTANDING_RULES + "\nPending item DATA: " + json.dumps(routing_items, ensure_ascii=False, default=str)
            + "\nBuffered answer DATA: " + json.dumps(buffered, ensure_ascii=False)
            + "\nRecent completed task DATA: " + json.dumps(finished_items, ensure_ascii=False, default=str)
            + "\nCurrent image metadata: " + json.dumps([i.metadata() for i in images])),
        *[m for m in messages[-6:] if m.type == "human"],
        human_message(message, images, "continuation-input")]
    bound = model.bind_tools([tool], tool_choice="route_pending_message")
    for attempt in range(3):
        response = await bound.ainvoke(inputs, config={"tags": ["agent_continuation"]})
        try:
            if len(response.tool_calls) != 1 or response.tool_calls[0]["name"] != "route_pending_message":
                raise ValueError("Return exactly one route_pending_message call")
            result = Continuation.model_validate(response.tool_calls[0]["args"])
            return validate_continuation(result, items, message, images, completed)
        except ValueError as exc:
            if attempt == 2:
                return Continuation(mode="UNCLEAR")
            inputs.append(response)
            inputs.extend(ToolMessage(content="Invalid association: " + str(exc)[:400] + ". Use only actual item_id values and current evidence; no changes executed.",
                                      tool_call_id=c["id"]) for c in [*response.tool_calls, *response.invalid_tool_calls])
            inputs.append(SystemMessage(content="Correct the association or use UNCLEAR. Preserve the user's answer without executing anything."))


def validate_continuation(result, items, message, images, completed=()):
    if result.mode == "REPLAY":
        if not result.replay_item_ids or result.responses or not set(result.replay_item_ids).issubset({i["item_id"] for i in completed}):
            raise ValueError("Replay must refer only to actual completed item_id values")
    elif result.replay_item_ids:
        raise ValueError("Only replay can identify completed items")
    known = {i["item_id"]: i for i in items}
    keys = {i["item_key"]: i for i in items}
    if not set(result.candidate_item_keys).issubset(keys):
        raise ValueError("Unclear targets must use actual pending item keys")
    image_ids = {str(i.image_id) for i in images}
    seen = set()
    for answer in result.responses:
        if answer.item_key:
            item = keys.get(answer.item_key)
            if not item or (answer.item_id and answer.item_id != item["item_id"]):
                raise ValueError("Use the correct pending item_key and leave item_id empty")
            answer.item_id = item["item_id"]
        text_evidence = bool(answer.evidence and answer.evidence in message)
        visual_evidence = bool(answer.image_ids and set(answer.image_ids).issubset(image_ids))
        if answer.item_id not in known or answer.item_id in seen or not (text_evidence or visual_evidence):
            raise ValueError("Invalid supplement target or source")
        seen.add(answer.item_id)
        if answer.decision in {"confirm", "cancel", "retry"}:
            if not text_evidence or images:
                raise ValueError("Images are not confirmation or cancellation")
            pattern = (r"^(确认|确定|可以|好的?|是的|就这样|confirm\b|yes\b|ok\b|go ahead\b|do it\b)"
                       if answer.decision == "confirm" else r"^(重试|再试|重新核对|核对.*保存|retry\b|try again\b|check.*save\b)"
                       if answer.decision == "retry" else r"^(取消|算了|不用了|不要了|cancel\b|never mind\b|stop\b)")
            if not re.search(pattern, answer.evidence.strip(), re.IGNORECASE):
                raise ValueError("Confirmation or cancellation requires explicit current user words")
            if answer.decision == "retry" and known[answer.item_id].get("error", {}).get("code") != "EXECUTION_UNCERTAIN":
                raise ValueError("Receipt retry applies only to the original uncertain operation")
        if answer.decision in {"answer", "edit"}:
            answer.message = message
        if answer.selected_inventory_item_id or answer.selected_space_name:
            candidates = known[answer.item_id].get("error", {}).get("details", {}).get("candidates", [])
            if answer.selected_space_name:
                matching = [c for c in candidates if (c.get("storage_space_name") or "").casefold() == answer.selected_space_name.casefold()]
                if len(matching) != 1 or answer.selected_space_name.casefold() not in message.casefold():
                    raise ValueError("The selected storage name must uniquely identify a candidate in current user words")
                answer.selected_inventory_item_id = str(matching[0]["id"])
            if answer.selected_inventory_item_id not in {str(c["id"]) for c in candidates}:
                raise ValueError("Invalid inventory batch selection")
    if result.mode != "CONTINUE" and result.responses:
        raise ValueError("Only a continuation can change pending items")
    return result
