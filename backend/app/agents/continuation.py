"""Interpret chat supplements without giving the model authority to write stock."""
import json
import re
from typing import Literal
from pydantic import BaseModel, Field
from langchain_core.messages import SystemMessage, HumanMessage


class ContinuationAnswer(BaseModel):
    item_id: str
    decision: Literal["answer", "edit", "confirm", "cancel"]
    message: str = ""
    evidence: str


class Continuation(BaseModel):
    mode: Literal["CONTINUE", "NEW", "QUERY", "UNCLEAR"]
    responses: list[ContinuationAnswer] = Field(default_factory=list, max_length=20)


async def interpret_continuation(model, items, message):
    tool = {"type": "function", "function": {"name": "route_pending_message",
        "description": "Associate current user text with pending items without executing actions.",
        "parameters": Continuation.model_json_schema()}}
    response = await model.bind_tools([tool], tool_choice="route_pending_message").ainvoke([
        SystemMessage(content="Classify this user message. CONTINUE supplements/edits/confirms/cancels existing items. "
            "NEW is an independent inventory request; QUERY is a question unrelated to completing the pending items. "
            "UNCLEAR means the target cannot be resolved. Preserve unmentioned items. 'All in fridge' applies to all pending creations. "
            "confirm/cancel require explicit current user words; evidence must be an exact substring. "
            "For answer/edit, message must contain only the user's supplement, not an invented restatement. "
            "Pending item DATA: " + json.dumps(items, ensure_ascii=False, default=str)),
        HumanMessage(content=message)], config={"tags": ["agent_continuation"]})
    if len(response.tool_calls) != 1 or response.tool_calls[0]["name"] != "route_pending_message":
        raise ValueError("Unable to associate the message with pending items")
    result = Continuation.model_validate(response.tool_calls[0]["args"])
    known = {i["item_id"]: i for i in items}
    seen = set()
    for answer in result.responses:
        if answer.item_id not in known or answer.item_id in seen or not answer.evidence or answer.evidence not in message:
            raise ValueError("Invalid supplement target or source")
        seen.add(answer.item_id)
        if answer.decision in {"confirm", "cancel"}:
            pattern = (r"^(确认|确定|可以|好的?|是的|就这样|confirm\b|yes\b|ok\b|go ahead\b|do it\b)"
                       if answer.decision == "confirm" else r"^(取消|算了|不用了|不要了|cancel\b|never mind\b|stop\b)")
            if not re.search(pattern, answer.evidence.strip(), re.IGNORECASE):
                raise ValueError("Confirmation or cancellation requires explicit current user words")
        if answer.decision in {"answer", "edit"}:
            answer.message = message
    return result
