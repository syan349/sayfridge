"""Opt-in HTTP/chat/resume acceptance for issues 158, 145 and 161."""
import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.agents.model import create_agent_model
from app.db.models import ItemCategory, ItemDefinition
from app.services.storage_spaces import ensure_default_space
from agent_dialogue_support import Dialogue, seed_catalog, describe
from inventory_test_support import inventory_context
from auth_test_support import exercise
from test_agent_api_postgres import parse_events

pytestmark = [pytest.mark.postgres, pytest.mark.skipif(os.getenv("AGENT_LIVE_MODEL") != "1", reason="Opt in to model API costs")]


@pytest.mark.parametrize("message,category_name,unit", [
    ("Add 2 yogurts to my fridge.", "Yoghurt", "each"),
    ("I bought 2 yoghurts. Put them in my fridge.", "Yoghurt", "each"),
    ("买了两盒酸奶，放冰箱。", "Yoghurt", "盒"),
    ("Add 2kg apples to my fridge.", "Fruit", "kg"),
])
def test_real_stock_category_quantity_and_expiry(message, category_name, unit, inventory_context, monkeypatch, live_runner):
    c = inventory_context
    async def scenario(client, sessions):
        await seed_catalog(c, sessions)
        async with sessions() as session:
            await ensure_default_space(session, c[1].id)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat(message)
        assert len(state["items"]) == 1, describe(state)
        item = state["items"][0]
        assert item["status"] == "SUCCEEDED", describe(state)
        saved = item["result"]["inventory"]
        assert saved["category_name"] == category_name
        assert Decimal(saved["confirmed_current_amount"]) == 2
        assert saved["confirmed_current_unit"] == unit
        assert saved["expiry_date"] is not None
        assert saved["warnings"][0]["code"] == "EXPIRY_ESTIMATED"
        assert (await dialogue.counts())[0] == 1
    live_runner.run(exercise(c[0], scenario))


def test_real_model_recognizes_old_category_and_waits_for_confirmation(inventory_context, monkeypatch, live_runner):
    c = inventory_context
    async def scenario(client, sessions):
        await seed_catalog(c, sessions)
        async with sessions() as session:
            other = await session.scalar(select(ItemCategory).where(ItemCategory.name == "Other"))
            definition = ItemDefinition(name="Yogurt", normalized_name="yogurt", category_id=other.id, owner_user_id=c[1].id)
            session.add(definition)
            await ensure_default_space(session, c[1].id)
            await session.commit()
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat("Add 2 yogurts to my fridge.")
        item = state["items"][0]
        assert item["status"] == "NEEDS_CONFIRMATION", describe(state)
        assert "CATEGORY_CHANGE" in item["display"]["confirmation_reasons"]
        assert (await dialogue.counts())[0] == 0
        snapshot = await dialogue.state()
        answer = {"conversation_id": dialogue.conversation_id, "request_id": str(uuid4()),
            "interrupt_id": snapshot["interrupt_id"], "responses": [{"item_id": item["item_id"],
                "proposal_id": item["proposal_id"], "decision": "confirm"}]}
        events = parse_events(await client.post("/api/v1/agent/resume", json=answer, headers=c[6]))
        saved = events[-1]["data"]["items"][0]
        assert saved["status"] == "SUCCEEDED", saved.get("error")
        assert saved["result"]["inventory"]["category_name"] == "Yoghurt"
        assert saved["result"]["inventory"]["expiry_date"] is not None
    live_runner.run(exercise(c[0], scenario))


def test_real_model_keeps_manufacture_shelf_life_separate_from_purchase(inventory_context, monkeypatch, live_runner):
    c = inventory_context
    async def scenario(client, sessions):
        await seed_catalog(c, sessions)
        async with sessions() as session:
            await ensure_default_space(session, c[1].id)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat("Add 2 bottles of milk to my fridge. I bought them on 2026-10-02. "
            "The label says manufactured 2026-09-28 and shelf life 7 days from manufacture.")
        item = state["items"][0]
        assert item["status"] == "SUCCEEDED", describe(state)
        saved = item["result"]["inventory"]
        assert saved["purchase_date"] == "2026-10-02"
        assert saved["expiry_date"] == "2026-10-05"
        assert saved["warnings"] == []
    live_runner.run(exercise(c[0], scenario))
