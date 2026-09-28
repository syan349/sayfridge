import asyncio
import json
from types import SimpleNamespace
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from sqlalchemy import select, func

from app.agents.workflow import build_agent_graph
from app.db.models import InventoryOperation
from app.api.routes import agent as api
from app.agents import locking
from inventory_test_support import inventory_context, seed_inventory
from auth_test_support import exercise
from test_agent_workflow import ScriptModel, call, intake

pytestmark = pytest.mark.postgres


def parse_events(response):
    return [json.loads(line[6:]) for line in response.text.splitlines() if line.startswith("data: ")]


def test_api_confirm_stale_replay_and_user_isolation(inventory_context, monkeypatch):
    c = inventory_context
    item = seed_inventory(c)
    url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
    monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
    async def scenario(client, sessions):
        proposed = {"item_key": "rice", "original_text": "two cups", "action": "CONSUME", "inventory_item_id": str(item.id),
            "quantity_value": "2", "quantity_unit": "cup", "estimate": {"amount": "0.2", "unit": "kg", "source": "MODEL_KNOWLEDGE", "rationale": "about 100g per cup"}}
        graph = build_agent_graph(ScriptModel([call([proposed])], intents=[intake([proposed])]), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        async def resources():
            return SimpleNamespace(graph=graph)
        monkeypatch.setattr(api, "get_agent_resources", resources)
        request_id, conversation_id = str(uuid4()), str(uuid4())
        body = {"message": "Use two cups", "request_id": request_id, "conversation_id": conversation_id, "as_of": "2026-09-25"}
        response = await client.post("/api/v1/agent/chat", json=body, headers=c[6])
        assert response.status_code == 200
        events = parse_events(response)
        assert not any(e["type"] == "error" for e in events), events
        pause = next(e["data"] for e in events if e["type"] == "action_required")
        waiting = pause["items"][0]
        state = (await client.get(f"/api/v1/agent/conversations/{conversation_id}/state", headers=c[6])).json()
        assert state["status"] == "WAITING_INPUT" and "messages" not in state
        blocked = await client.post("/api/v1/agent/chat", json={**body, "request_id": str(uuid4())}, headers=c[6])
        assert blocked.status_code == 409
        resume = {"conversation_id": conversation_id, "interrupt_id": pause["interrupt_id"], "request_id": str(uuid4()),
            "responses": [{"item_id": waiting["item_id"], "proposal_id": str(uuid4()), "decision": "confirm"}]}
        assert (await client.post("/api/v1/agent/resume", json=resume, headers=c[6])).status_code == 409
        resume["responses"][0]["proposal_id"] = waiting["proposal_id"]
        response = await client.post("/api/v1/agent/resume", json=resume, headers=c[6])
        events = parse_events(response)
        assert not any(e["type"] == "error" for e in events), events
        assert events[-1]["status"] == "COMPLETED"
        assert events[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
        replay = await client.post("/api/v1/agent/resume", json=resume, headers=c[6])
        assert parse_events(replay)[-1]["status"] == "COMPLETED"
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
        from app.core.security import create_access_token
        from app.core.config import get_settings
        other = {"Authorization": "Bearer " + create_access_token(c[2].id, get_settings().jwt_secret_key, 15)}
        assert (await client.get(f"/api/v1/agent/conversations/{conversation_id}/state", headers=other)).status_code == 404
        assert (await client.post("/api/v1/agent/resume", json=resume, headers=other)).status_code == 409
    asyncio.run(exercise(c[0], scenario))


def test_conversation_lock_is_cross_connection(inventory_context, monkeypatch):
    url = inventory_context[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
    async def scenario():
        user, conversation = uuid4(), uuid4()
        async with locking.conversation_lock(user, conversation):
            with pytest.raises(locking.ConversationBusy):
                async with locking.conversation_lock(user, conversation):
                    pass
        async with locking.conversation_lock(user, conversation):
            pass
    asyncio.run(scenario())


def test_structured_target_selection_executes_without_extra_confirmation(inventory_context, monkeypatch):
    c = inventory_context
    first, second = seed_inventory(c), seed_inventory(c)
    url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
    monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
    async def scenario(client, sessions):
        action = {"item_key": "rice", "original_text": "use 1 kg rice", "action": "CONSUME", "item_query": "Rice", "quantity_value": "1", "quantity_unit": "kg"}
        graph = build_agent_graph(ScriptModel([call([action])], intents=[intake([action])]), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        async def resources():
            return SimpleNamespace(graph=graph)
        monkeypatch.setattr(api, "get_agent_resources", resources)
        cid = str(uuid4())
        events = parse_events(await client.post("/api/v1/agent/chat", headers=c[6], json={"conversation_id": cid, "message": "use 1 kg rice"}))
        pause = next(e["data"] for e in events if e["type"] == "action_required")
        item = pause["items"][0]
        assert item["status"] == "NEEDS_INPUT"
        payload = {"conversation_id": cid, "interrupt_id": pause["interrupt_id"], "request_id": str(uuid4()),
            "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "answer", "selected_inventory_item_id": str(uuid4())}]}
        assert (await client.post("/api/v1/agent/resume", headers=c[6], json=payload)).status_code == 422
        payload["responses"][0]["selected_inventory_item_id"] = str(second.id)
        events = parse_events(await client.post("/api/v1/agent/resume", headers=c[6], json=payload))
        assert not any(e["type"] == "action_required" for e in events)
        assert events[-1]["data"]["items"][0]["result"]["inventory"]["id"] == str(second.id)
    asyncio.run(exercise(c[0], scenario))


def test_restart_after_commit_before_checkpoint_does_not_double_apply(inventory_context, monkeypatch):
    from psycopg import AsyncConnection
    from psycopg.rows import dict_row
    from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
    from app.agents import workflow
    from app.agents.state import AgentContext
    from test_agent_workflow import initial
    c = inventory_context
    item = seed_inventory(c)
    class SimulatedCrash(BaseException):
        pass
    original = workflow.execute_action
    async def commit_then_crash(*args, **kwargs):
        await original(*args, **kwargs)
        raise SimulatedCrash()
    async def scenario(client, sessions):
        conninfo = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(conninfo, options=f"-csearch_path={c[0][1]}", autocommit=True, row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            store = InMemoryStore()
            proposal = {"item_key": "rice", "original_text": "use 1 kg", "action": "CONSUME", "inventory_item_id": str(item.id), "quantity_value": "1", "quantity_unit": "kg"}
            graph = build_agent_graph(ScriptModel([call([proposal])], intents=[intake([proposal])]), checkpointer=saver, store=store, session_factory=sessions, tools=[])
            config = {"configurable": {"thread_id": "restart"}, "recursion_limit": 128}
            context = AgentContext(c[1].id, None, uuid4())
            monkeypatch.setattr(workflow, "execute_action", commit_then_crash)
            with pytest.raises(SimulatedCrash):
                await graph.ainvoke(initial(), config, context=context, durability="sync")
            monkeypatch.setattr(workflow, "execute_action", original)
            rebuilt = build_agent_graph(ScriptModel([]), checkpointer=saver, store=store, session_factory=sessions, tools=[])
            result = await rebuilt.ainvoke(None, config, context=context, durability="sync")
            assert result["items"][0]["status"] == "SUCCEEDED"
            assert result["items"][0]["result"]["replayed"]
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
    asyncio.run(exercise(c[0], scenario))
