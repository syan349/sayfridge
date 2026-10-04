"""Authenticated Agent SSE, typed resume, and sanitized recovery state."""
import asyncio
import json
import logging
from datetime import date
from contextlib import AsyncExitStack, suppress, aclosing
from uuid import UUID, uuid4, uuid5

from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask
from langgraph.types import Command
from langchain_core.messages import AIMessage

from app.api.dependencies import get_current_user
from app.db.models import User
from app.db.session import get_db_session
from sqlalchemy.ext.asyncio import AsyncSession
from app.services import conversation_history as history
from app.agents.persistence import get_agent_resources, get_agent_persistence_settings
from app.agents.locking import conversation_lock, ConversationBusy
from app.agents.state import AgentContext
from app.agents.messages import human_message, chat_fingerprint, resume_fingerprint, validate_image_ids
from app.agents.workflow import public_state
from app.schemas.agent import AgentChatRequest, AgentErrorResponse, PrimaryChatResponse
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
HEARTBEAT_SECONDS = 15


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


def _replay(snapshot, result):
    """Preserve the result of this request; attach a live interrupt only if valid."""
    state = result.get("state", result)
    if state.get("status") == "WAITING_INPUT":
        current = _state(snapshot)
        original_proposals = {i["item_id"]: i["proposal_id"] for i in state.get("items", [])
                              if i["status"] in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"}}
        current_proposals = {i["item_id"]: i["proposal_id"] for i in current.get("items", [])
                             if i["status"] in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"}}
        if current.get("interrupt_id") and all(current_proposals.get(k) == v for k, v in original_proposals.items()):
            state = {**state, "interrupt_id": current["interrupt_id"],
                     "pending": {"items": [i for i in state["items"] if i["status"] in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"}]}}
    return {**result, "state": state}


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


async def _with_heartbeats(stream):
    iterator = aiter(stream)
    pending = None
    loop = asyncio.get_running_loop()
    next_heartbeat = loop.time() + HEARTBEAT_SECONDS
    try:
        while True:
            pending = asyncio.create_task(anext(iterator))
            while True:
                done, _ = await asyncio.wait({pending}, timeout=max(0, next_heartbeat - loop.time()))
                # Internal model tokens are filtered out of public SSE. They
                # must not reset the heartbeat clock and leave clients idle.
                if loop.time() >= next_heartbeat:
                    yield None
                    next_heartbeat = loop.time() + HEARTBEAT_SECONDS
                if done:
                    break
            try:
                yield pending.result()
            except StopAsyncIteration:
                return
    finally:
        if pending is not None and not pending.done():
            pending.cancel()
            with suppress(asyncio.CancelledError, StopAsyncIteration):
                await pending
        if hasattr(iterator, "aclose"):
            await iterator.aclose()


def _history_writer(session, user_id, conversation_id, *, complete=False):
    async def write(records):
        return await history.try_write_messages(session, user_id, conversation_id, records, complete=complete)
    return write


def _response(stack, resources, config, command, context, request, request_id, replay=None):
    async def events():
        final_streamed = False
        try:
            yield _sse("start", conversation_id=str(context.conversation_id), request_id=str(request_id))
            if replay is not None:
                snapshot = await resources.graph.aget_state(config)
                if context.history_writer:
                    await context.history_writer(snapshot.values.get("history_outbox", {}))
                if replay.get("answer"):
                    yield _sse("text_delta", delta=_text(replay["answer"]))
                state = replay.get("state", replay)
                for item in state.get("items", []):
                    if item["status"] in {"SUCCEEDED", "FAILED", "CANCELLED"}:
                        yield _sse("operation_result", data=item)
                if state.get("status") == "WAITING_INPUT":
                    question = _pending_text(state.get("items", []))
                    if question:
                        yield _sse("text_delta", delta=question)
                if state.get("interrupt_id"):
                    yield _sse("action_required", data=state)
                yield _sse("done", status=state.get("status", "COMPLETED"), data=state)
                return
            stream = resources.graph.astream(command, config=config, context=context,
                    stream_mode=["messages", "updates"], durability="sync")
            async with aclosing(_with_heartbeats(stream)) as entries:
                async for entry in entries:
                    if await request.is_disconnected():
                        raise asyncio.CancelledError()
                    if entry is None:
                        yield ": keep-alive\n\n"
                        continue
                    mode, chunk = entry
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
                                if update.get("route") in {"END", "WAIT"} and not final_streamed:
                                    for message in update.get("messages", []):
                                        if isinstance(message, AIMessage) and not message.tool_calls and _text(message.content):
                                            yield _sse("text_delta", delta=_text(message.content))
            snapshot = await resources.graph.aget_state(config)
            if context.history_writer:
                await context.history_writer(snapshot.values.get("history_outbox", {}))
            state = _state(snapshot)
            yield _sse("done", status=state["status"], data=state)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning("Agent request failed (%s)", type(exc).__name__)
            yield _sse("error", code=getattr(exc, "code", "AGENT_EXECUTION_FAILED"), message="Execution interrupted; query conversation state and retry with the same request ID")
        finally:
            await stack.aclose()
    return StreamingResponse(events(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}, background=BackgroundTask(stack.aclose))


@router.post("/chat", summary="Stream an Agent turn", response_class=StreamingResponse,
             responses={200: {"content": {"text/event-stream": {"schema": {"type": "string"}}}}})
async def chat_with_agent(payload: AgentChatRequest, request: Request, user: User = Depends(get_current_user),
                          session: AsyncSession = Depends(get_db_session)):
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
            replay = _replay(snapshot, previous)
        elif str(request_id) in values.get("chat_requests", {}):
            if values["chat_requests"][str(request_id)] != digest:
                raise HTTPException(409, detail={"code": "REQUEST_ID_CONFLICT"})
            command = None
            if _interrupts(snapshot) or not snapshot.next:
                replay = _state(snapshot)
        elif values.get("turn_id") == str(request_id):
            if values.get("request_fingerprint") != digest:
                raise HTTPException(409, detail={"code": "REQUEST_ID_CONFLICT"})
            command = None
            if _interrupts(snapshot) or not snapshot.next:
                replay = _state(snapshot)
        else:
            record = history.chat_input(conversation_id, request_id, payload)
            if _interrupts(snapshot):
                interrupt = _interrupts(snapshot)[0]
                command = Command(resume={interrupt.id: {"chat_message": payload.message,
                    "images": [i.model_dump(mode="json") for i in payload.images],
                    "request_id": str(request_id), "fingerprint": digest, "_public_input": record}})
            elif snapshot.next:
                raise HTTPException(409, detail={"code": "AGENT_INPUT_REQUIRED" if _interrupts(snapshot) else "AGENT_RECOVERY_REQUIRED", "state": _state(snapshot)})
            if not validate_image_ids(payload.images, [*values.get("image_messages", []), *values.get("messages", [])]):
                raise HTTPException(409, detail={"code": "IMAGE_ID_CONFLICT"})
            if not _interrupts(snapshot):
                command = {"messages": [human_message(payload.message, payload.images, str(request_id),
                    known_messages=[*values.get("image_messages", []), *values.get("messages", [])])],
                "turn_id": str(request_id), "as_of": payload.as_of.isoformat() if payload.as_of else None,
                "chat_requests": {str(request_id): digest},
                "turn_has_images": bool(payload.images),
                "image_task_active": bool(payload.images) or values.get("image_task_active", False),
                "request_fingerprint": digest, "items": [], "pending_input": [],
                "context_next": "prepare_context",
                "public_turn": {"request_id": str(request_id), "conversation_id": str(conversation_id), "input": record},
                "history_outbox": {**values.get("history_outbox", {}), record["id"]: record},
                "execution_results": [], "events": [], "final_only": False,
                "inventory_reads": {}, "inventory_query": None}
        as_of = payload.as_of or (date.fromisoformat(values["as_of"]) if snapshot.next and values.get("as_of") else None)
        context = AgentContext(user_id=user.id, as_of=as_of, conversation_id=conversation_id, user_message=payload.message,
            history_writer=_history_writer(session, user.id, conversation_id, complete=not bool(values)),
            inventory_cards=request.headers.get("x-sayfridge-inventory-cards") == "1")
        return _response(stack, resources, config, command, context, request, request_id, replay)
    except BaseException:
        await stack.aclose()
        raise


@router.post("/resume", summary="Answer, edit, confirm or cancel pending Agent items", response_class=StreamingResponse,
             responses={200: {"content": {"text/event-stream": {"schema": {"type": "string"}}}}})
async def resume_agent(payload: AgentResumeRequest, request: Request, user: User = Depends(get_current_user),
                       session: AsyncSession = Depends(get_db_session)):
    """Resume one paused conversation with validated answers or confirmations."""
    stack, resources, config, snapshot = await _open(user, payload.conversation_id)
    try:
        data = payload.model_dump(mode="json")
        prior = snapshot.values.get("resume_requests", {}).get(str(payload.request_id))
        if prior:
            if prior != resume_fingerprint(payload):
                raise HTTPException(409, detail={"code": "REQUEST_ID_CONFLICT"})
            saved = snapshot.values.get("requests", {}).get(str(payload.request_id))
            replay = _replay(snapshot, saved) if saved else (_state(snapshot) if _interrupts(snapshot) or not snapshot.next else None)
            command = None
        else:
            interrupts = _interrupts(snapshot)
            if len(interrupts) != 1 or interrupts[0].id != payload.interrupt_id:
                raise HTTPException(409, detail={"code": "STALE_INTERRUPT"})
            if not validate_image_ids([i for r in payload.responses for i in r.images],
                    [*snapshot.values.get("image_messages", []), *snapshot.values.get("messages", [])]):
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
            data["_public_input"] = history.resume_input(payload.conversation_id, payload.request_id, payload, snapshot.values.get("items", []))
            replay, command = None, Command(resume={payload.interrupt_id: data})
        context = AgentContext(user_id=user.id, as_of=date.fromisoformat(snapshot.values["as_of"]) if snapshot.values.get("as_of") else None,
            conversation_id=payload.conversation_id, user_message="\n".join(r.message for r in payload.responses if r.message),
            history_writer=_history_writer(session, user.id, payload.conversation_id),
            inventory_cards=request.headers.get("x-sayfridge-inventory-cards") == "1")
        return _response(stack, resources, config, command, context, request, payload.request_id, replay)
    except BaseException:
        await stack.aclose()
        raise


@router.get("/conversations/{conversation_id}/state", summary="Read sanitized Agent recovery state",
            response_model=AgentConversationState, response_model_exclude_none=True)
async def conversation_state(conversation_id: UUID, user: User = Depends(get_current_user),
                             session: AsyncSession = Depends(get_db_session)):
    """Return the current user's sanitized conversation state for recovery."""
    try:
        resources = await get_agent_resources()
        snapshot = await resources.graph.aget_state(_config(user.id, conversation_id))
    except Exception:
        raise HTTPException(503, detail={"code": "AGENT_UNAVAILABLE"}) from None
    if not snapshot.values:
        raise HTTPException(404, detail={"code": "NOT_FOUND"})
    await _history_writer(session, user.id, conversation_id)(snapshot.values.get("history_outbox", {}))
    return _state(snapshot)


@router.get("/chat", summary="Open the primary chat and read public history", response_model=PrimaryChatResponse,
            response_model_exclude_none=True)
async def primary_chat(before: UUID | None = None, page_size: int = Query(50, ge=1, le=100),
                       user: User = Depends(get_current_user), session: AsyncSession = Depends(get_db_session)):
    """Return a stable primary ID, its recovery state, and ordered public messages.

    The cursor pages older public messages; it never selects model context.
    Legacy POST and state requests keep their original conversation identity.
    """
    try:
        resources = await get_agent_resources()
        cid, snapshot, rows, next_before, complete = await history.primary_history(session, user.id, resources.graph,
            before=before, page_size=page_size, pool=getattr(resources, "pool", None))
        return {"conversation_id": cid, "state": _state(snapshot), "messages": rows,
                "next_before": next_before, "history_complete": complete}
    except history.HistoryError as exc:
        raise HTTPException(422 if exc.code == "INVALID_HISTORY_CURSOR" else 404, detail={"code": exc.code}) from None
    except Exception:
        raise HTTPException(503, detail={"code": "AGENT_UNAVAILABLE"}) from None
