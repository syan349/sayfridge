"""Transactional acceptance against a disposable migrated PostgreSQL schema."""
import asyncio
from decimal import Decimal
from uuid import uuid4
import pytest
from sqlalchemy import select, func
from langgraph.store.memory import InMemoryStore
from auth_test_support import exercise, make_user, seed_users
from inventory_test_support import inventory_context, seed_inventory
from app.db.models import StorageSpace, InventoryItem, InventoryOperation
from app.services.storage_spaces import ensure_default_space, set_default_space, set_storage_space_status
from app.agents.memory import MemoryService
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import prepare_action, execute_action, PreparationError

pytestmark = [pytest.mark.postgres, pytest.mark.ci]


def test_incremental_migration_preserves_existing_stock(inventory_context):
    from pathlib import Path
    from alembic import command
    from alembic.config import Config
    from sqlalchemy import text
    c = inventory_context
    item = seed_inventory(c)
    with c[0][2].begin() as connection:
        cfg = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
        cfg.attributes["connection"] = connection
        command.downgrade(cfg, "02ec95582dc7")
        from sqlalchemy import inspect
        stock_columns = {table: [(c["name"], str(c["type"])) for c in inspect(connection).get_columns(table)]
                         for table in ("inventory_item", "inventory_operation", "agent_inventory_action")}
        before = connection.execute(text("SELECT initial_amount, initial_unit, confirmed_current_amount, confirmed_current_unit FROM inventory_item WHERE id=:id"), {"id": item.id}).one()
        command.upgrade(cfg, "head")
        after = connection.execute(text("SELECT initial_amount, initial_unit, confirmed_current_amount, confirmed_current_unit FROM inventory_item WHERE id=:id"), {"id": item.id}).one()
        assert after == before
        for table, expected_columns in stock_columns.items():
            assert [(c["name"], str(c["type"])) for c in inspect(connection).get_columns(table)] == expected_columns
        columns = {column["name"]: column["type"] for column in inspect(connection).get_columns("inventory_item")}
        assert columns["confirmed_current_amount"].precision == 12
        assert columns["estimated_current_amount"].precision == 12


def test_default_lock_does_not_deadlock_inventory_receipt_foreign_key(inventory_context):
    from app.db.models import AgentInventoryAction
    from app.services.storage_spaces import lock_space_owner
    c = inventory_context
    async def scenario(client, sessions):
        async with sessions() as stock_session, sessions() as default_session:
            await stock_session.scalar(select(StorageSpace.id).where(StorageSpace.id == c[4].id).with_for_update())
            await lock_space_owner(default_session, c[1].id)
            waiting = asyncio.create_task(default_session.scalar(select(StorageSpace.id).where(
                StorageSpace.id == c[4].id).with_for_update()))
            try:
                stock_session.add(AgentInventoryAction(id=uuid4(), user_id=c[1].id,
                    conversation_id=uuid4(), turn_id=uuid4(), action="CREATE_STOCK",
                    request_fingerprint="f" * 64, request_snapshot={}, result_snapshot={}))
                await asyncio.wait_for(stock_session.commit(), timeout=5)
                assert await asyncio.wait_for(waiting, timeout=5) == c[4].id
            finally:
                if not waiting.done():
                    waiting.cancel()
                    await asyncio.gather(waiting, return_exceptions=True)
                await default_session.rollback()
    asyncio.run(exercise(c[0], scenario))


def test_concurrent_default_creation_and_archive_replacement(database):
    user = make_user()
    seed_users(database, user)
    async def scenario(client, sessions):
        async def ensure():
            async with sessions() as session:
                return (await ensure_default_space(session, user.id)).id
        ids = await asyncio.gather(*[ensure() for _ in range(8)])
        assert len(set(ids)) == 1
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(StorageSpace)) == 1
            old = await set_storage_space_status(session, ids[0], user.id, target_status="ARCHIVED")
            assert not old.is_default
        replacement = await ensure()
        assert replacement != ids[0]
        async with sessions() as session:
            spaces = list(await session.scalars(select(StorageSpace).where(StorageSpace.user_id == user.id)))
            assert sum(s.is_default for s in spaces) == 1
            assert next(s for s in spaces if s.is_default).name == "默认空间"
    asyncio.run(exercise(database, scenario))


