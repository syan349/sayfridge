"""Issues 158/145/161: real persisted stock, confirmation, rollback and receipts."""
import asyncio
from datetime import date
from decimal import Decimal
from uuid import uuid4

import pytest
from langgraph.store.memory import InMemoryStore
from sqlalchemy import select, func, text
from sqlalchemy.exc import IntegrityError

from app.agents.memory import MemoryService
from app.agents.intake import outcome_text, waiting_question
from app.db.models import ItemDefinition, InventoryItem, AgentInventoryAction
from app.schemas.agent_actions import ActionDraft
from app.services import inventory_expiry
from app.services.agent_actions import prepare_action, execute_action, PreparationError
from inventory_test_support import inventory_context, seed_inventory, payload, BASE
from catalog_test_support import seed_category, seed_definition
from auth_test_support import exercise

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


@pytest.mark.parametrize("private", [True, False])
def test_category_confirmation_changes_only_authorized_definition_and_replays(inventory_context, monkeypatch, private):
    c = inventory_context
    correct = seed_category(c[0], "Yoghurt")
    wrong = seed_definition(c[0], c[3].id, name="Yogurt", owner_id=c[1].id if private else None)
    old = seed_inventory(c, item_definition_id=wrong.id)
    estimates = []
    async def estimate(items):
        estimates.append(items)
        return {i["key"]: 7 for i in items}
    monkeypatch.setattr(inventory_expiry, "estimate_shelf_lives", estimate)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        draft = ActionDraft(item_key="yogurt", original_text="Add 2 yogurts", action="CREATE_STOCK", quantity_value="2",
            quantity_unit="each", storage_space_id=c[4].id, item_definition_id=wrong.id, category_name="Yoghurt")
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft, memory, date(2026, 10, 2))
        assert preview["requires_confirmation"] and "CATEGORY_CHANGE" in preview["confirmation_reasons"]
        assert "Yoghurt" in waiting_question({"status": "NEEDS_CONFIRMATION", "preview": preview, "draft": preview["draft"]}, "en")
        monkeypatch.setattr(inventory_expiry, "local_today", lambda: date(2026, 11, 1))
        async with sessions() as session:
            with pytest.raises(PreparationError, match="Confirm"):
                await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
            assert (await session.get(ItemDefinition, wrong.id)).category_id == c[3].id
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 1
        conversation, turn, proposal = uuid4(), uuid4(), uuid4()
        async with sessions() as session:
            result = await execute_action(session, c[1].id, conversation, turn, proposal, preview, memory, approved=True)
        assert result["inventory"]["category_id"] == str(correct.id)
        assert result["inventory"]["expiry_date"] == "2026-10-09"
        assert result["inventory"]["purchase_date"] is None
        assert result["inventory"]["warnings"][0]["code"] == "EXPIRY_ESTIMATED"
        async with sessions() as session:
            replay = await execute_action(session, c[1].id, conversation, turn, proposal, preview, memory, approved=True)
            assert replay["inventory"] == result["inventory"]
            assert (await session.get(ItemDefinition, wrong.id)).category_id == (correct.id if private else c[3].id)
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 2
            assert await session.scalar(select(func.count()).select_from(AgentInventoryAction)) == 1
        assert len(estimates) == 1
        original = (await client.get(f"{BASE}/{old.id}", headers=c[6])).json()
        assert original["category_id"] == str(correct.id if private else c[3].id)
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("failure", ["concurrent_change", "receipt_failure"])
def test_classification_change_is_revalidated_and_atomic(inventory_context, failure):
    c = inventory_context
    correct = seed_category(c[0], "Yoghurt")
    wrong = seed_definition(c[0], c[3].id, name="Yoghurt", owner_id=c[1].id)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        draft = ActionDraft(item_key="one", original_text="add yoghurt", action="CREATE_STOCK", quantity_value="2",
            quantity_unit="each", storage_space_id=c[4].id, item_definition_id=wrong.id, category_name="Yoghurt")
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft, memory)
            if failure == "concurrent_change":
                (await session.get(ItemDefinition, wrong.id)).name = "Renamed yoghurt"
            else:
                await session.execute(text("ALTER TABLE agent_inventory_action ADD CONSTRAINT reject_test_receipt CHECK (action <> 'CREATE_STOCK')"))
            await session.commit()
        async with sessions() as session:
            with pytest.raises(PreparationError if failure == "concurrent_change" else IntegrityError):
                await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory, approved=True)
            assert (await session.get(ItemDefinition, wrong.id)).category_id == c[3].id
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
    asyncio.run(exercise(c[0], scenario))


