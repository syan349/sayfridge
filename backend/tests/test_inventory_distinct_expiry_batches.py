"""Reusing category/item names must preserve independently dated stock batches."""
import asyncio
from datetime import date, timedelta
from decimal import Decimal
from uuid import uuid4

import pytest
from langgraph.store.memory import InMemoryStore
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.agents.memory import MemoryService
from app.db.models import InventoryItem, ItemCategory, ItemDefinition
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import execute_action, prepare_action
from auth_test_support import exercise
from catalog_test_support import CATEGORIES, seed_definition
from inventory_test_support import BASE, inventory_context

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


@pytest.mark.parametrize("entry", ["manual", "batch", "agent"])
def test_reused_category_keeps_two_carrot_batches_and_edits_independent(inventory_context, entry):
    c = inventory_context
    today = date(2026, 10, 2)
    dates = [today + timedelta(days=3), today + timedelta(days=5)]

    async def scenario(client, sessions):
        categories = []
        for name in ["Vegetable", " vegetable "]:
            response = await client.post(CATEGORIES, headers=c[-1], json={"name": name})
            assert response.status_code == 201, response.text
            categories.append(response.json())
        assert categories[0]["id"] == categories[1]["id"]
        category = categories[0]
        from uuid import UUID
        definition = seed_definition(c[0], UUID(category["id"]), name="Carrots", owner_id=c[1].id)
        payloads = [{"storage_space_id": str(c[4].id), "item_definition_id": str(definition.id),
                     "amount": str(amount), "unit": "each", "expiry_date": expiry.isoformat()}
                    for amount, expiry in zip([2, 5], dates)]
        created = []
        if entry == "batch":
            response = await client.post(BASE + "/batch-create", headers=c[-1], json={"items": payloads})
            assert response.status_code == 201, response.text
            created = response.json()["items"]
        elif entry == "manual":
            for payload in payloads:
                response = await client.post(BASE, headers=c[-1], json=payload)
                assert response.status_code == 201, response.text
                created.append(response.json())
        else:
            memory = MemoryService(InMemoryStore(), c[1].id)
            for payload in payloads:
                draft = ActionDraft(item_key="carrots", action="CREATE_STOCK", original_text="Add carrots",
                    storage_space_id=c[4].id, new_definition={"name": "Carrots", "category_id": category["id"]},
                    category_name=" vegetable ", quantity_value=payload["amount"], quantity_unit="each",
                    expiry_date=payload["expiry_date"])
                async with sessions() as session:
                    preview = await prepare_action(session, c[1].id, draft, memory, today)
                async with sessions() as session:
                    result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory, approved=True)
                created.append(result["inventory"])

        assert len({item["id"] for item in created}) == 2
        assert {item["item_definition_id"] for item in created} == {str(definition.id)}
        response = await client.get(BASE, headers=c[-1], params={"category_id": category["id"]})
        assert response.status_code == 200, response.text
        listed = response.json()
        assert listed["total"] == 2
        assert [item["id"] for item in listed["items"]] == [item["id"] for item in created]
        assert [item["expiry_date"] for item in listed["items"]] == [expiry.isoformat() for expiry in dates]
        assert [Decimal(item["display_amount"]) for item in listed["items"]] == [Decimal(2), Decimal(5)]

        edited = await client.patch(f"{BASE}/{created[0]['id']}", headers=c[-1], json={"expected_version": 1,
            "expiry_date": "2026-10-06", "quantity": {"mode": "EXACT", "amount": "1", "unit": "each"}})
        assert edited.status_code == 200, edited.text
        assert edited.json()["expiry_date"] == "2026-10-06"
        assert Decimal(edited.json()["display_amount"]) == 1
        sibling = await client.get(f"{BASE}/{created[1]['id']}", headers=c[-1])
        assert sibling.status_code == 200, sibling.text
        assert sibling.json()["expiry_date"] == "2026-10-07"
        assert Decimal(sibling.json()["display_amount"]) == 5
        assert sibling.json()["version"] == 1
        with Session(c[0][2]) as session:
            assert session.scalar(select(func.count()).select_from(InventoryItem)) == 2
            assert session.scalar(select(func.count()).select_from(ItemCategory).where(ItemCategory.owner_user_id == c[1].id)) == 1
            assert session.scalar(select(func.count()).select_from(ItemDefinition).where(ItemDefinition.owner_user_id == c[1].id)) == 1
    asyncio.run(exercise(c[0], scenario))
