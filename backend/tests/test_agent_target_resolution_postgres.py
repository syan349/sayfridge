"""Real searches, stock validation and legacy SSE for target recovery."""
import asyncio
from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest
from agent_dialogue_support import Dialogue
from auth_test_support import exercise
from catalog_test_support import seed_definition
from inventory_test_support import (
    inventory_context as inventory_context,  # noqa: PLC0414 - export the pytest fixture
)
from inventory_test_support import seed_inventory, seed_space
from langchain_core.messages import AIMessage
from sqlalchemy.orm import Session
from test_agent_api_postgres import parse_events
from test_agent_workflow import ScriptModel, call, intake

from app.api.routes import agent as api
from app.db.models import InventoryItem, ItemDefinition
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import PreparationError, prepare_action

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


def invocation(name, **args):
    return AIMessage(content="", tool_calls=[{"name": name, "args": args, "id": str(uuid4()), "type": "tool_call"}])


def apples(c, **overrides):
    with Session(c[0][2]) as session:
        definition = session.get(ItemDefinition, c[5].id)
        definition.name, definition.normalized_name = "Apples", "apples"
        session.commit()
    return seed_inventory(c, initial_amount=Decimal(3), initial_unit="个",
        confirmed_current_amount=Decimal(3), confirmed_current_unit="个", **overrides)


def apple_action():
    return {"item_key": "apple", "original_text": "我又吃了一个苹果", "action": "CONSUME", "item_query": "苹果",
            "quantity_value": "1", "quantity_unit": "个"}