def test_single_and_batch_dates_warnings_and_read_contract(inventory_context, monkeypatch):
    c = inventory_context
    calls = []
    async def estimate(items):
        calls.append(items)
        return {items[0]["key"]: 7}  # The second batch item cannot be estimated.
    monkeypatch.setattr(inventory_expiry, "estimate_shelf_lives", estimate)
    async def scenario(client, sessions):
        single = await client.post(BASE, json=payload(c, purchase_date="2026-10-02"), headers=c[6])
        assert single.status_code == 201
        saved = single.json()
        assert saved["expiry_date"] == "2026-10-09"
        assert saved["warnings"][0]["item_id"] == saved["id"]
        read = (await client.get(f"{BASE}/{saved['id']}", headers=c[6])).json()
        assert "warnings" not in read and read["expiry_date"] == saved["expiry_date"]
        batch = await client.post(BASE + "/batch-create", json={"items": [payload(c), payload(c)]}, headers=c[6])
        assert batch.status_code == 201
        data = batch.json()
        assert data["count"] == 2 and len(data["warnings"]) == 2
        assert data["items"][1]["expiry_date"] is None
        assert data["warnings"][1]["code"] == "EXPIRY_ESTIMATION_FAILED"
        assert all("warnings" not in item for item in data["items"])
        assert len(calls) == 2 and len(calls[1]) == 2
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 3
    asyncio.run(exercise(c[0], scenario))


def test_failed_expiry_saves_stock_and_receipt_warning(inventory_context):
    c = inventory_context
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        draft = ActionDraft(item_key="apples", original_text="Add 2kg apples", action="CREATE_STOCK",
            quantity_value="2", quantity_unit="kg", storage_space_id=c[4].id, item_definition_id=c[5].id)
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft, memory)
            result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
        saved = result["inventory"]
        assert Decimal(saved["confirmed_current_amount"]) == 2 and saved["confirmed_current_unit"] == "kg"
        assert saved["expiry_date"] is None and saved["warnings"][0]["code"] == "EXPIRY_ESTIMATION_FAILED"
        message = outcome_text([{"status": "SUCCEEDED", "draft": preview["draft"], "result": result}], "zh")
        assert "2 kg" in message and "库存已保存" in message and "18.1" not in message
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("decision", ["confirm", "cancel"])
def test_http_category_resume_and_cancel_keep_business_effects_atomic(inventory_context, monkeypatch, decision):
    from agent_dialogue_support import Dialogue
    from test_agent_workflow import ScriptModel, call, intake
    from test_agent_api_postgres import parse_events
    c = inventory_context
    category = seed_category(c[0], "Yoghurt")
    definition = seed_definition(c[0], c[3].id, name="Yogurt", owner_id=c[1].id)
    async def scenario(client, sessions):
        draft = {"item_key": "yogurt", "original_text": "Add 2 yogurts", "action": "CREATE_STOCK",
            "item_query": "Yogurt", "quantity_value": "2", "quantity_unit": "each",
            "storage_space_id": str(c[4].id), "item_definition_id": str(definition.id), "category_name": "Yoghurt"}
        dialogue = Dialogue(client, c, sessions, ScriptModel([call([draft])], intents=[intake([draft])]), monkeypatch)
        waiting = await dialogue.chat("Add 2 yogurts")
        item = waiting["items"][0]
        assert item["status"] == "NEEDS_CONFIRMATION"
        assert "Existing stock" in item["display"]["question"]
        assert "Food" in item["display"]["question"] and "Yoghurt" in item["display"]["question"]
        state = await dialogue.state()
        payload = {"conversation_id": dialogue.conversation_id, "request_id": str(uuid4()),
            "interrupt_id": state["interrupt_id"], "responses": [{"item_id": item["item_id"],
                "proposal_id": item["proposal_id"], "decision": decision}]}
        events = parse_events(await client.post("/api/v1/agent/resume", json=payload, headers=c[6]))
        assert not any(event["type"] == "error" for event in events)
        assert events[-1]["data"]["items"][0]["status"] == ("SUCCEEDED" if decision == "confirm" else "CANCELLED")
        async with sessions() as session:
            assert (await session.get(ItemDefinition, definition.id)).category_id == (category.id if decision == "confirm" else c[3].id)
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == (1 if decision == "confirm" else 0)
    asyncio.run(exercise(c[0], scenario))