def test_default_chooses_oldest_and_preserves_explicit_choice(inventory_context):
    c = inventory_context
    existing = seed_inventory(c)
    async def scenario(client, sessions):
        async with sessions() as session:
            first = await ensure_default_space(session, c[1].id)
            assert first.id == c[4].id
            second = StorageSpace(user_id=c[1].id, name="Pantry", type="PANTRY")
            session.add(second)
            await session.commit()
            await set_default_space(session, second.id, c[1].id)
            assert (await ensure_default_space(session, c[1].id)).id == second.id
            action = ActionDraft(item_key="apple", original_text="add 2 apples", action="CREATE_STOCK",
                item_definition_id=c[5].id, quantity_value="2", quantity_unit="个")
            memory = MemoryService(InMemoryStore(), c[1].id)
            consumption = ActionDraft(item_key="consume", original_text="use half the rice", action="CONSUME",
                item_query=c[5].name, quantity_kind="FRACTION", quantity_value="1/2")
            consumption_preview = await prepare_action(session, c[1].id, consumption, memory)
            assert consumption_preview["draft"]["inventory_item_id"] == str(existing.id)
            preview = await prepare_action(session, c[1].id, action, memory)
            result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
            assert result["inventory"]["storage_space_id"] == str(second.id)
    asyncio.run(exercise(c[0], scenario))


def test_count_to_weight_receipt_and_retry_memory_without_duplicate_write(inventory_context):
    c = inventory_context
    item = seed_inventory(c, initial_amount=Decimal("20"), initial_unit="个",
                          confirmed_current_amount=Decimal("20"), confirmed_current_unit="个")
    async def scenario(client, sessions):
        store = InMemoryStore()
        memory = MemoryService(store, c[1].id)
        original = memory.save_conversion
        async def unavailable(*args):
            raise RuntimeError("temporary memory failure")
        memory.save_conversion = unavailable
        action = ActionDraft(item_key="apple", original_text="ate 200 g", action="CONSUME",
            inventory_item_id=item.id, quantity_value="200", quantity_unit="g",
            unit_relationship={"source_amount": "1", "source_unit": "个", "target_amount": "180",
                "target_unit": "g", "source": "MODEL_KNOWLEDGE", "rationale": "Typical apple"})
        pid, conv, turn = uuid4(), uuid4(), uuid4()
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory)
            assert not preview["requires_confirmation"]
            with pytest.raises(PreparationError) as exc:
                await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            assert exc.value.code == "MEMORY_SAVE_UNAVAILABLE"
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 0
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 1 and actual.estimated_current_amount is None
        memory.save_conversion = original
        async with sessions() as session:
            first = await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            assert Decimal(first["inventory"]["estimated_current_amount"]) == 3400
            assert first["inventory"]["estimated_current_unit"] == "g"
        async with sessions() as session:
            replay = await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            assert replay["replayed"]
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
            actual = await session.get(InventoryItem, item.id)
            assert actual.confirmed_current_amount == 20
        assert len(await memory.search_memories("UNIT_RELATIONSHIP")) == 1
    asyncio.run(exercise(c[0], scenario))


