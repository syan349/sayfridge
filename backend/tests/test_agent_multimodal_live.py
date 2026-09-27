"""Opt-in multimodal acceptance; generated labels/receipts and isolated stock only."""
import asyncio
import os
from uuid import uuid4

import pytest
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
from sqlalchemy import select, func

from app.agents.model import create_agent_model
from app.agents.workflow import build_agent_graph
from app.agents.messages import human_message
from app.agents.state import AgentContext
from app.agents import tools as agent_tools
from app.db.models import InventoryItem
from inventory_test_support import inventory_context
from catalog_test_support import seed_definition
from auth_test_support import exercise
from agent_image_support import image_input

pytestmark = [pytest.mark.postgres, pytest.mark.skipif(os.getenv("AGENT_LIVE_MODEL") != "1", reason="Opt in to model API costs")]


@pytest.fixture(scope="module")
def live_runner():
    # LangChain caches its HTTP client; keep all parameterized calls on one loop.
    with asyncio.Runner() as runner:
        yield runner


@pytest.mark.parametrize("kind", ["single", "multiple", "receipt", "two_views", "question", "image_only"])
def test_live_multimodal_review_and_stock_creation(kind, inventory_context, monkeypatch, live_runner):
    c = inventory_context
    milk = seed_definition(c[0], c[3].id, name="Milk")
    bread = seed_definition(c[0], c[3].id, name="Bread")
    labels = {
        "single": ["MILK\nQuantity: 2 bottles\n500 ml per bottle"],
        "multiple": ["MILK: 2 bottles, 500 ml each\nBREAD: 1 loaf"],
        "receipt": ["GROCERY RECEIPT\n2026-09-26\nMILK   2 bottles  $6.00\nBREAD  1 loaf     $4.00\nTOTAL            $10.00"],
        "two_views": ["MILK\nOne bottle - front\n500 ml", "SAME MILK BOTTLE - back\n500 ml\nExpiry: 2026-10-10"],
        "question": ["MILK\n2 bottles\n500 ml per bottle"],
        "image_only": ["MILK\n2 bottles\n500 ml per bottle"],
    }
    async def scenario(client, sessions):
        monkeypatch.setattr(agent_tools, "AsyncSessionFactory", sessions)
        images = [image_input(label) for label in labels[kind]]
        message = f"Please enter the pictured groceries as new stock in space {c[4].id}. Milk definition is {milk.id}; Bread is {bread.id}. Use the package counts shown and ask me to review before saving."
        if kind == "two_views":
            message += " These are front/back of the SAME single bottle, not two bottles."
        if kind == "question":
            message = "What product and package size are shown? Only describe it; don't enter inventory."
        if kind == "image_only":
            message = ""
        graph = build_agent_graph(create_agent_model(), checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions)
        turn = str(uuid4())
        config = {"configurable": {"thread_id": f"image-live-{turn}"}, "recursion_limit": 128}
        context = AgentContext(c[1].id, None, uuid4(), user_message=message)
        try:
            state = await graph.ainvoke({"messages": [human_message(message, images, turn)], "turn_id": turn,
                "request_fingerprint": "live", "items": [], "turn_has_images": True, "image_task_active": True},
                config, context=context, durability="sync")
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
            if kind in {"question", "image_only"}:
                assert not state.get("items"), "A visual question/ambiguous image must not propose writes"
                return
            assert len(state["items"]) == (2 if kind in {"multiple", "receipt"} else 1)
            assert all(i["status"] == "NEEDS_CONFIRMATION" for i in state["items"])
            for item in state["items"]:
                assert "IMAGE_REVIEW" in item["preview"]["confirmation_reasons"]
                expected = "2" if str(item["draft"]["item_definition_id"]) == str(milk.id) and kind != "two_views" else "1"
                assert item["draft"]["quantity_value"] == expected
            snap = await graph.aget_state(config)
            resume = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()),
                "interrupt_id": snap.tasks[0].interrupts[0].id, "responses": [{"item_id": i["item_id"],
                "proposal_id": i["proposal_id"], "decision": "confirm"} for i in state["items"]]}
            result = await graph.ainvoke(Command(resume=resume), config, context=context, durability="sync")
            assert all(i["status"] == "SUCCEEDED" for i in result["items"])
            async with sessions() as session:
                assert await session.scalar(select(func.count()).select_from(InventoryItem)) == len(state["items"])
        except Exception as exc:
            pytest.fail(f"Multimodal live case {kind} failed ({type(exc).__name__}); provider details suppressed", pytrace=False)
    live_runner.run(exercise(c[0], scenario))
