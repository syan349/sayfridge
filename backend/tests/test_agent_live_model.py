"""Opt-in model acceptance against synthetic stock in an isolated test database."""
import asyncio
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
def test_real_model_exact_and_knowledge_estimate(inventory_context, monkeypatch, estimated):
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
        assert len(result["items"]) == 1
        record = result["items"][0]
        if estimated:
            assert record["status"] == "NEEDS_CONFIRMATION", record.get("error")
            assert record["preview"]["calculation_method"] == "AI_ESTIMATED"
            assert record["preview"]["draft"]["estimate"]["source"] == "MODEL_KNOWLEDGE"
        else:
            assert record["status"] == "SUCCEEDED"
            assert record["result"]["inventory"]["confirmed_current_amount"] == "2.400"
            assert record["result"]["inventory"]["estimated_current_amount"] is None
    asyncio.run(exercise(c[0], scenario))