@pytest.mark.parametrize("multiple", [False, True])
def test_real_zero_search_inventory_pages_execute_or_offer_candidates(inventory_context, monkeypatch, multiple):
    c = inventory_context
    target = apples(c, expiry_date=date(2026, 10, 10))
    juice_def = seed_definition(c[0], c[3].id, name="Apple juice", normalized_name="apple juice")
    juice = seed_inventory(c, item_definition_id=juice_def.id, expiry_date=date(2026, 10, 1))
    other = apples(c, storage_space_id=seed_space(c[0], c[1].id, name="Garage").id,
                   expiry_date=date(2026, 10, 11)) if multiple else None
    action = apple_action()
    revised = {**action, "inventory_item_id": str(target.id)}
    async def scenario(client, sessions):
        model = ScriptModel([invocation("resolve_inventory_targets", queries=["苹果"]), call([action]),
                             invocation("list_inventory", q="", page=1, page_size=1),
                             invocation("list_inventory", q="", page=2, page_size=1), call([revised]), call([revised])],
                            intents=[intake([action], language="zh")])
        dialogue = Dialogue(client, c, sessions, model, monkeypatch)
        state = await dialogue.chat(action["original_text"])
        item = state["items"][0]
        snapshot = await dialogue.graph.aget_state(api._config(c[1].id, dialogue.conversation_id))
        calls = [t for m in snapshot.values["messages"] for t in getattr(m, "tool_calls", [])]
        assert [t["name"] for t in calls[:4]] == ["resolve_inventory_targets", "propose_inventory_actions", "list_inventory", "list_inventory"]
        if multiple:
            assert item["status"] == "NEEDS_INPUT"
            assert item["error"]["details"]["reason"] == "AMBIGUOUS"
            assert {r["id"] for r in item["error"]["details"]["candidates"]} == {str(target.id), str(other.id)}
            assert item["display"]["missing_fields"] == []
            assert (await dialogue.counts())[1] == 0
            # Existing client-selected ID and unchanged resume schema.
            body = {"conversation_id": dialogue.conversation_id, "request_id": str(uuid4()), "interrupt_id": state["interrupt_id"],
                    "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "answer",
                                   "selected_inventory_item_id": str(target.id)}]}
            response = await client.post("/api/v1/agent/resume", json=body, headers=c[6])
            item = parse_events(response)[-1]["data"]["items"][0]
        else:
            assert not any(e["type"] == "action_required" for e in dialogue.events)
            previous = dict(dialogue.body)
            replay = await dialogue.chat(previous["message"], request_id=previous["request_id"])
            assert replay["items"][0]["proposal_id"] == item["proposal_id"]
        assert item["status"] == "SUCCEEDED"
        assert Decimal(item["result"]["inventory"]["confirmed_current_amount"]) == 2
        assert (await dialogue.counts())[1:] == (1, 1)
        async with sessions() as session:
            assert (await session.get(InventoryItem, juice.id)).confirmed_current_amount == Decimal("2.5")
            if other:
                assert (await session.get(InventoryItem, other.id)).confirmed_current_amount == 3
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("have_other_stock", [False, True])
def test_no_match_waits_with_legacy_contract_then_answer_or_cancel(inventory_context, monkeypatch, have_other_stock):
    c, action = inventory_context, apple_action()
    if have_other_stock:
        # Rice is unrelated to apples and must never be consumed as a fallback.
        rice = seed_definition(c[0], c[3].id, name="Other rice", normalized_name="other rice")
        seed_inventory(c, item_definition_id=rice.id)
    async def scenario(client, sessions):
        model = ScriptModel([call([action]), invocation("list_inventory", q=""), call([action]), call([action])],
                            intents=[intake([action], language="zh")])
        dialogue = Dialogue(client, c, sessions, model, monkeypatch)
        state = await dialogue.chat(action["original_text"])
        item = state["items"][0]
        assert state["status"] == "WAITING_INPUT" and item["status"] == "NEEDS_INPUT"
        assert item["error"]["code"] == "TARGET_REQUIRED" and item["error"]["details"]["reason"] == "NO_MATCH"
        assert item["display"]["missing_fields"] == []
        assert "哪一批" not in item["display"]["question"]
        assert ("没有在库" in item["display"]["question"]) is not have_other_stock
        assert sum(e["type"] == "action_required" for e in dialogue.events) == 1
        restored = await dialogue.state()
        assert restored["interrupt_id"] == state["interrupt_id"]
        if have_other_stock:
            target = apples(c)
            model.messages = iter([call([{**action, "inventory_item_id": str(target.id)}])])
            answer = {"decision": "answer", "message": "是库存中的 Apples"}
        else:
            answer = {"decision": "cancel"}
        body = {"conversation_id": dialogue.conversation_id, "request_id": str(uuid4()), "interrupt_id": state["interrupt_id"],
                "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], **answer}]}
        response = await client.post("/api/v1/agent/resume", json=body, headers=c[6])
        final = parse_events(response)[-1]["data"]["items"][0]
        assert final["status"] == ("SUCCEEDED" if have_other_stock else "CANCELLED")
        assert (await dialogue.counts())[1] == (1 if have_other_stock else 0)
        repeated = await client.post("/api/v1/agent/resume", json=body, headers=c[6])
        assert parse_events(repeated)[-1]["data"]["items"][0]["status"] == final["status"]
        assert (await dialogue.counts())[1] == (1 if have_other_stock else 0)
    asyncio.run(exercise(c[0], scenario))


def test_real_validation_reasons(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        async with sessions() as session:
            for query, expected in [("", "MISSING_QUERY"), ("苹果", "NO_MATCH")]:
                with pytest.raises(PreparationError) as exc:
                    await prepare_action(session, c[1].id, ActionDraft(**{**apple_action(), "item_query": query}), None)
                assert exc.value.code == "TARGET_REQUIRED" and exc.value.details["reason"] == expected
    asyncio.run(exercise(c[0], scenario))


def test_lookup_budget_survives_rebuilt_graph_and_postgres_saver(inventory_context, monkeypatch):
    from langchain_core.messages import HumanMessage
    from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
    from langgraph.store.memory import InMemoryStore
    from psycopg import AsyncConnection
    from test_agent_delta_postgres import connection_args
    from test_agent_workflow import initial

    from app.agents import tools as agent_tools
    from app.agents.state import AgentContext
    from app.agents.workflow import build_agent_graph

    c, action = inventory_context, apple_action()
    class InterruptedModel(ScriptModel):
        internal_calls = 0
        async def ainvoke(self, messages, **kwargs):
            if "agent_internal" in kwargs.get("config", {}).get("tags", []):
                self.internal_calls += 1
                if self.internal_calls == 3:
                    raise RuntimeError("simulated worker interruption")
            return await super().ainvoke(messages, **kwargs)

    async def scenario(client, sessions):
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)
        context = AgentContext(c[1].id, None, uuid4(), user_message=action["original_text"])
        config = {"configurable": {"thread_id": str(uuid4())}, "recursion_limit": 100}
        async with await AsyncConnection.connect(**connection_args(c[0])) as conn:
            saver = AsyncPostgresSaver(conn)
            await saver.setup()
            model = InterruptedModel([call([action]), invocation("list_inventory", q="")], intents=[intake([action])])
            graph = build_agent_graph(model, checkpointer=saver, store=InMemoryStore(), session_factory=sessions)
            with pytest.raises(RuntimeError, match="simulated worker interruption"):
                await graph.ainvoke({**initial(), "messages": [HumanMessage(content=action["original_text"])]}, config, context=context)
        # New connection, saver, graph and model: no process-local budget survives.
        async with await AsyncConnection.connect(**connection_args(c[0])) as conn:
            graph = build_agent_graph(ScriptModel([call([action])] * 2), checkpointer=AsyncPostgresSaver(conn),
                                      store=InMemoryStore(), session_factory=sessions)
            before = (await graph.aget_state(config)).values["items"][0]["target_lookup"]
            assert before["revisions"] == 1 and before["reads"] == 1
            await graph.ainvoke(None, config, context=context)
            item = (await graph.aget_state(config)).values["items"][0]
            assert item["status"] == "NEEDS_INPUT"
            assert item["target_lookup"]["revisions"] == 2 and item["target_lookup"]["reads"] == 1
    asyncio.run(exercise(c[0], scenario))