def test_chat_query_then_supplement_replays_original_request_without_recreating_work(inventory_context, monkeypatch):
    from types import SimpleNamespace
    from langchain_core.messages import AIMessage
    from langgraph.checkpoint.memory import InMemorySaver
    from app.agents import locking, continuation
    from app.agents.continuation import Continuation, ContinuationAnswer
    from app.agents.workflow import build_agent_graph
    from app.api.routes import agent as api
    from test_agent_workflow import ScriptModel, call, intake
    from test_agent_api_postgres import parse_events
    c = inventory_context
    url = c[0][0].render_as_string(hide_password=False).replace("postgresql+psycopg://", "postgresql://", 1)
    monkeypatch.setattr(locking, "get_agent_persistence_settings", lambda: SimpleNamespace(psycopg_url=lambda: url))
    monkeypatch.setattr(api, "get_agent_persistence_settings", lambda: SimpleNamespace(workflow_step_limit=128))
    async def interpret(model, items, message):
        if message == "How many spaces?":
            return Continuation(mode="QUERY")
        return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=items[0]["item_id"],
            decision="answer", message=message, evidence=message)])
    monkeypatch.setattr(continuation, "interpret_continuation", interpret)
    async def scenario(client, sessions):
        action = {"item_key": "rice", "action": "CREATE_STOCK", "original_text": "Add rice",
                  "item_definition_id": str(c[5].id), "storage_space_id": str(c[4].id)}
        updated = {**action, "quantity_value": "2", "quantity_unit": "kg"}
        model = ScriptModel([call([action]), AIMessage(content="One space."), call([updated])],
                            intents=[intake([action]), intake(kind="QUERY")])
        graph = build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=sessions, tools=[])
        async def resources():
            return SimpleNamespace(graph=graph)
        monkeypatch.setattr(api, "get_agent_resources", resources)
        original = {"message": "Add rice", "request_id": str(uuid4()), "conversation_id": str(uuid4())}
        first = parse_events(await client.post("/api/v1/agent/chat", json=original, headers=c[6]))
        assert first[-1]["status"] == "WAITING_INPUT"
        old_id = first[-1]["data"]["items"][0]["item_id"]
        query = {**original, "request_id": str(uuid4()), "message": "How many spaces?"}
        answered = parse_events(await client.post("/api/v1/agent/chat", json=query, headers=c[6]))
        assert any(e.get("delta") == "One space." for e in answered)
        assert answered[-1]["status"] == "WAITING_INPUT"
        replay = parse_events(await client.post("/api/v1/agent/chat", json=original, headers=c[6]))
        assert replay[-1]["data"]["items"][0]["item_id"] == old_id
        supplement = {**original, "request_id": str(uuid4()), "message": "2 kg"}
        done = parse_events(await client.post("/api/v1/agent/chat", json=supplement, headers=c[6]))
        assert done[-1]["data"]["items"][0]["status"] == "SUCCEEDED"
        await client.post("/api/v1/agent/chat", json=supplement, headers=c[6])
        await client.post("/api/v1/agent/chat", json=original, headers=c[6])
        replay_query = parse_events(await client.post("/api/v1/agent/chat", json=query, headers=c[6]))
        assert any(e.get("delta") == "One space." for e in replay_query)
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryItem)) == 1
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("amount,expected", [("1", "18"), ("0.5", "18.5")])
def test_mass_to_count_saved_preview_and_feedback_agree(inventory_context, amount, expected):
    from app.agents.intake import outcome_text
    c = inventory_context
    item = seed_inventory(c, confirmed_current_amount=Decimal("3400"), confirmed_current_unit="g")
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        relationship = {"source_amount": "1", "source_unit": "个", "target_amount": "180", "target_unit": "g",
                        "source": "MODEL_KNOWLEDGE", "rationale": "Typical apple estimate"}
        action = ActionDraft(item_key="apple", original_text=f"ate {amount} apples", action="CONSUME",
            inventory_item_id=item.id, quantity_value=amount, quantity_unit="个", unit_relationship=relationship)
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory)
            assert Decimal(preview["after"]["amount"]) == Decimal(expected)
            result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
            actual = await session.get(InventoryItem, item.id)
            assert actual.estimated_current_amount == Decimal(expected) and actual.estimated_current_unit == "个"
            assert set(result) == {"operation", "inventory", "replayed"}
            message = outcome_text([{"status": "SUCCEEDED", "draft": action.model_dump(), "preview": preview, "result": result}], "zh")
            assert f"剩余约{expected} 个" in message
    asyncio.run(exercise(c[0], scenario))


