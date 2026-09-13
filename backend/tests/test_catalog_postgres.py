"""B05/B06 normalization races, category locks, atomic rollback, and snapshots."""
import asyncio

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import ItemCategory, ItemDefinition
from app.services import catalog as service
from auth_test_support import exercise
from catalog_test_support import CATEGORIES, DEFINITIONS, catalog_context, seed_category, seed_definition

pytestmark = pytest.mark.postgres


@pytest.mark.parametrize("operation", [pytest.param("create", marks=pytest.mark.ci), "rename"])
def test_concurrent_normalized_name_claims_in_different_categories_have_one_winner(catalog_context, monkeypatch, operation):
    """Force both name checks to finish before either write; the real unique index arbitrates."""
    db, owner, _, category, headers = catalog_context
    other_category = seed_category(db, "Other")
    categories = [category, other_category]
    rows = [seed_definition(db, cat.id, owner_id=owner.id, name=f"Original {i}") for i, cat in enumerate(categories)] if operation == "rename" else []
    check = service._check_name
    async def scenario(client, sessions):
        barrier = asyncio.Barrier(2)
        async def synchronized_check(session, user_id, name, exclude_id=None):
            result = await check(session, user_id, name, exclude_id)
            await asyncio.wait_for(barrier.wait(), timeout=15)
            return result
        monkeypatch.setattr(service, "_check_name", synchronized_check)
        names = ["Milk", "\uff2d\uff49\uff4c\uff4b"]
        if operation == "create":
            calls = [client.post(DEFINITIONS, json={"name": name, "category_id": str(cat.id)}, headers=headers)
                     for name, cat in zip(names, categories)]
        else:
            calls = [client.patch(f"{DEFINITIONS}/{row.id}", json={"name": name}, headers=headers)
                     for name, row in zip(names, rows)]
        responses = await asyncio.wait_for(asyncio.gather(*calls), timeout=30)
        assert sorted(r.status_code for r in responses) == [201 if operation == "create" else 200, 409]
        assert next(r for r in responses if r.status_code == 409).json()["detail"]["code"] == "NAME_CONFLICT"
        async with sessions() as session:
            assert await session.scalar(text("SELECT count(*) FROM item_definition WHERE normalized_name='milk'")) == 1
    asyncio.run(exercise(db, scenario))


@pytest.mark.parametrize("operation", ["create", pytest.param("restore", marks=pytest.mark.ci), "moved_definition"])
def test_category_lock_wait_rechecks_state_and_planned_relationship(catalog_context, monkeypatch, operation):
    """Observe a real PostgreSQL lock wait before releasing a concurrent category change."""
    db, owner, _, category, headers = catalog_context
    row = seed_definition(db, category.id, owner_id=owner.id, status="ARCHIVED")
    target = seed_category(db, "Target")
    lock = service._lock_categories
    async def scenario(client, sessions):
        started = asyncio.Event()
        waiter_pid = None
        async def observe_lock(session, ids):
            nonlocal waiter_pid
            waiter_pid = await session.scalar(text("SELECT pg_backend_pid()"))
            started.set()
            return await lock(session, ids)
        monkeypatch.setattr(service, "_lock_categories", observe_lock)
        pending = None
        async with sessions() as writer:
            writer_pid = await writer.scalar(text("SELECT pg_backend_pid()"))
            await writer.execute(select(ItemCategory).where(ItemCategory.id == category.id).with_for_update())
            if operation == "moved_definition":
                await writer.execute(text("UPDATE item_definition SET category_id=:category WHERE id=:id"), {"category": target.id, "id": row.id})
            else:
                await writer.execute(text("UPDATE item_category SET status='ARCHIVED' WHERE id=:id"), {"id": category.id})
            try:
                if operation == "create":
                    pending = asyncio.create_task(client.post(DEFINITIONS, json={"name": "New", "category_id": str(category.id)}, headers=headers))
                else:
                    pending = asyncio.create_task(client.post(f"{DEFINITIONS}/{row.id}/restore", headers=headers))
                await asyncio.wait_for(started.wait(), timeout=15)
                async def observe_block():
                    while True:
                        blocking = await writer.scalar(text("SELECT pg_blocking_pids(:pid)"), {"pid": waiter_pid})
                        if writer_pid in blocking:
                            return
                        if pending.done():
                            raise AssertionError("Catalog request failed to wait for the category lock")
                        await asyncio.sleep(0.01)
                await asyncio.wait_for(observe_block(), timeout=15)
                await writer.commit()
                response = await asyncio.wait_for(pending, timeout=15)
                assert response.status_code == 409
                assert response.json()["detail"]["code"] == ("RESOURCE_CHANGED" if operation == "moved_definition" else "STATE_CONFLICT")
            finally:
                await writer.rollback()
                if pending is not None and not pending.done():
                    pending.cancel()
                    await asyncio.gather(pending, return_exceptions=True)
        async with sessions() as session:
            stored = await session.get(ItemDefinition, row.id)
            assert stored.status == "ARCHIVED"
            assert await session.scalar(text("SELECT count(*) FROM item_definition")) == 1
    asyncio.run(exercise(db, scenario))


@pytest.mark.parametrize("operation", ["create", "patch", "restore"])
def test_unrelated_constraint_failures_roll_back_and_leave_session_usable(catalog_context, operation):
    db, owner, _, category, _ = catalog_context
    row = seed_definition(db, category.id, owner_id=owner.id,
                          name="Blocked" if operation == "restore" else "Original",
                          status="ARCHIVED" if operation == "restore" else "ACTIVE")
    with db[2].begin() as connection:
        connection.execute(text("ALTER TABLE item_definition ADD CONSTRAINT reject_fixture_name CHECK (name <> 'Blocked' OR status <> 'ACTIVE')"))
    async def scenario(client, sessions):
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                if operation == "create":
                    await service.create_definition(session, owner.id, name="Blocked", category_id=category.id)
                elif operation == "patch":
                    await service.update_definition(session, row.id, owner.id, changes={"name": "Blocked"})
                else:
                    await service.set_definition_status(session, row.id, owner.id, target_status="ACTIVE")
            stored = await session.get(ItemDefinition, row.id)
            assert stored.name == row.name and stored.status == row.status and stored.normalized_name == row.normalized_name
            saved = await service.create_definition(session, owner.id, name="Allowed", category_id=category.id)
            assert saved.name == "Allowed"
    asyncio.run(exercise(db, scenario))


@pytest.mark.parametrize("path", [CATEGORIES, DEFINITIONS])
def test_catalog_pagination_counts_and_rows_share_one_statement(catalog_context, monkeypatch, path):
    db, owner, _, category, headers = catalog_context
    seed_definition(db, category.id, owner_id=owner.id)
    execute = AsyncSession.execute
    queries = []
    async def observe(session, statement, *args, **kwargs):
        sql = str(statement)
        if "item_category" in sql or "item_definition" in sql:
            queries.append(sql)
        return await execute(session, statement, *args, **kwargs)
    monkeypatch.setattr(AsyncSession, "execute", observe)
    async def scenario(client, sessions):
        response = await client.get(path, params={"page": 99}, headers=headers)
        assert response.status_code == 200 and response.json()["items"] == [] and response.json()["total"] == 1
    asyncio.run(exercise(db, scenario))
    assert len(queries) == 1 and "count(" in queries[0].lower()