def test_expiry_revisions_and_legacy_pending_proposals(inventory_context, monkeypatch):
    c = inventory_context
    async def estimate(items):
        return {i["key"]: 7 if i["storage_type"] == "FRIDGE" else 30 for i in items}
    monkeypatch.setattr(inventory_expiry, "estimate_shelf_lives", estimate)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        draft = ActionDraft(item_key="one", original_text="buy rice", action="CREATE_STOCK", quantity_value="2",
            quantity_unit="kg", storage_space_id=c[4].id, item_definition_id=c[5].id, purchase_date="2026-10-02")
        async with sessions() as session:
            first = await prepare_action(session, c[1].id, draft, memory)
            revised = await prepare_action(session, c[1].id, draft.model_copy(update={"purchase_date": date(2026, 10, 4)}), memory)
            assert first["draft"]["expiry_date"] is None
            assert first["expiry_resolution"]["expiry_date"] == "2026-10-09"
            assert revised["expiry_resolution"]["expiry_date"] == "2026-10-11"
        legacy = {**first, "creation_policy": {"version": 1}}
        async with sessions() as session:
            with pytest.raises(PreparationError) as exc:
                await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), legacy, memory, approved=True)
            assert exc.value.code == "RESOURCE_CHANGED"
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
    asyncio.run(exercise(c[0], scenario))


def test_apple_addition_switch_and_explicit_partial_persist_correct_units(inventory_context):
    c = inventory_context
    item = seed_inventory(c, initial_amount=Decimal("20"), initial_unit="each",
        confirmed_current_amount=Decimal("20"), confirmed_current_unit="each")
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        relation = {"source_amount": "1", "source_unit": "each", "target_amount": "180", "target_unit": "g",
            "source": "MODEL_KNOWLEDGE", "rationale": "Estimated apple size"}
        for operation, value, unit, expected, relationship in [
            ("ADD", "2", "kg", "5.600", relation),
            ("CONSUME", "1", "each", "30.000", relation),
            ("CONSUME", "0.5", "each", "29.500", None),
        ]:
            draft = ActionDraft(item_key="apple", original_text="change this apple batch", action=operation,
                inventory_item_id=item.id, quantity_value=value, quantity_unit=unit, unit_relationship=relationship)
            async with sessions() as session:
                preview = await prepare_action(session, c[1].id, draft, memory)
                result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
            saved = result["inventory"]
            assert saved["estimated_current_amount"] == expected and saved["estimated_current_unit"] == unit
            assert saved["initial_amount"] == "20.000" and saved["initial_unit"] == "each"
            actual = (await client.get(f"{BASE}/{item.id}", headers=c[6])).json()
            assert actual["display_amount"] == expected and actual["display_unit"] == unit
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("batch", [False, True])
def test_estimation_occurs_before_space_write_lock_and_rechecks_changes(inventory_context, monkeypatch, batch):
    from app.db.models import StorageSpace
    from sqlalchemy.orm import Session
    c = inventory_context
    async def change_during_estimate(items):
        # A separate writer must be able to acquire this lock while the model runs.
        with Session(c[0][2]) as writer:
            writer.execute(text("SET LOCAL lock_timeout = '300ms'"))
            space = writer.scalar(select(StorageSpace).where(StorageSpace.id == c[4].id).with_for_update())
            space.type = "FREEZER"
            writer.commit()
        return {i["key"]: 7 for i in items}
    monkeypatch.setattr(inventory_expiry, "estimate_shelf_lives", change_during_estimate)
    async def scenario(client, sessions):
        body = {"items": [payload(c)]} if batch else payload(c)
        response = await client.post(BASE + ("/batch-create" if batch else ""), json=body, headers=c[6])
        assert response.status_code == 409 and response.json()["detail"]["code"] == "RESOURCE_CHANGED"
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 0
    asyncio.run(exercise(c[0], scenario))