def test_memory_can_survive_failed_stock_write_and_retry_is_once(inventory_context):
    from sqlalchemy import text
    from sqlalchemy.exc import IntegrityError
    c = inventory_context
    item = seed_inventory(c, confirmed_current_amount=Decimal("20"), confirmed_current_unit="个")
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        action = ActionDraft(item_key="apple", original_text="ate 200g", action="CONSUME", inventory_item_id=item.id,
            quantity_value="200", quantity_unit="g", unit_relationship={"source_amount": "1", "source_unit": "个",
                "target_amount": "180", "target_unit": "g", "source": "MODEL_KNOWLEDGE", "rationale": "Estimate"})
        pid, conv, turn = uuid4(), uuid4(), uuid4()
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory)
            await session.execute(text("ALTER TABLE inventory_operation ADD CONSTRAINT reject_consumption CHECK (operation_type <> 'CONSUME')"))
            await session.commit()
            with pytest.raises(IntegrityError):
                await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 1 and actual.estimated_current_amount is None
            assert len(await memory.search_memories("UNIT_RELATIONSHIP")) == 1
            await session.execute(text("ALTER TABLE inventory_operation DROP CONSTRAINT reject_consumption"))
            await session.commit()
            await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            replay = await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            assert replay["replayed"]
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
    asyncio.run(exercise(c[0], scenario))


def test_old_pending_preview_reprepared_but_committed_receipt_only_replayed(inventory_context):
    from app.agents.memory import fingerprint
    from app.db.models import AgentInventoryAction
    c = inventory_context
    item = seed_inventory(c)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        action = ActionDraft(item_key="rice", original_text="use 1kg", action="CONSUME", inventory_item_id=item.id,
                            quantity_value="1", quantity_unit="kg")
        pid, conv, turn = uuid4(), uuid4(), uuid4()
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory)
            old = {k: v for k, v in preview.items() if k != "quantity_policy"}
            with pytest.raises(PreparationError) as exc:
                await execute_action(session, c[1].id, conv, turn, pid, old, memory)
            assert exc.value.code == "QUANTITY_POLICY_CHANGED"
            assert (await session.get(InventoryItem, item.id)).version == 1
            result = await execute_action(session, c[1].id, conv, turn, pid, preview, memory)
            receipt = await session.get(AgentInventoryAction, pid)
            receipt.request_snapshot = old
            receipt.request_fingerprint = fingerprint(old)
            await session.commit()
            replay = await execute_action(session, c[1].id, conv, turn, pid, old, memory)
            assert replay["replayed"] and replay["inventory"] == result["inventory"]
            assert (await session.get(InventoryItem, item.id)).version == 2
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("quantity_unit,expected_unit,expected_amount", [(None, "kg", "2.200"), ("g", "g", "2200.000")])
def test_qualitative_estimate_uses_user_unit_or_existing_unit(inventory_context, quantity_unit, expected_unit, expected_amount):
    c = inventory_context
    item = seed_inventory(c)
    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        action = ActionDraft(item_key="rice", original_text="used some rice", action="CONSUME", inventory_item_id=item.id,
            quantity_kind="QUALITATIVE", quantity_value="some", quantity_unit=quantity_unit,
            estimate={"amount": "300", "unit": "g", "source": "MODEL_KNOWLEDGE", "rationale": "Estimate"})
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, action, memory)
            assert preview["after"]["unit"] == expected_unit
            result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory)
            assert result["inventory"]["estimated_current_unit"] == expected_unit
            assert Decimal(result["inventory"]["estimated_current_amount"]) == Decimal(expected_amount)
    asyncio.run(exercise(c[0], scenario))
