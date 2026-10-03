"""Public chat history, legacy identity, durable recovery and ownership."""
import asyncio
from datetime import datetime, timezone, timedelta
from types import SimpleNamespace
from uuid import UUID, uuid4, uuid5

import pytest
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langgraph.store.memory import InMemoryStore
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from sqlalchemy import select, func, text

from app.api.routes import agent as api
from app.agents import locking
from app.agents.state import AgentContext
from app.agents.workflow import build_agent_graph
from app.db.models import Conversation, ConversationMessage, InventoryOperation, AgentInventoryAction
from app.services import conversation_history as history
from auth_test_support import exercise
from inventory_test_support import inventory_context, seed_inventory
from test_agent_workflow import ScriptModel, call, intake
from test_agent_api_postgres import parse_events

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


def configure_api(c, graph, monkeypatch):
    url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
    monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
    async def resources():
        return SimpleNamespace(graph=graph)
    monkeypatch.setattr(api, "get_agent_resources", resources)


def test_primary_concurrent_open_and_legacy_ids_remain_independent(inventory_context, monkeypatch):
    c = inventory_context
    async def scenario(client, sessions):
        graph = build_agent_graph(ScriptModel([AIMessage(content="First reply"), AIMessage(content="Second reply")],
            intents=[intake(), intake()]), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        configure_api(c, graph, monkeypatch)
        responses = await asyncio.gather(*[client.get("/api/v1/agent/chat", headers=c[6]) for _ in range(3)])
        assert all(r.status_code == 200 for r in responses), [r.text for r in responses]
        primary_id = responses[0].json()["conversation_id"]
        assert {r.json()["conversation_id"] for r in responses} == {primary_id}
        assert responses[0].json()["history_complete"]
        rid = uuid4()
        legacy = {"message": "Web first turn", "request_id": str(rid)}
        stream = await client.post("/api/v1/agent/chat", json=legacy, headers=c[6])
        events = parse_events(stream)
        legacy_id = str(uuid5(c[1].id, f"agent:{rid}"))
        assert events[0]["conversation_id"] == legacy_id != primary_id
        mobile_id = str(uuid4())
        body = {"message": "Mobile first turn", "request_id": str(uuid4()), "conversation_id": mobile_id}
        events = parse_events(await client.post("/api/v1/agent/chat", json=body, headers=c[6]))
        assert events[0]["conversation_id"] == mobile_id
        repeated = parse_events(await client.post("/api/v1/agent/chat", json=body, headers=c[6]))
        assert repeated[-1] == events[-1]
        page = (await client.get("/api/v1/agent/chat", headers=c[6])).json()
        assert page["conversation_id"] == primary_id
        assert [m["role"] for m in page["messages"]] == ["USER", "ASSISTANT"] * 2
        assert [m["content"] for m in page["messages"]] == ["Web first turn", "First reply", "Mobile first turn", "Second reply"]
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(Conversation).where(Conversation.is_primary)) == 1
    asyncio.run(exercise(c[0], scenario))


