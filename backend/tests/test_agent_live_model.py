"""Opt-in model acceptance against synthetic stock in an isolated test database."""
import os
from uuid import uuid4

import pytest
from langchain_core.messages import HumanMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore

from app.agents.graph import build_agent_graph
from app.agents.model import create_agent_model
from app.agents.state import AgentContext
from app.agents import tools as agent_tools
from app.agents.memory import fingerprint
from inventory_test_support import inventory_context, seed_inventory
from auth_test_support import exercise

pytestmark = [pytest.mark.postgres, pytest.mark.skipif(os.getenv("AGENT_LIVE_MODEL") != "1", reason="Explicit opt-in for model API costs")]


@pytest.mark.parametrize("estimated", [False, True])
def test_real_model_exact_and_knowledge_estimate(inventory_context, monkeypatch, estimated, live_runner):
    c = inventory_context
    from sqlalchemy.orm import Session
    from app.db.models import ItemDefinition
    with Session(c[0][2]) as session:
        definition = session.get(ItemDefinition, c[5].id)
        definition.name = "Rice"
        definition.normalized_name = "rice"
        session.commit()
    item = seed_inventory(c)
    async def scenario(client, sessions):
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)
        store = InMemoryStore()
        graph = build_agent_graph(create_agent_model(), checkpointer=InMemorySaver(), store=store, session_factory=sessions)
        message = (f"库存批次 {item.id}：我要消耗两杯米。我没有单位经验或相关记忆，允许你用自身知识估算重量。请提出估算方案等待确认，不要保存记忆。"
                   if estimated else f"库存批次 {item.id}：我刚刚用了0.1 kg，请扣减。是消耗，不是盘点。")
        turn = str(uuid4())
        context = AgentContext(c[1].id, None, uuid4())
        try:
            result = await graph.ainvoke({"messages": [HumanMessage(content=message)], "turn_id": turn,
                "request_fingerprint": fingerprint(message), "items": [], "requests": {}, "resume_requests": {}},
                {"configurable": {"thread_id": f"live-{turn}"}, "recursion_limit": 128}, context=context, durability="sync")
        except Exception as exc:
            pytest.fail(f"Live model acceptance failed ({type(exc).__name__}); credentials suppressed", pytrace=False)
        assert len(result["items"]) == 1, result.get("turn_intent")
        record = result["items"][0]
        if estimated:
            assert record["status"] == "NEEDS_CONFIRMATION", record.get("error")
            assert record["preview"]["calculation_method"] == "AI_ESTIMATED"
            basis = record["preview"]["draft"].get("unit_relationship") or record["preview"]["draft"]["estimate"]
            assert basis["source"] == "MODEL_KNOWLEDGE"
        else:
            assert record["status"] == "SUCCEEDED"
            assert record["result"]["inventory"]["confirmed_current_amount"] == "2.400"
            assert record["result"]["inventory"]["estimated_current_amount"] is None
    live_runner.run(exercise(c[0], scenario))


