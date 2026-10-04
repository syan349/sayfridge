"""Public messages only. Inventory receipts and checkpoints own execution recovery."""
from datetime import datetime, timezone
from uuid import UUID, uuid5
import re
import asyncio
import logging

from sqlalchemy import select, tuple_, update, func
from sqlalchemy.dialects.postgresql import insert

from app.db.models import Conversation, ConversationMessage, User

logger = logging.getLogger(__name__)


class HistoryError(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def public_text(value):
    if not isinstance(value, str):
        value = "\n".join(b.get("text", "") for b in value
                          if isinstance(b, dict) and b.get("type") in {"text", "output_text"}) if isinstance(value, list) else ""
    return re.sub(r"data:image/[^\s]+", "[Image attached]", value)


def message_record(conversation_id, request_id, role, content, *, created_at=None):
    return {"id": str(uuid5(UUID(str(conversation_id)), f"public:{request_id}:{role}")),
            "role": role, "content": public_text(content),
            "created_at": created_at or datetime.now(timezone.utc).isoformat()}


def chat_input(conversation_id, request_id, payload):
    content = payload.message
    if payload.images:
        content = "\n".join(filter(None, [content, *[f"[Image attached: {i.mime_type}]" for i in payload.images]]))
    return message_record(conversation_id, request_id, "USER", content)


def resume_input(conversation_id, request_id, payload, items):
    known = {i["item_id"]: i for i in items}
    lines = []
    for answer in payload.responses:
        item = known.get(str(answer.item_id), {})
        display, draft = item.get("display") or {}, item.get("draft") or {}
        name = display.get("item_name") or (draft.get("new_definition") or {}).get("name") or draft.get("item_query") or item.get("original_text", "item")
        action = {"confirm": "Confirmed", "cancel": "Cancelled", "answer": "Answered", "edit": "Edited"}[answer.decision]
        lines.append(f"[{action}: {name}]")
        if answer.message:
            lines.append(answer.message)
        if answer.selected_inventory_item_id:
            candidates = (item.get("error") or {}).get("details", {}).get("candidates", [])
            selected = next((c for c in candidates if str(c["id"]) == str(answer.selected_inventory_item_id)), {})
            label = selected.get("item_definition_name") or name
            if selected.get("storage_space_name"):
                label += " in " + selected["storage_space_name"]
            lines.append("[Selected batch: " + label + "]")
        lines.extend(f"[Image attached: {i.mime_type}]" for i in answer.images)
    return message_record(conversation_id, request_id, "USER", "\n".join(lines))


async def ensure_conversation(session, user_id, conversation_id, *, complete=False):
    await session.execute(insert(Conversation).values(id=conversation_id, user_id=user_id,
        history_complete=complete).on_conflict_do_nothing(index_elements=[Conversation.id]))
    row = await session.get(Conversation, conversation_id, populate_existing=True)
    if row.user_id != user_id:
        raise HistoryError("NOT_FOUND")
    return row


async def write_messages(session, user_id, conversation_id, records, *, complete=False):
    """Stable IDs survive replay, retries and acknowledgement loss after COMMIT."""
    if not records:
        return set()
    row = await ensure_conversation(session, user_id, conversation_id, complete=complete)
    for record in records.values():
        stamp = datetime.fromisoformat(record["created_at"])
        if stamp.tzinfo is None:
            raise ValueError("Public message timestamp must include a timezone")
        await session.execute(insert(ConversationMessage).values(id=UUID(record["id"]),
            conversation_id=conversation_id, role=record["role"], content=public_text(record["content"]),
            created_at=stamp).on_conflict_do_nothing(index_elements=[ConversationMessage.id]))
    latest = max(datetime.fromisoformat(r["created_at"]) for r in records.values())
    await session.execute(update(Conversation).where(Conversation.id == conversation_id).values(
        updated_at=func.greatest(Conversation.updated_at, latest)))
    await session.commit()
    return set(records)


async def try_write_messages(session, user_id, conversation_id, records, *, complete=False):
    try:
        async with asyncio.timeout(5):
            return await write_messages(session, user_id, conversation_id, records, complete=complete)
    except Exception as exc:
        # History failure never changes an inventory receipt or retries execution.
        logger.warning("agent_history_write_failed cause=%s", type(exc).__name__)
        await session.rollback()
        return set()


async def bind_primary(session, user_id, legacy_threads):
    # Serialize first binding with old-client writes and concurrent GETs without
    # constraining user_id across the user's other conversations.
    await session.scalar(select(User.id).where(User.id == user_id).with_for_update())
    primary = await session.scalar(select(Conversation).where(
        Conversation.user_id == user_id, Conversation.is_primary.is_(True)))
    if primary is not None:
        await session.commit()
        return primary
    existing = await session.scalar(select(Conversation).where(Conversation.user_id == user_id)
                                    .order_by(Conversation.updated_at.desc(), Conversation.id.desc()).limit(1))
    candidates = [(stamp, cid) for cid, stamp in legacy_threads]
    if existing:
        candidates.append((existing.updated_at, existing.id))
    latest = max(candidates, key=lambda v: (v[0], str(v[1]))) if candidates else None
    cid = latest[1] if latest else uuid5(user_id, "agent:primary")
    primary = await ensure_conversation(session, user_id, cid, complete=not bool(candidates))
    primary.is_primary = True
    await session.commit()
    return primary


async def list_messages(session, user_id, *, before=None, page_size=50):
    # Public history spans the user's old threads; their execution states remain separate.
    query = select(ConversationMessage).join(Conversation).where(Conversation.user_id == user_id)
    if before is not None:
        cursor = await session.scalar(query.where(ConversationMessage.id == before))
        if cursor is None:
            raise HistoryError("INVALID_HISTORY_CURSOR")
        query = query.where(tuple_(ConversationMessage.created_at, ConversationMessage.id)
                            < tuple_(cursor.created_at, cursor.id))
    rows = list(await session.scalars(query.order_by(ConversationMessage.created_at.desc(),
        ConversationMessage.id.desc()).limit(page_size + 1)))
    has_more = len(rows) > page_size
    page = list(reversed(rows[:page_size]))
    return page, page[0].id if has_more else None


def parse_thread(thread_id, user_id):
    prefix = f"user:{user_id}:conversation:"
    if not isinstance(thread_id, str) or not thread_id.startswith(prefix):
        return None
    try:
        return UUID(thread_id[len(prefix):])
    except ValueError:
        return None


async def user_threads(checkpointer, user_id, *, pool=None):
    """Find current-user legacy IDs, ordered by the latest checkpoint timestamp."""
    if pool is not None:
        async with pool.connection() as connection:
            rows = await (await connection.execute(
                "SELECT thread_id, max(checkpoint_id) AS latest FROM checkpoints "
                "WHERE checkpoint_ns = '' AND thread_id LIKE %s GROUP BY thread_id ORDER BY latest DESC",
                (f"user:{user_id}:conversation:%",))).fetchall()
        configs = [{"configurable": {"thread_id": row["thread_id"]}} for row in rows]
        checkpoints = [await checkpointer.aget_tuple(config) for config in configs]
    else:
        # In-memory checkpointers used by deterministic tests have no SQL pool.
        latest = {}
        async for row in checkpointer.alist(None):
            cfg = row.config["configurable"]
            if not cfg.get("checkpoint_ns") and parse_thread(cfg.get("thread_id"), user_id):
                latest.setdefault(cfg["thread_id"], row)
        checkpoints = latest.values()
    return [(parse_thread(row.config["configurable"]["thread_id"], user_id),
             datetime.fromisoformat(row.checkpoint["ts"])) for row in checkpoints if row is not None
            and parse_thread(row.config["configurable"]["thread_id"], user_id)]


async def primary_history(session, user_id, graph, *, before=None, page_size=50, pool=None):
    primary = await session.scalar(select(Conversation).where(
        Conversation.user_id == user_id, Conversation.is_primary.is_(True)))
    if primary is None:
        threads = await user_threads(graph.checkpointer, user_id, pool=pool)
        primary = await bind_primary(session, user_id, threads)
    snapshot = await graph.aget_state({"configurable": {"thread_id": f"user:{user_id}:conversation:{primary.id}"}})
    if snapshot.values.get("history_outbox"):
        await write_messages(session, user_id, primary.id, snapshot.values["history_outbox"])
    rows, next_before = await list_messages(session, user_id, before=before, page_size=page_size)
    incomplete = await session.scalar(select(Conversation.id).where(
        Conversation.user_id == user_id, Conversation.history_complete.is_(False)).limit(1))
    return primary.id, snapshot, rows, next_before, bool(primary.history_complete and not incomplete)


async def recover_messages(checkpointer, user_id, conversation_id):
    """Recover only observed public inputs and saved public replies, never summaries.

    The first observed checkpoint timestamp is retained where the original send
    timestamp is unavailable. Missing confirmations/trimmed text remain missing.
    """
    from langchain_core.messages import HumanMessage
    from app.agents.messages import user_text
    from app.agents.state import history_state_reader
    config = {"configurable": {"thread_id": f"user:{user_id}:conversation:{conversation_id}", "checkpoint_ns": ""}}
    records, observed = {}, {}
    reader = history_state_reader(checkpointer)
    # PostgreSQL alist holds a saver cursor/lock while yielding. Finish listing
    # before nested get_state calls, or a single-connection saver deadlocks.
    checkpoints = [(row.config, row.checkpoint["ts"]) async for row in checkpointer.alist(config)]
    for checkpoint_config, stamp in checkpoints:
        # Delta-backed channels may be absent or snapshot sentinels in alist.
        # The public graph API hydrates both legacy and incremental checkpoints.
        values = (await reader.aget_state(checkpoint_config)).values
        for record in values.get("history_outbox", {}).values():
            records[record["id"]] = dict(record)
        current = values.get("public_turn", {})
        if current.get("input"):
            record = current["input"]
            records[record["id"]] = dict(record)
        for message in values.get("messages", []):
            if not isinstance(message, HumanMessage) or not message.id:
                continue
            # Framework/system/tool/model messages are never public inputs.
            identity = str(message.id).split(":", 1)[0]
            try:
                UUID(identity)
            except ValueError:
                continue
            content = user_text(message)
            content = re.sub(r"^(?:Unassigned supplement DATA: |For item [^:]+: )", "", content)
            attachments = message.additional_kwargs.get("images", [])
            content = "\n".join(filter(None, [content, *[f"[Image attached: {i['mime_type']}]" for i in attachments]]))
            if not content:
                continue
            key = (identity, str(message.id))
            previous = observed.get(key)
            if previous is None or stamp < previous[1]:
                observed[key] = (content, stamp)
        for rid, saved in values.get("requests", {}).items():
            result = saved.get("state", saved)
            questions = [(i.get("display") or {}).get("question") for i in result.get("items", []) if i.get("status") in {"NEEDS_INPUT", "NEEDS_CONFIRMATION"}]
            content = "\n".join(filter(None, [public_text(saved.get("answer", "")), *dict.fromkeys(q for q in questions if q)]))
            if content:
                record = message_record(conversation_id, rid, "ASSISTANT", content, created_at=stamp)
                previous = records.get(record["id"])
                if previous is None or stamp < previous["created_at"]:
                    records[record["id"]] = record
    grouped = {}
    for (identity, mid), (content, stamp) in sorted(observed.items(), key=lambda v: (v[1][1], v[0])):
        entry = grouped.setdefault(identity, {"content": [], "created_at": stamp})
        entry["content"].append(content)
    for identity, entry in grouped.items():
        record = message_record(conversation_id, identity, "USER", "\n".join(entry["content"]), created_at=entry["created_at"])
        records.setdefault(record["id"], record)
    return records
