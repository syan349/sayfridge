"""Real transaction, estimate, replay, and dependency rollback acceptance."""
import asyncio
from decimal import Decimal
from uuid import uuid4

import pytest
from langgraph.store.memory import InMemoryStore
from sqlalchemy import select, func, text
from sqlalchemy.exc import IntegrityError

from app.agents.memory import MemoryService
from app.db.models import AgentInventoryAction, InventoryItem, InventoryOperation, StorageSpace, ItemDefinition
from app.schemas.agent_actions import ActionDraft
from app.schemas.agent import SaveUserMemoryToolInput
from app.services.agent_actions import prepare_action, execute_action, PreparationError
from inventory_test_support import inventory_context, seed_inventory
from auth_test_support import exercise

pytestmark = pytest.mark.postgres


def draft(item, action="CONSUME", **changes):
    return ActionDraft(item_key="one", original_text="use one", action=action,
        inventory_item_id=item.id, **{"quantity_value": "1", "quantity_unit": "kg", **changes})


def test_estimate_precise_followup_reconcile_and_replay(inventory_context):
    c = inventory_context
    item = seed_inventory(c)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        conversation, turn = uuid4(), uuid4()
        async def submit(action, approved=False):
            async with sessions() as session:
                preview = await prepare_action(session, c[1].id, action, memory)
            pid = uuid4()
            async with sessions() as session:
                result = await execute_action(session, c[1].id, conversation, turn, pid, preview, memory, approved=approved)
            return result, pid, preview
        estimate = draft(item, quantity_value="2", quantity_unit="cup", estimate={"amount": "0.3", "unit": "kg", "source": "MODEL_KNOWLEDGE", "rationale": "About 150g per cup"})
        result, pid, preview = await submit(estimate, True)
        assert result["inventory"]["confirmed_current_amount"] == "2.500"
        assert result["inventory"]["estimated_current_amount"] == "14.667"
        assert result["inventory"]["estimated_current_unit"] == "cup"
        assert result["operation"]["quantity_unit"] == "cup"
        assert result["operation"]["calculation_method"] == "AI_ESTIMATED"
        assert result["operation"]["input_method"] == "TEXT"
        async with sessions() as session:
            replay = await execute_action(session, c[1].id, conversation, turn, pid, preview, memory, approved=True)
            assert replay["replayed"]
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
        result, _, _ = await submit(draft(item, quantity_value="500", quantity_unit="g"))
        assert result["inventory"]["estimated_current_amount"] == "1700.050"
        assert result["inventory"]["confirmed_current_amount"] == "2.500"
        assert result["operation"]["calculation_method"] == "AI_ESTIMATED"
        result, _, _ = await submit(draft(item, "RECONCILE", quantity_value="8", quantity_unit="each"))
        assert result["inventory"]["confirmed_current_amount"] == "8.000"
        assert result["inventory"]["estimated_current_amount"] is None
        assert result["inventory"]["initial_amount"] == "2.500"
    asyncio.run(exercise(c[0], scenario))


def test_memory_basis_and_confirmation_are_checked(inventory_context):
    c = inventory_context
    item = seed_inventory(c)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        saved = await memory.save_memory(SaveUserMemoryToolInput(category="UNIT_RELATIONSHIP", content="cup is about 100g",
            conditions={"item_definition_id": c[5].id, "source_unit": "cup", "target_unit": "g"},
            structured_value={"source_amount": "1", "source_unit": "cup", "target_amount": "100", "target_unit": "g"}))
        action = draft(item, quantity_value="2", quantity_unit="cup", estimate={"amount": "9", "unit": "kg", "source": "USER_MEMORY", "memory_id": saved["memory_id"], "rationale": "use remembered cup"})
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory)
        assert Decimal(preview["after"]["amount"]) == Decimal("23")  # backend ratio overrides bad model arithmetic
        assert not preview["requires_confirmation"]
        await memory.delete_memory(saved["memory_id"])
        async with sessions() as session:
            with pytest.raises(PreparationError, match="Memory changed"):
                await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory, approved=True)
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 1
            assert actual.estimated_current_amount is None
    asyncio.run(exercise(c[0], scenario))


def test_receipt_failure_rolls_back_all_new_associations(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        action = ActionDraft(item_key="new", original_text="two bags", action="CREATE_STOCK", quantity_value="2", quantity_unit="bag",
            new_space={"name": "Agent pantry", "type": "PANTRY"}, new_space_source_text="Put them in Agent pantry",
            new_definition={"name": "New rice", "category_id": c[3].id})
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory, source_texts=["Put them in Agent pantry"])
            assert not preview["requires_confirmation"]
            await session.execute(text("ALTER TABLE agent_inventory_action ADD CONSTRAINT reject_receipt CHECK (action <> 'CREATE_STOCK')"))
            await session.commit()
        pid, conv, turn = uuid4(), uuid4(), uuid4()
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            assert await session.scalar(select(func.count()).select_from(StorageSpace).where(StorageSpace.name == "Agent pantry")) == 0
            assert await session.scalar(select(func.count()).select_from(ItemDefinition).where(ItemDefinition.name == "New rice")) == 0
            await session.execute(text("ALTER TABLE agent_inventory_action DROP CONSTRAINT reject_receipt"))
            await session.commit()
        async with sessions() as session:
            first = await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
        async with sessions() as session:
            replay = await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            assert first["inventory"]["id"] == replay["inventory"]["id"]
            assert replay["replayed"]
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 1
    asyncio.run(exercise(c[0], scenario))


def test_concurrent_receipt_applies_once_and_other_user_cannot_replay(inventory_context):
    c = inventory_context
    item = seed_inventory(c)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft(item), memory)
        pid, conv, turn = uuid4(), uuid4(), uuid4()
        async def send():
            async with sessions() as session:
                return await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
        results = await asyncio.gather(send(), send())
        assert sorted(r["replayed"] for r in results) == [False, True]
        async with sessions() as session:
            actual = await session.get(InventoryItem, item.id)
            assert actual.confirmed_current_amount == Decimal("1.5") and actual.version == 2
            with pytest.raises(PreparationError):
                await execute_action(session, c[2].id, conv, turn, pid, preview, MemoryService(memory.store, c[2].id))
    asyncio.run(exercise(c[0], scenario))