def test_latest_legacy_pending_thread_binds_and_old_proposal_remains_valid(inventory_context, monkeypatch):
    c = inventory_context
    rice = seed_inventory(c)
    async def scenario(client, sessions):
        saver = InMemorySaver()
        old_id, latest_id = uuid4(), uuid4()
        draft = {"item_key": "rice", "original_text": "use 1 kg rice", "action": "CONSUME", "inventory_item_id": str(rice.id),
                 "quantity_value": "1", "quantity_unit": "kg", "confirmation_requested": True}
        graph = build_agent_graph(ScriptModel([AIMessage(content="Old reply"), call([draft])], intents=[intake(), intake([draft])]),
            checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
        for cid, message in ((old_id, "old topic"), (latest_id, "use 1 kg rice")):
            rid = str(uuid4())
            await graph.ainvoke({"messages": [HumanMessage(content=message, id=rid)], "turn_id": rid,
                "request_fingerprint": "legacy", "items": [], "context_next": "prepare_context"}, api._config(c[1].id, cid),
                context=AgentContext(c[1].id, None, cid), durability="sync")
        before = await graph.aget_state(api._config(c[1].id, latest_id))
        item = before.values["items"][0]
        configure_api(c, graph, monkeypatch)
        opened = await client.get("/api/v1/agent/chat", headers=c[6])
        assert opened.status_code == 200, opened.text
        view = opened.json()
        assert view["conversation_id"] == str(latest_id)
        assert not view["history_complete"] and view["messages"] == []
        assert view["state"]["items"][0]["proposal_id"] == item["proposal_id"]
        resume = {"conversation_id": str(latest_id), "request_id": str(uuid4()), "interrupt_id": view["state"]["interrupt_id"],
                  "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "confirm"}]}
        response = await client.post("/api/v1/agent/resume", json=resume, headers=c[6])
        assert parse_events(response)[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
        assert (await client.get(f"/api/v1/agent/conversations/{old_id}/state", headers=c[6])).status_code == 200
        page = (await client.get("/api/v1/agent/chat", headers=c[6])).json()
        assert page["messages"][0]["content"].startswith("[Confirmed:")
        assert "Updated" in page["messages"][1]["content"]
    asyncio.run(exercise(c[0], scenario))


def test_history_keyset_order_limits_and_foreign_cursor(inventory_context, monkeypatch):
    c = inventory_context
    async def scenario(client, sessions):
        graph = build_agent_graph(ScriptModel([]), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        configure_api(c, graph, monkeypatch)
        stamp = datetime(2026, 10, 1, tzinfo=timezone.utc)
        async with sessions() as session:
            for uid, count in ((c[1].id, 107), (c[2].id, 1)):
                cid = uuid4()
                records = [history.message_record(cid, uuid4(), "USER", f"{uid}:{n}", created_at=(stamp + timedelta(seconds=n // 3)).isoformat()) for n in range(count)]
                await history.write_messages(session, uid, cid, {r["id"]: r for r in records}, complete=True)
            foreign = await session.scalar(select(ConversationMessage.id).join(Conversation).where(Conversation.user_id == c[2].id))
            expected = list(await session.scalars(select(ConversationMessage.id).join(Conversation).where(Conversation.user_id == c[1].id)
                .order_by(ConversationMessage.created_at, ConversationMessage.id)))
        assert len((await client.get("/api/v1/agent/chat", headers=c[6])).json()["messages"]) == 50
        collected, cursor = [], None
        while True:
            params = {"page_size": 40, **({"before": cursor} if cursor else {})}
            page = (await client.get("/api/v1/agent/chat", headers=c[6], params=params)).json()
            collected = [UUID(m["id"]) for m in page["messages"]] + collected
            cursor = page.get("next_before")
            if not cursor:
                break
        assert collected == expected and len(set(collected)) == 107
        assert (await client.get("/api/v1/agent/chat", headers=c[6], params={"page_size": 101})).status_code == 422
        for cursor in (foreign, uuid4()):
            bad = await client.get("/api/v1/agent/chat", headers=c[6], params={"before": str(cursor)})
            assert bad.status_code == 422 and bad.json()["detail"]["code"] == "INVALID_HISTORY_CURSOR"
        assert (await client.get("/api/v1/agent/chat")).status_code == 401
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("after_commit", [False, True])
def test_history_failure_then_restart_replay_does_not_repeat_inventory(inventory_context, monkeypatch, after_commit):
    c = inventory_context
    rice = seed_inventory(c)
    async def scenario(client, sessions):
        url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(url, options=f"-csearch_path={c[0][1]}", autocommit=True,
                row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            action = {"item_key": "rice", "original_text": "use 1 kg rice", "action": "CONSUME", "inventory_item_id": str(rice.id),
                      "quantity_value": "1", "quantity_unit": "kg"}
            graph = build_agent_graph(ScriptModel([call([action])], intents=[intake([action])]), checkpointer=saver,
                store=InMemoryStore(), session_factory=sessions, tools=[])
            configure_api(c, graph, monkeypatch)
            original = history.write_messages
            async def fail(*args, **kwargs):
                if after_commit:
                    await original(*args, **kwargs)
                raise ConnectionError("simulated history acknowledgement failure")
            monkeypatch.setattr(history, "write_messages", fail)
            body = {"conversation_id": str(uuid4()), "request_id": str(uuid4()), "message": "use 1 kg rice"}
            first = parse_events(await client.post("/api/v1/agent/chat", json=body, headers=c[6]))
            assert first[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
            snapshot = await graph.aget_state(api._config(c[1].id, body["conversation_id"]))
            assert len(snapshot.values["history_outbox"]) == 2
            monkeypatch.setattr(history, "write_messages", original)
            rebuilt = build_agent_graph(ScriptModel([]), checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
            configure_api(c, rebuilt, monkeypatch)
            repeated = parse_events(await client.post("/api/v1/agent/chat", json=body, headers=c[6]))
            assert repeated[-1] == first[-1]
            page = (await client.get("/api/v1/agent/chat", headers=c[6])).json()
            assert len(page["messages"]) == 2
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
                assert await session.scalar(select(func.count()).select_from(ConversationMessage)) == 2
    asyncio.run(exercise(c[0], scenario))


def test_recover_observed_history_is_idempotent_and_never_exposes_internal_data(inventory_context, monkeypatch):
    c = inventory_context
    async def scenario(client, sessions):
        saver = InMemorySaver()
        cid, rid = uuid4(), uuid4()
        graph = build_agent_graph(ScriptModel([AIMessage(content="Public reply")], intents=[intake()]),
            checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
        await graph.ainvoke({"messages": [SystemMessage(content="private prompt"), HumanMessage(content="Actual input", id=str(rid))],
            "conversation_summary": "A made-up reconstruction must never become public", "turn_id": str(rid), "request_fingerprint": "old",
            "context_next": "prepare_context", "items": []}, api._config(c[1].id, cid), context=AgentContext(c[1].id, None, cid))
        records = await history.recover_messages(saver, c[1].id, cid)
        assert {r["content"] for r in records.values()} == {"Actual input", "Public reply"}
        async with sessions() as session:
            for _ in range(2):
                await history.write_messages(session, c[1].id, cid, records)
            assert await session.scalar(select(func.count()).select_from(ConversationMessage)) == 2
        configure_api(c, graph, monkeypatch)
        response = await client.get("/api/v1/agent/chat", headers=c[6])
        assert response.status_code == 200
        assert not response.json()["history_complete"]
        assert "private prompt" not in response.text and "made-up" not in response.text
        assert await history.recover_messages(saver, c[2].id, cid) == {}
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("decision", ["confirm", "cancel", "answer", "edit"])
def test_explicit_actions_and_batch_confirmation_keep_public_history_idempotent(inventory_context, monkeypatch, decision):
    c = inventory_context
    async def scenario(client, sessions):
        actions = [{"item_key": f"rice-{n}", "original_text": "add 1 kg rice", "action": "CREATE_STOCK",
                    "item_definition_id": str(c[5].id), "storage_space_id": str(c[4].id),
                    "quantity_value": "1", "quantity_unit": "kg", "confirmation_requested": True}
                   for n in range(2)]
        revised = [{**a, "quantity_value": "0.5"} for a in actions]
        graph = build_agent_graph(ScriptModel([call(actions), call(revised)], intents=[intake(actions)]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        configure_api(c, graph, monkeypatch)
        cid = str(uuid4())
        first = parse_events(await client.post("/api/v1/agent/chat", headers=c[6], json={"conversation_id": cid, "message": "Add 1 kg in each of two separate Rice batches; ask me first"}))[-1]["data"]
        assert all(i["status"] == "NEEDS_CONFIRMATION" for i in first["items"])
        body = {"conversation_id": cid, "interrupt_id": first["interrupt_id"], "request_id": str(uuid4()),
            "responses": [{"item_id": i["item_id"], "proposal_id": i["proposal_id"], "decision": decision,
                           **({"message": "Use half a kilogram instead"} if decision in {"answer", "edit"} else {})} for i in first["items"]]}
        second = parse_events(await client.post("/api/v1/agent/resume", headers=c[6], json=body))[-1]["data"]
        if decision in {"answer", "edit"}:
            assert all(i["proposal_id"] != first["items"][n]["proposal_id"] for n, i in enumerate(second["items"]))
            body = {"conversation_id": cid, "interrupt_id": second["interrupt_id"], "request_id": str(uuid4()),
                "responses": [{"item_id": i["item_id"], "proposal_id": i["proposal_id"], "decision": "confirm"} for i in second["items"]]}
            second = parse_events(await client.post("/api/v1/agent/resume", headers=c[6], json=body))[-1]["data"]
        assert all(i["status"] == ("CANCELLED" if decision == "cancel" else "SUCCEEDED") for i in second["items"])
        await client.post("/api/v1/agent/resume", headers=c[6], json=body)
        page = (await client.get("/api/v1/agent/chat", headers=c[6])).json()
        assert len(page["messages"]) == (6 if decision in {"answer", "edit"} else 4)
        assert len({m["id"] for m in page["messages"]}) == len(page["messages"])
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(AgentInventoryAction)) == (0 if decision == "cancel" else 2)
    asyncio.run(exercise(c[0], scenario))


def test_migration_preserves_old_messages_and_only_limits_primary_rows(database):
    from alembic import command
    from alembic.config import Config
    from pathlib import Path
    from auth_test_support import make_user, seed_users
    user = make_user()
    seed_users(database, user)
    first, second, mid = uuid4(), uuid4(), uuid4()
    with database[2].begin() as conn:
        cfg = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
        cfg.attributes["connection"] = conn
        command.downgrade(cfg, "a261002_categories")
        conn.execute(text("INSERT INTO conversation(id,user_id) VALUES (:id,:uid)"), {"id": first, "uid": user.id})
        conn.execute(text("INSERT INTO conversation_message(id,conversation_id,role,content) VALUES (:id,:cid,'USER','real old text')"), {"id": mid, "cid": first})
        command.upgrade(cfg, "head")
        row = conn.execute(text("SELECT is_primary,history_complete FROM conversation WHERE id=:id"), {"id": first}).one()
        assert tuple(row) == (False, False)
        conn.execute(text("INSERT INTO conversation(id,user_id,is_primary) VALUES (:id,:uid,true)"), {"id": second, "uid": user.id})
        assert conn.scalar(text("SELECT content FROM conversation_message WHERE id=:id"), {"id": mid}) == "real old text"
    from sqlalchemy.exc import IntegrityError
    with pytest.raises(IntegrityError), database[2].begin() as conn:
        conn.execute(text("UPDATE conversation SET is_primary=true WHERE id=:id"), {"id": first})
