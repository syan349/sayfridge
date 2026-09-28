"""Authenticated Agent SSE, typed resume, and sanitized recovery state."""
import asyncio
import json
import logging
from datetime import date
from contextlib import AsyncExitStack
from uuid import UUID, uuid4, uuid5

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask
from langgraph.types import Command
from langchain_core.messages import AIMessage

from app.api.dependencies import get_current_user
from app.db.models import User
from app.agents.persistence import get_agent_resources, get_agent_persistence_settings
from app.agents.locking import conversation_lock, ConversationBusy
from app.agents.state import AgentContext
from app.agents.messages import human_message, chat_fingerprint, resume_fingerprint, validate_image_ids
from app.agents.workflow import public_state
from app.schemas.agent import AgentChatRequest, AgentErrorResponse
from app.schemas.auth import AuthErrorResponse
from app.schemas.agent_actions import AgentResumeRequest, AgentConversationState

router = APIRouter(
    prefix="/api/v1/agent",
    tags=["agent"],
    responses={
        401: {
            "model": AuthErrorResponse,
            "description": "Missing, invalid, expired, or unavailable identity",
        },
        409: {
            "model": AgentErrorResponse,
            "description": "Conversation state or idempotency conflict",
        },
        503: {
            "model": AgentErrorResponse,
            "description": "Agent persistence or execution service is unavailable",
        },
    },
)
logger = logging.getLogger(__name__)


def _thread_id(user_id, conversation_id):
    return f"user:{user_id}:conversation:{conversation_id}"


def _config(user_id, conversation_id):
    return {"configurable": {"thread_id": _thread_id(user_id, conversation_id)},
            "recursion_limit": get_agent_persistence_settings().workflow_step_limit}


def _interrupts(snapshot):
    return [i for task in snapshot.tasks for i in task.interrupts]


def _state(snapshot):
    result = public_state(snapshot.values)
    interrupts = _interrupts(snapshot)
    if interrupts:
        result.update(status="WAITING_INPUT", interrupt_id=interrupts[0].id, pending=interrupts[0].value)
    elif snapshot.next:
        result["status"] = "RECOVERABLE"
    return result


def _sse(kind, **data):
    return f"event: {kind}\ndata: {json.dumps({'type': kind, **data}, ensure_ascii=False, default=str)}\n\n"


def _text(content):
    if isinstance(content, str):
        return content
    return "".join(v.get("text", "") for v in content if isinstance(v, dict) and v.get("type") in {"text", "output_text"}) if isinstance(content, list) else ""


