"""Explicit model opt-in: original #144 phrase and accumulated summary fidelity."""
import os
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session
from langchain_core.messages import HumanMessage, AIMessage

from app.agents.model import create_agent_model
from app.agents.context_budget import Budget, rolling_summary
from app.db.models import ItemDefinition, InventoryItem
from inventory_test_support import inventory_context, seed_inventory, seed_space
from auth_test_support import exercise
from agent_dialogue_support import Dialogue, describe, seed_catalog

pytestmark = [pytest.mark.postgres, pytest.mark.skipif(os.getenv("AGENT_LIVE_MODEL") != "1", reason="Opt in to model API costs")]


@pytest.mark.parametrize("multiple_batches", [False, True])
def test_original_half_consumed_phrase_and_exact_retry(multiple_batches, inventory_context, monkeypatch, live_runner):
    c = inventory_context
    with Session(c[0][2]) as session:
        definition = session.get(ItemDefinition, c[5].id)
        definition.name, definition.normalized_name = "Rice", "rice"
        session.commit()
    rice = seed_inventory(c, initial_amount=Decimal("2"), initial_unit="kg", confirmed_current_amount=Decimal("2"), confirmed_current_unit="kg")
    other = None
    if multiple_batches:
        garage = seed_space(c[0], c[1].id, name="Garage")
        other = seed_inventory(c, storage_space_id=garage.id, initial_amount=Decimal("4"), initial_unit="kg",
                               confirmed_current_amount=Decimal("4"), confirmed_current_unit="kg")
    async def scenario(client, sessions):
        await seed_catalog(c, sessions)
        dialogue = Dialogue(client, c, sessions, create_agent_model(), monkeypatch)
        state = await dialogue.chat("I consumed half of the rice today")
        assert len(state["items"]) == 1, describe(state)
        if multiple_batches:
            item = state["items"][0]
            assert item["status"] == "NEEDS_INPUT" and item["error"]["code"] == "TARGET_REQUIRED", describe(state)
            assert "quantity_unit" not in item["display"]["missing_fields"]
            state = await dialogue.chat(f"The rice in {c[4].name}.")
        item = state["items"][0]
        assert item["status"] == "SUCCEEDED", describe(state)
        assert item["result"]["inventory"]["id"] == str(rice.id)
        assert Decimal(item["result"]["inventory"]["confirmed_current_amount"]) == 1
        previous = dict(dialogue.body)
        repeated = await dialogue.chat(previous["message"], request_id=previous["request_id"])
        assert repeated["items"][0]["item_id"] == item["item_id"]
        assert (await dialogue.counts())[1] == 1
        async with sessions() as session:
            assert (await session.get(InventoryItem, rice.id)).confirmed_current_amount == 1
            if other:
                assert (await session.get(InventoryItem, other.id)).confirmed_current_amount == 4
    live_runner.run(exercise(c[0], scenario))


def test_live_three_summaries_preserve_early_fact_and_later_correction(live_runner):
    async def scenario():
        model = create_agent_model()
        model.budget = Budget(trigger=22000, target=17000, limit=160000, model_limit=160000, output=8000)
        summary, messages = "", []
        for cycle in range(3):
            for n in range(18):
                fact = "I have a peanut allergy. My name is May." if cycle == 0 and n == 0 else "Correction: my name is Mei." if cycle == 1 and n == 0 else "Neutral topic."
                messages.extend([HumanMessage(content=fact + " Background conversation about everyday cooking. " * 200, id=str(uuid4())), AIMessage(content="Understood.", id=str(uuid4()))])
            info = await rolling_summary(model, messages, summary=summary)
            assert info, cycle
            summary = info["summary"]
            assert "peanut" in summary.lower(), summary
            if cycle:
                assert "Mei" in summary, summary
            messages = [m for m in messages if m.id not in info["remove_ids"]]
        print({"live_summary_cycles": 3, "early_fact_retained": True, "correction_retained": True})
    live_runner.run(scenario())
