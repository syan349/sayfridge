"""Three rolling compressions and recovery across durable checkpoint boundaries."""
import asyncio
import json
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langgraph.store.memory import InMemoryStore
from langgraph.graph import StateGraph, START
from psycopg import AsyncConnection
from psycopg.rows import dict_row
from sqlalchemy import select, func

from app.agents import workflow
from app.agents.context_budget import Budget
from app.agents.state import AgentContext, AgentState
from app.api.routes import agent as api
from app.db.models import ConversationMessage, InventoryItem, InventoryOperation, StorageSpace
from auth_test_support import exercise
from inventory_test_support import inventory_context
from test_agent_workflow import ScriptModel, intake
from test_agent_api_postgres import parse_events
from test_agent_history_postgres import configure_api

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


class Crash(BaseException):
    pass


class FactModel(ScriptModel):
    budget = Budget(trigger=45000, target=28000, limit=160000, model_limit=160000, output=1000)
    summaries = 0
    seen = None
    def __init__(self):
        super().__init__([], intents=[])
    async def ainvoke(self, messages, **kwargs):
        tags = kwargs.get("config", {}).get("tags", [])
        if "agent_summary" in tags:
            data = json.loads(messages[-1].content)
            if self.summaries:
                assert "peanut allergy" in data["previous_summary"]
            text = data["previous_summary"] + "\n" + "\n".join(m["content"] for m in data["older_messages"])
            assert "peanut allergy" in text
            self.summaries += 1
            name = "Mei" if "correct name is Mei" in text else "May"
            return AIMessage(content=f"peanut allergy; correct name is {name}; user's existing background persists.")
        self.seen = messages
        if "agent_intake" in tags:
            return intake()
        return AIMessage(content="Public reply")


