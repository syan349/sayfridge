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


@pytest.mark.parametrize("language", ["en", "zh"])
def test_live_three_summaries_preserve_early_fact_and_later_correction(live_runner, language):
    async def scenario():
        model = create_agent_model()
        # Exercise release defaults even if developer .env still has old values.
        model.budget = Budget(summary_output=20000)
        summary, messages = "", []
        facts = {
            "en": ("My name is May. Rice task RICE_PENDING: 2 kg, waiting for storage location; do not execute yet. "
                   "Milk task MILK_CANCELLED: cancelled. Keep these task labels unchanged.",
                   "Correction: my name is Mei. Rice task RICE_PENDING is still waiting for storage location. "
                   "Milk task MILK_CANCELLED remains cancelled.", "Neutral discussion about everyday cooking. "),
            "zh": ("我叫May。大米任务RICE_PENDING：2 kg，还缺存放位置，不要执行。牛奶任务MILK_CANCELLED：已取消。请保留这些任务标签。",
                   "更正：我叫Mei。大米任务RICE_PENDING仍缺存放位置。牛奶任务MILK_CANCELLED仍然取消。", "普通的做饭背景讨论，没有新的库存操作。"),
        }
        original, correction, background = facts[language]
        measurements = []
        for cycle in range(3):
            n = 0
            while model.count(messages) + model.budget.output + model.budget.margin < model.budget.trigger + 3000:
                fact = original if cycle == 0 and n == 0 else correction if cycle == 1 and n == 0 else ""
                messages.extend([HumanMessage(content=fact + background * 160, id=str(uuid4())),
                                 AIMessage(content="Understood.", id=str(uuid4()))])
                n += 1
            info = await rolling_summary(model, messages, summary=summary)
            assert info, cycle
            summary = info["summary"]
            assert "RICE_PENDING" in summary and "MILK_CANCELLED" in summary, summary
            assert "2" in summary and "kg" in summary.lower(), summary
            assert any(word in summary.lower() for word in ("waiting", "pending", "缺", "待")), summary
            assert any(word in summary.lower() for word in ("cancelled", "canceled", "取消")), summary
            if cycle:
                assert "Mei" in summary, summary
            assert info["summary_tokens"] <= 10000 and info["recent_tokens"] <= 10000
            assert info["after"] <= 50000
            measurements.append({k: info[k] for k in ("before", "after", "summary_tokens", "recent_tokens", "input_tokens")})
            messages = [m for m in messages if m.id not in info["remove_ids"]]
        print({"language": language, "live_summary_cycles": 3, "pending_and_cancelled_preserved": True,
               "correction_retained": True, "measurements": measurements})
    live_runner.run(scenario())