@pytest.mark.parametrize("language", ["en", "zh"])
def test_real_model_first_purchase_missing_space_then_create(inventory_context, monkeypatch, language, live_runner):
    from dataclasses import replace
    from langgraph.types import Command
    from sqlalchemy import delete, select, func
    from app.db.models import StorageSpace, ItemCategory, InventoryItem, ItemDefinition, AgentInventoryAction
    c = inventory_context
    report, purchase, location = (("Show me an inventory report", "I just bought 2 kg of tomatoes", "Put them in the fridge")
        if language == "en" else ("看看我的库存", "我刚买了2公斤西红柿", "放冰箱里"))
    async def scenario(client, sessions):
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)
        async with sessions() as session:
            await session.execute(delete(StorageSpace).where(StorageSpace.user_id == c[1].id))
            category = await session.get(ItemCategory, c[3].id)
            category.name = "Vegetables & Mushrooms"
            await session.commit()
        graph = build_agent_graph(create_agent_model(), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions)
        config = {"configurable": {"thread_id": f"tomatoes-{uuid4()}"}, "recursion_limit": 128}
        context = AgentContext(c[1].id, None, uuid4())
        async def turn(message):
            return await graph.ainvoke({"messages": [HumanMessage(content=message)], "turn_id": str(uuid4()),
                "request_fingerprint": fingerprint(message), "items": [], "requests": {}, "resume_requests": {}},
                config, context=replace(context, user_message=message), durability="sync")
        try:
            reported = await turn(report)
            assert not reported["items"]
            assert "**" not in reported["messages"][-1].content and "##" not in reported["messages"][-1].content
            pending = await turn(purchase)
            assert len(pending["items"]) == 1
            item = pending["items"][0]
            assert item["status"] == "NEEDS_INPUT", item.get("error")
            assert item["error"]["code"] == "SPACE_REQUIRED", item.get("error")
            assert len(item["question"]) < 150
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
                assert await session.scalar(select(func.count()).select_from(ItemDefinition).where(ItemDefinition.owner_user_id == c[1].id)) == 0
            snapshot = await graph.aget_state(config)
            response = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()),
                "interrupt_id": snapshot.tasks[0].interrupts[0].id,
                "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "answer", "message": location}]}
            result = await graph.ainvoke(Command(resume=response), config, context=replace(context, user_message=location), durability="sync")
            record = result["items"][0]
            assert record["status"] == "SUCCEEDED", record.get("error")
            saved = record["result"]["inventory"]
            assert saved["confirmed_current_amount"] == "2.000"
            from app.core.quantity import normalize_standard_unit
            assert normalize_standard_unit(saved["confirmed_current_unit"]) == "kg"
            assert saved["category_id"] == str(c[3].id)
            answer = result["messages"][-1].content
            assert isinstance(answer, str) and len(answer) < 250
            assert "**" not in answer and "##" not in answer
            assert "confirm" not in answer.lower() and "确认" not in answer
            assert ("Added" in answer) if language == "en" else ("已" in answer)
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 1
                assert await session.scalar(select(func.count()).select_from(AgentInventoryAction)) == 1
                assert await session.scalar(select(func.count()).select_from(StorageSpace).where(StorageSpace.user_id == c[1].id)) == 1
            print({"scenario": language, "waiting_question": item["question"], "status": record["status"],
                   "amount": saved["confirmed_current_amount"], "unit": saved["confirmed_current_unit"], "reply": answer})
        except AssertionError:
            raise
        except Exception as exc:
            pytest.fail(f"Live purchase acceptance failed ({type(exc).__name__}); credentials suppressed", pytrace=False)
    live_runner.run(exercise(c[0], scenario))


@pytest.mark.parametrize("message,kind", [
    ("I just bought 2 kg of tomatoes", "INVENTORY"),
    ("How should I store tomatoes?", "QUERY"),
    ("Do not add these tomatoes. Just tell me how to store them.", "QUERY"),
    ("If I bought 2 kg of tomatoes, how long would they last?", "QUERY"),
    ("我要消耗两杯米，请提出估算方案等待确认，不要保存记忆。", "INVENTORY"),
])
def test_real_model_intent_boundaries(message, kind, live_runner):
    from app.agents.intake import identify_turn
    async def scenario():
        try:
            result = await identify_turn(create_agent_model(), [HumanMessage(content=message)])
        except Exception as exc:
            pytest.fail(f"Live intake failed ({type(exc).__name__}); credentials suppressed", pytrace=False)
        assert result.kind == kind
        assert bool(result.items) == (kind == "INVENTORY")
    live_runner.run(scenario())


@pytest.mark.parametrize("location", ["the usual place", "the storage area", "the fridge"])
def test_real_model_ambiguous_storage_does_not_write(inventory_context, monkeypatch, live_runner, location):
    from app.db.models import InventoryItem
    from sqlalchemy import select, func
    from inventory_test_support import seed_space
    c = inventory_context
    seed_space(c[0], c[1].id, name="Garage fridge")
    async def scenario(client, sessions):
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)
        graph = build_agent_graph(create_agent_model(), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions)
        message = f"I bought 2 kg of tomatoes. Put them in {location}."
        try:
            result = await graph.ainvoke({"messages": [HumanMessage(content=message)], "turn_id": str(uuid4()),
                "request_fingerprint": fingerprint(message), "items": []},
                {"configurable": {"thread_id": str(uuid4())}, "recursion_limit": 128},
                context=AgentContext(c[1].id, None, uuid4(), user_message=message))
        except Exception as exc:
            pytest.fail(f"Live storage check failed ({type(exc).__name__}); credentials suppressed", pytrace=False)
        assert len(result["items"]) == 1 and result["items"][0]["status"] == "NEEDS_INPUT"
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
    live_runner.run(exercise(c[0], scenario))