def test_three_compressions_restart_and_public_history_survives(inventory_context, monkeypatch):
    c = inventory_context
    async def scenario(client, sessions):
        url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(url, options=f"-csearch_path={c[0][1]}", autocommit=True,
                row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            model = FactModel()
            cid = uuid4()
            last_body = None
            for n in range(18):
                graph = workflow.build_agent_graph(model, checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
                configure_api(c, graph, monkeypatch)
                important = "peanut allergy; my name is May" if n == 0 else "The correct name is Mei" if n == 3 else f"recent topic {n}"
                last_body = {"conversation_id": str(cid), "request_id": str(uuid4()), "message": important + " " + "x" * 7800}
                events = parse_events(await client.post("/api/v1/agent/chat", headers=c[6], json=last_body))
                assert events[-1]["type"] == "done", events[-1]
            snapshot = await graph.aget_state(api._config(c[1].id, cid))
            assert model.summaries >= 3
            assert "peanut allergy" in snapshot.values["conversation_summary"] and "Mei" in snapshot.values["conversation_summary"]
            assert snapshot.values["summary_cursor"] and snapshot.values["summary_pending_ids"] == []
            assert len([m for m in snapshot.values["messages"] if isinstance(m, HumanMessage)]) < 18
            assert snapshot.values["messages"][-2].content == last_body["message"]
            assert any("peanut allergy" in str(m.content) and "Mei" in str(m.content) for m in model.seen)
            page = (await client.get("/api/v1/agent/chat", headers=c[6])).json()
            assert len(page["messages"]) == 36 and page["messages"][0]["content"].startswith("peanut allergy")
            assert all("Cumulative conversation" not in m["content"] for m in page["messages"])
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(ConversationMessage)) == 36
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("after_save", [False, True])
def test_crash_at_summary_save_never_removes_unpersisted_history(inventory_context, monkeypatch, after_save):
    c = inventory_context
    async def scenario(client, sessions):
        url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(url, options=f"-csearch_path={c[0][1]}", autocommit=True,
                row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            original = saver.aput
            broken = False
            async def fail(config, checkpoint, metadata, new_versions):
                nonlocal broken
                if not broken and checkpoint["channel_values"].get("summary_pending_ids"):
                    broken = True
                    if after_save:
                        await original(config, checkpoint, metadata, new_versions)
                    raise Crash()
                return await original(config, checkpoint, metadata, new_versions)
            monkeypatch.setattr(saver, "aput", fail)
            model = FactModel()
            graph = workflow.build_agent_graph(model, checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
            rid, cid = uuid4(), uuid4()
            messages = [HumanMessage(content=("peanut allergy; correct name is Mei. " if n == 0 else "older topic ") + "x" * 7800, id=str(uuid4())) for n in range(10)]
            config = api._config(c[1].id, cid)
            context = AgentContext(c[1].id, None, cid)
            with pytest.raises(Crash):
                await graph.ainvoke({"messages": messages, "turn_id": str(rid), "request_fingerprint": "old",
                    "items": [], "context_next": "prepare_context"}, config, context=context, durability="sync")
            before = await graph.aget_state(config)
            assert len(before.values["messages"]) == 10
            count = model.summaries
            monkeypatch.setattr(saver, "aput", original)
            # The replacement process uses a new saver and graph, not cached state.
            rebuilt = workflow.build_agent_graph(model, checkpointer=AsyncPostgresSaver(conn), store=InMemoryStore(), session_factory=sessions, tools=[])
            result = await rebuilt.ainvoke(None, config, context=context, durability="sync")
            assert "peanut allergy" in result["conversation_summary"]
            assert len(result["messages"]) < 10 and result["summary_pending_ids"] == []
            assert model.summaries == count  # staged pending writes survive either crash boundary
    asyncio.run(exercise(c[0], scenario))


def test_upgrade_recovers_legacy_compact_model_node_without_reclassifying(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(url, options=f"-csearch_path={c[0][1]}", autocommit=True,
                row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            builder = StateGraph(AgentState)
            builder.add_node("old_execution", lambda s: {"route": "FINISH"})
            def crash(s):
                raise Crash()
            builder.add_node("compact_model", crash)
            builder.add_edge(START, "old_execution")
            builder.add_edge("old_execution", "compact_model")
            old = builder.compile(checkpointer=saver)
            cid, rid = uuid4(), uuid4()
            config = api._config(c[1].id, cid)
            with pytest.raises(Crash):
                await old.ainvoke({"messages": [HumanMessage(content="old task")], "turn_id": str(rid),
                    "request_fingerprint": "old", "items": []}, config, durability="sync")
            rebuilt = workflow.build_agent_graph(ScriptModel([]), checkpointer=AsyncPostgresSaver(conn), store=InMemoryStore(), session_factory=sessions, tools=[])
            result = await rebuilt.ainvoke(None, config, context=AgentContext(c[1].id, None, cid), durability="sync")
            assert result["route"] == "END" and not (await rebuilt.aget_state(config)).next
    asyncio.run(exercise(c[0], scenario))


def test_pending_task_survives_three_compressions_independent_queries_and_restart(inventory_context, monkeypatch):
    from app.agents import continuation
    from app.agents.continuation import Continuation, ContinuationAnswer
    from test_agent_workflow import call
    from sqlalchemy import update
    c = inventory_context
    action = {"item_key": "rice", "original_text": "add 2 kg rice", "action": "CREATE_STOCK",
              "item_definition_id": str(c[5].id), "quantity_value": "2", "quantity_unit": "kg"}
    class PendingModel(FactModel):
        def __init__(self):
            super().__init__()
            self.proposal = False
        async def ainvoke(self, messages, **kwargs):
            tags = kwargs.get("config", {}).get("tags", [])
            latest = next((m.content for m in reversed(messages) if isinstance(m, HumanMessage)), "")
            if "agent_intake" in tags and "I bought 2 kg rice" in latest:
                self.proposal = True
                return intake([action])
            if "agent_internal" in tags and self.proposal:
                self.proposal = False
                return call([action])
            if "agent_internal" in tags and "Put that rice" in latest:
                return call([{**action, "storage_space_id": str(c[4].id)}])
            return await super().ainvoke(messages, **kwargs)
    async def route(model, items, message, **kwargs):
        if "Put that rice" in message:
            return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=items[0]["item_id"],
                decision="answer", message=message, evidence=message)])
        return Continuation(mode="QUERY")
    monkeypatch.setattr(continuation, "interpret_continuation", route)
    async def scenario(client, sessions):
        async with sessions() as session:
            await session.execute(update(StorageSpace).where(StorageSpace.user_id == c[1].id).values(is_default=False))
            await session.commit()
        url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(url, options=f"-csearch_path={c[0][1]}", autocommit=True,
                row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            model, cid = PendingModel(), uuid4()
            def rebuild():
                graph = workflow.build_agent_graph(model, checkpointer=AsyncPostgresSaver(conn), store=InMemoryStore(), session_factory=sessions, tools=[])
                configure_api(c, graph, monkeypatch)
                return graph
            async def chat(message):
                events = parse_events(await client.post("/api/v1/agent/chat", headers=c[6], json={
                    "conversation_id": str(cid), "request_id": str(uuid4()), "message": message}))
                assert events[-1]["type"] == "done", events[-1]
                return events[-1]["data"]
            graph = rebuild()
            await chat("peanut allergy; my name is May " + "x" * 7700)
            waiting = await chat("I bought 2 kg rice; please record it.")
            original = waiting["items"][0]
            assert original["error"]["code"] == "SPACE_REQUIRED"
            for n in range(16):
                graph = rebuild()
                reply = await chat(("The correct name is Mei " if n == 0 else f"Independent question {n} ") + "x" * 7700)
                pending = reply["items"][0]
                assert pending["item_id"] == original["item_id"] and pending["proposal_id"] == original["proposal_id"]
            assert model.summaries >= 3
            snapshot = await graph.aget_state(api._config(c[1].id, cid))
            assert any(m.id == original["item_id"] or "I bought 2 kg rice" in str(m.content) for m in snapshot.values["messages"])
            assert snapshot.values["items"][0]["draft"]["quantity_value"] == "2"
            graph = rebuild()
            final = await chat(f"Put that rice in {c[4].name}.")
            assert final["items"][0]["status"] == "SUCCEEDED" and final["items"][0]["item_id"] == original["item_id"]
            async with sessions() as session:
                stock = await session.scalar(select(InventoryItem))
                assert stock.confirmed_current_amount == 2 and stock.confirmed_current_unit == "kg"
            page = (await client.get("/api/v1/agent/chat", headers=c[6])).json()
            assert len(page["messages"]) == 38
    asyncio.run(exercise(c[0], scenario))


def test_restart_after_receiving_confirmation_recovers_without_a_live_interrupt(inventory_context, monkeypatch):
    from langgraph.types import Command
    from inventory_test_support import seed_inventory
    from app.services.conversation_history import resume_input
    from app.schemas.agent_actions import AgentResumeRequest
    from test_agent_workflow import call
    c = inventory_context
    rice = seed_inventory(c)
    async def scenario(client, sessions):
        url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
        async with await AsyncConnection.connect(url, options=f"-csearch_path={c[0][1]}", autocommit=True,
                row_factory=dict_row, prepare_threshold=0) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            action = {"item_key": "rice", "original_text": "use 1 kg rice", "action": "CONSUME",
                      "inventory_item_id": str(rice.id), "quantity_value": "1", "quantity_unit": "kg", "confirmation_requested": True}
            graph = workflow.build_agent_graph(ScriptModel([call([action])], intents=[intake([action])]),
                checkpointer=saver, store=InMemoryStore(), session_factory=sessions, tools=[])
            cid, rid = uuid4(), uuid4()
            config = api._config(c[1].id, cid)
            context = AgentContext(c[1].id, None, cid)
            await graph.ainvoke({"messages": [HumanMessage(content="use 1 kg rice", id=str(rid))], "turn_id": str(rid),
                "request_fingerprint": "old", "items": []}, config, context=context, durability="sync")
            waiting = api._state(await graph.aget_state(config))
            item = waiting["items"][0]
            payload = AgentResumeRequest.model_validate({"conversation_id": str(cid), "request_id": str(uuid4()),
                "interrupt_id": waiting["interrupt_id"], "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "confirm"}]})
            data = payload.model_dump(mode="json")
            data["_public_input"] = resume_input(cid, payload.request_id, payload, waiting["items"])
            original_put = saver.aput
            async def fail(config, checkpoint, metadata, versions):
                result = await original_put(config, checkpoint, metadata, versions)
                if checkpoint["channel_values"].get("resume_payload"):
                    raise Crash()
                return result
            monkeypatch.setattr(saver, "aput", fail)
            with pytest.raises(Crash):
                await graph.ainvoke(Command(resume={payload.interrupt_id: data}), config, context=context, durability="sync")
            snapshot = await graph.aget_state(config)
            assert api._state(snapshot)["status"] == "RECOVERABLE" and not api._interrupts(snapshot)
            rebuilt = workflow.build_agent_graph(ScriptModel([]), checkpointer=AsyncPostgresSaver(conn),
                store=InMemoryStore(), session_factory=sessions, tools=[])
            configure_api(c, rebuilt, monkeypatch)
            body = payload.model_dump(mode="json")
            for _ in range(2):
                response = await client.post("/api/v1/agent/resume", headers=c[6], json=body)
                assert response.status_code == 200, response.text
                assert parse_events(response)[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
    asyncio.run(exercise(c[0], scenario))