def _pending_text(items):
    questions = [(item.get("display") or {}).get("question") for item in items
                 if item.get("status") in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"}]
    return "\n".join(dict.fromkeys(q for q in questions if q))


async def _open(user, conversation_id):
    stack = AsyncExitStack()
    try:
        await stack.enter_async_context(conversation_lock(user.id, conversation_id))
        resources = await get_agent_resources()
        config = _config(user.id, conversation_id)
        snapshot = await resources.graph.aget_state(config)
        return stack, resources, config, snapshot
    except BaseException as exc:
        await stack.aclose()
        if isinstance(exc, ConversationBusy):
            raise HTTPException(409, detail={"code": "AGENT_CONVERSATION_BUSY", "message": "Conversation is running"}) from None
        if isinstance(exc, (HTTPException, asyncio.CancelledError)):
            raise
        raise HTTPException(503, detail={"code": "AGENT_UNAVAILABLE", "message": "Agent storage is unavailable"}) from None


def _response(stack, resources, config, command, context, request, request_id, replay=None):
    async def events():
        final_streamed = False
        try:
            yield _sse("start", conversation_id=str(context.conversation_id), request_id=str(request_id))
            if replay is not None:
                if replay.get("answer"):
                    yield _sse("text_delta", delta=_text(replay["answer"]))
                state = replay.get("state", replay)
                for item in state.get("items", []):
                    if item["status"] in {"SUCCEEDED", "FAILED", "CANCELLED"}:
                        yield _sse("operation_result", data=item)
                if state.get("interrupt_id"):
                    question = _pending_text(state.get("items", []))
                    if question:
                        yield _sse("text_delta", delta=question)
                    yield _sse("action_required", data=state)
                yield _sse("done", status=state.get("status", "COMPLETED"), data=state)
                return
            async for mode, chunk in resources.graph.astream(command, config=config, context=context,
                    stream_mode=["messages", "updates"], durability="sync"):
                if await request.is_disconnected():
                    raise asyncio.CancelledError()
                if mode == "messages":
                    message, metadata = chunk
                    if "agent_final" in metadata.get("tags", []):
                        delta = _text(message.content)
                        if delta:
                            final_streamed = True
                            yield _sse("text_delta", delta=delta)
                else:
                    for node, update in chunk.items():
                        if node == "__interrupt__":
                            for intr in update:
                                question = _pending_text(intr.value.get("items", []))
                                if question:
                                    yield _sse("text_delta", delta=question)
                                yield _sse("action_required", data={"interrupt_id": intr.id, **intr.value})
                        elif isinstance(update, dict):
                            for event in update.get("events", []):
                                yield _sse(event["type"], data=event["data"])
                            if update.get("route") == "END" and not final_streamed:
                                for message in update.get("messages", []):
                                    if isinstance(message, AIMessage) and not message.tool_calls and _text(message.content):
                                        yield _sse("text_delta", delta=_text(message.content))
            snapshot = await resources.graph.aget_state(config)
            state = _state(snapshot)
            yield _sse("done", status=state["status"], data=state)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning("Agent request failed (%s)", type(exc).__name__)
            yield _sse("error", code="AGENT_EXECUTION_FAILED", message="Execution interrupted; query conversation state and retry with the same request ID")
        finally:
            await stack.aclose()
    return StreamingResponse(events(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}, background=BackgroundTask(stack.aclose))


@router.post("/chat", summary="Stream an Agent turn", response_class=StreamingResponse,
             responses={200: {"content": {"text/event-stream": {"schema": {"type": "string"}}}}})
async def chat_with_agent(payload: AgentChatRequest, request: Request, user: User = Depends(get_current_user)):
    """Start or replay one Agent turn and stream typed server-sent events."""
    request_id = payload.request_id or uuid4()
    conversation_id = payload.conversation_id or uuid5(user.id, f"agent:{request_id}")
    stack, resources, config, snapshot = await _open(user, conversation_id)
    try:
        digest = chat_fingerprint(payload)
        values = snapshot.values
        previous = values.get("requests", {}).get(str(request_id))
        replay = None
        if previous:
            if previous["fingerprint"] != digest:
                raise HTTPException(409, detail={"code": "REQUEST_ID_CONFLICT"})
            replay, command = previous, None
        elif values.get("turn_id") == str(request_id):
            if values.get("request_fingerprint") != digest:
                raise HTTPException(409, detail={"code": "REQUEST_ID_CONFLICT"})
            command = None
            if _interrupts(snapshot) or not snapshot.next:
                replay = _state(snapshot)
        else:
            if snapshot.next:
                raise HTTPException(409, detail={"code": "AGENT_INPUT_REQUIRED" if _interrupts(snapshot) else "AGENT_RECOVERY_REQUIRED", "state": _state(snapshot)})
            if not validate_image_ids(payload.images, values.get("messages", [])):
                raise HTTPException(409, detail={"code": "IMAGE_ID_CONFLICT"})
            command = {"messages": [human_message(payload.message, payload.images, str(request_id))],
                "turn_id": str(request_id), "as_of": payload.as_of.isoformat() if payload.as_of else None,
                "turn_has_images": bool(payload.images),
                "image_task_active": bool(payload.images) or values.get("image_task_active", False),
                "request_fingerprint": digest, "items": [], "pending_input": [],
                "execution_results": [], "events": [], "final_only": False, "resume_requests": {}}
        context = AgentContext(user_id=user.id, as_of=payload.as_of, conversation_id=conversation_id, user_message=payload.message)
        return _response(stack, resources, config, command, context, request, request_id, replay)
    except BaseException:
        await stack.aclose()
        raise


@router.post("/resume", summary="Answer, edit, confirm or cancel pending Agent items", response_class=StreamingResponse,
             responses={200: {"content": {"text/event-stream": {"schema": {"type": "string"}}}}})
async def resume_agent(payload: AgentResumeRequest, request: Request, user: User = Depends(get_current_user)):
    """Resume one paused conversation with validated answers or confirmations."""
    stack, resources, config, snapshot = await _open(user, payload.conversation_id)
    try:
        data = payload.model_dump(mode="json")
        prior = snapshot.values.get("resume_requests", {}).get(str(payload.request_id))
        if prior:
            if prior != resume_fingerprint(payload):
                raise HTTPException(409, detail={"code": "REQUEST_ID_CONFLICT"})
            replay = _state(snapshot) if _interrupts(snapshot) or not snapshot.next else None
            command = None
        else:
            interrupts = _interrupts(snapshot)
            if len(interrupts) != 1 or interrupts[0].id != payload.interrupt_id:
                raise HTTPException(409, detail={"code": "STALE_INTERRUPT"})
            if not validate_image_ids([i for r in payload.responses for i in r.images], snapshot.values.get("messages", [])):
                raise HTTPException(409, detail={"code": "IMAGE_ID_CONFLICT"})
            items = {i["item_id"]: i for i in snapshot.values.get("items", [])}
            for answer in payload.responses:
                item = items.get(str(answer.item_id))
                if not item or item["status"] not in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"} or item["proposal_id"] != str(answer.proposal_id):
                    raise HTTPException(409, detail={"code": "STALE_PROPOSAL"})
                if answer.decision == "confirm" and item["status"] != "NEEDS_CONFIRMATION":
                    raise HTTPException(422, detail={"code": "ANSWER_REQUIRED"})
                if answer.selected_inventory_item_id:
                    choices = item.get("error", {}).get("details", {}).get("candidates", [])
                    if str(answer.selected_inventory_item_id) not in {str(c["id"]) for c in choices}:
                        raise HTTPException(422, detail={"code": "INVALID_TARGET_SELECTION"})
                if item.get("error", {}).get("code") == "EXECUTION_UNCERTAIN" and answer.decision != "confirm":
                    raise HTTPException(409, detail={"code": "VERIFY_OUTCOME_FIRST"})
            replay, command = None, Command(resume={payload.interrupt_id: data})
        context = AgentContext(user_id=user.id, as_of=date.fromisoformat(snapshot.values["as_of"]) if snapshot.values.get("as_of") else None,
            conversation_id=payload.conversation_id, user_message="\n".join(r.message for r in payload.responses if r.message))
        return _response(stack, resources, config, command, context, request, payload.request_id, replay)
    except BaseException:
        await stack.aclose()
        raise


@router.get("/conversations/{conversation_id}/state", summary="Read sanitized Agent recovery state",
            response_model=AgentConversationState, response_model_exclude_none=True)
async def conversation_state(conversation_id: UUID, user: User = Depends(get_current_user)):
    """Return the current user's sanitized conversation state for recovery."""
    try:
        resources = await get_agent_resources()
        snapshot = await resources.graph.aget_state(_config(user.id, conversation_id))
    except Exception:
        raise HTTPException(503, detail={"code": "AGENT_UNAVAILABLE"}) from None
    if not snapshot.values:
        raise HTTPException(404, detail={"code": "NOT_FOUND"})
    return _state(snapshot)