@pytest.mark.parametrize("case", ["relative", "weight", "odd_count", "count", "switch"])
def test_real_model_quantity_and_chat_continuation(inventory_context, monkeypatch, case, live_runner):
    from decimal import Decimal
    from langgraph.types import Command
    from app.services.storage_spaces import ensure_default_space
    c = inventory_context
    if case != "relative":
        from sqlalchemy.orm import Session
        from app.db.models import ItemDefinition
        with Session(c[0][2]) as session:
            definition = session.get(ItemDefinition, c[5].id)
            definition.name = "苹果"
            definition.normalized_name = "苹果"
            session.commit()
    initial_amount = {"relative": "2", "odd_count": "3", "count": "3400"}.get(case, "20")
    initial_unit = "kg" if case == "relative" else "g" if case == "count" else "个"
    item = seed_inventory(c, initial_amount=Decimal(initial_amount), initial_unit=initial_unit,
        confirmed_current_amount=Decimal(initial_amount), confirmed_current_unit=initial_unit)
    async def scenario(client, sessions):
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)
        async with sessions() as session:
            await ensure_default_space(session, c[1].id)
        store = InMemoryStore()
        if case == "count":
            from app.agents.memory import MemoryService
            await MemoryService(store, c[1].id).save_conversion({"item_definition_id": str(c[5].id), "item_name": "苹果",
                "relationship": {"source_amount": "1", "source_unit": "个", "target_amount": "180", "target_unit": "g",
                    "source": "USER_INPUT", "rationale": "An apple weighs about 180g"}})
        graph = build_agent_graph(create_agent_model(), checkpointer=InMemorySaver(), store=store, session_factory=sessions)
        message = (f"库存批次 {item.id}：消耗一半。" if case in {"relative", "odd_count"} else
                   f"库存批次 {item.id}：我吃了一个苹果，按已有记忆换算后扣减。" if case == "count" else
                   f"库存批次 {item.id} 是苹果：我吃了200 g，直接按一般苹果重量估算并扣减。")
        turn = str(uuid4())
        config = {"configurable": {"thread_id": f"quantity-{turn}"}, "recursion_limit": 128}
        context = AgentContext(c[1].id, None, uuid4(), user_message=message)
        try:
            result = await graph.ainvoke({"messages": [HumanMessage(content=message)], "turn_id": turn,
                "request_fingerprint": fingerprint(message), "items": [], "requests": {}, "resume_requests": {}},
                config, context=context)
            record = result["items"][0]
            if case == "odd_count":
                assert record["status"] == "NEEDS_INPUT" and record["error"]["code"] == "WHOLE_COUNT_REQUIRED"
                snapshot = await graph.aget_state(config)
                intr = snapshot.tasks[0].interrupts[0]
                result = await graph.ainvoke(Command(resume={intr.id: {"chat_message": "实际吃了一个半",
                    "request_id": str(uuid4()), "fingerprint": "explicit-half"}}), config, context=context)
                record = result["items"][0]
            assert record["status"] == "SUCCEEDED", record.get("error")
            saved = record["result"]["inventory"]
            if case == "relative":
                assert Decimal(saved["confirmed_current_amount"]) == 1 and saved["confirmed_current_unit"] == "kg"
            elif case == "odd_count":
                assert Decimal(saved["confirmed_current_amount"]) == Decimal("1.5")
            elif case == "count":
                assert saved["estimated_current_unit"] in {"个", "each"}
                assert Decimal(saved["estimated_current_amount"]) == 18
                assert "18.1" not in str(result["messages"][-1].content)
            else:
                assert saved["estimated_current_unit"] == "g"
                assert record["result"]["operation"]["quantity_unit"] == "g"
                if case == "switch":
                    followup = f"库存批次 {item.id}：再消耗0.2 kg。"
                    next_turn = str(uuid4())
                    updated = await graph.ainvoke({"messages": [HumanMessage(content=followup)], "turn_id": next_turn,
                        "request_fingerprint": fingerprint(followup), "items": [], "final_only": False},
                        config, context=AgentContext(c[1].id, None, context.conversation_id, user_message=followup))
                    changed = updated["items"][0]
                    assert changed["status"] == "SUCCEEDED", changed.get("error")
                    balance = changed["result"]["inventory"]
                    assert balance["estimated_current_unit"] == "kg"
                    assert Decimal(balance["estimated_current_amount"]) == (Decimal(saved["estimated_current_amount"]) / 1000 - Decimal(".2")).quantize(Decimal(".001"))
                    assert balance["initial_unit"] == "个"
        except Exception as exc:
            pytest.fail(f"Live quantity acceptance failed ({type(exc).__name__}); credentials suppressed", pytrace=False)
    live_runner.run(exercise(c[0], scenario))
