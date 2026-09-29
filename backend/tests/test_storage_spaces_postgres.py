"""B04 real PostgreSQL concurrency, snapshot, and transaction regression tests."""
import asyncio
import uuid

import pytest
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.models import StorageSpace
from app.services import storage_spaces as service
from auth_test_support import exercise, make_user, seed_users
from test_storage_spaces_api import BASE, seed_inventory, seed_space

pytestmark = pytest.mark.postgres


def setup_owner(database):
    owner = make_user()
    seed_users(database, owner)
    token = create_access_token(owner.id, get_settings().jwt_secret_key, 15)
    return owner, {"Authorization": f"Bearer {token}"}


@pytest.mark.parametrize("operation", [pytest.param("create"), "rename", "restore"])
def test_concurrent_active_name_claims_have_one_winner(database, operation):
    """Independent requests contend for the same unique index; only one commits."""
    owner, headers = setup_owner(database)
    if operation == "restore":
        spaces = [seed_space(database, owner.id, name="Shared", status="ARCHIVED") for _ in range(2)]
    elif operation == "rename":
        spaces = [seed_space(database, owner.id, name=f"Original {i}") for i in range(2)]
    async def scenario(client, sessions):
        if operation == "create":
            requests = [client.post(BASE, json={"name": name, "type": "FRIDGE"}, headers=headers)
                        for name in ["Shared", "SHARED"]]
        elif operation == "restore":
            requests = [client.post(f"{BASE}/{space.id}/restore", headers=headers) for space in spaces]
        else:
            requests = [client.patch(f"{BASE}/{space.id}", json={"name": "Shared"}, headers=headers) for space in spaces]
        results = await asyncio.wait_for(asyncio.gather(*requests), timeout=30)
        assert sorted(r.status_code for r in results) == [201 if operation == "create" else 200, 409]
        assert next(r for r in results if r.status_code == 409).json()["detail"]["code"] == "NAME_CONFLICT"
        async with sessions() as session:
            winners = (await session.execute(text("SELECT id FROM storage_space WHERE lower(name)='shared' AND status='ACTIVE'"))).all()
            assert len(winners) == 1
            if operation == "restore":
                assert await session.scalar(text("SELECT count(*) FROM storage_space WHERE status='ARCHIVED'")) == 1
            elif operation == "rename":
                assert await session.scalar(text("SELECT count(*) FROM storage_space WHERE name LIKE 'Original %'")) == 1
    asyncio.run(exercise(database, scenario))


@pytest.mark.parametrize("operation", [pytest.param("archive_after_stock"), "patch_after_archive"])
def test_waiting_write_rechecks_committed_state_after_space_lock(database, monkeypatch, operation):
    """Hold a real row lock, prove the API waits on it, then commit a conflicting change."""
    owner, headers = setup_owner(database)
    space = seed_space(database, owner.id)
    if operation == "archive_after_stock":
        item = seed_inventory(database, space.id, status="EMPTY")
    lookup = service.get_storage_space_by_id
    async def scenario(client, sessions):
        started = asyncio.Event()
        waiter_pid = None
        async def observe_lookup(session, space_id, user_id, *, lock=False):
            nonlocal waiter_pid
            if lock:
                waiter_pid = await session.scalar(text("SELECT pg_backend_pid()"))
                started.set()
            return await lookup(session, space_id, user_id, lock=lock)
        monkeypatch.setattr(service, "get_storage_space_by_id", observe_lookup)
        pending = None
        async with sessions() as writer:
            writer_pid = await writer.scalar(text("SELECT pg_backend_pid()"))
            await writer.execute(select(StorageSpace).where(StorageSpace.id == space.id).with_for_update())
            if operation == "archive_after_stock":
                await writer.execute(text("UPDATE inventory_item SET status='IN_STOCK', confirmed_current_amount=1 WHERE id=:id"), {"id": item.id})
            else:
                await writer.execute(text("UPDATE storage_space SET status='ARCHIVED' WHERE id=:id"), {"id": space.id})
            try:
                if operation == "archive_after_stock":
                    pending = asyncio.create_task(client.post(f"{BASE}/{space.id}/archive", headers=headers))
                else:
                    pending = asyncio.create_task(client.patch(f"{BASE}/{space.id}", json={"name": "Changed"}, headers=headers))
                await asyncio.wait_for(started.wait(), timeout=15)
                # Observe PostgreSQL's lock state, rather than relying on a timing guess.
                async def wait_for_block():
                    while True:
                        blockers = await writer.scalar(text("SELECT pg_blocking_pids(:pid)"), {"pid": waiter_pid})
                        if writer_pid in blockers:
                            return
                        if pending.done():
                            raise AssertionError("Request did not wait for the space row lock")
                        await asyncio.sleep(0.01)
                await asyncio.wait_for(wait_for_block(), timeout=15)
                await writer.commit()
                response = await asyncio.wait_for(pending, timeout=15)
                assert response.status_code == 409 and response.json()["detail"]["code"] == "STATE_CONFLICT"
            finally:
                await writer.rollback()
                if pending is not None and not pending.done():
                    pending.cancel()
                    await asyncio.gather(pending, return_exceptions=True)
        async with sessions() as session:
            stored = await session.get(StorageSpace, space.id)
            assert stored.name == "Kitchen"
            assert stored.status == ("ACTIVE" if operation == "archive_after_stock" else "ARCHIVED")
    asyncio.run(exercise(database, scenario))


@pytest.mark.parametrize("operation", ["create", "patch", "restore"])
def test_unrelated_database_failure_rolls_back_and_does_not_become_name_conflict(database, operation):
    owner, _ = setup_owner(database)
    existing = None
    if operation != "create":
        existing = seed_space(database, owner.id, name="Blocked" if operation == "restore" else "Kitchen",
                              status="ARCHIVED" if operation == "restore" else "ACTIVE")
    with database[2].begin() as connection:
        connection.execute(text("ALTER TABLE storage_space ADD CONSTRAINT reject_fixture_name CHECK (name <> 'Blocked' OR status <> 'ACTIVE')"))
    async def scenario(client, sessions):
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                if operation == "create":
                    await service.create_storage_space(session, owner.id, name="Blocked", type="FRIDGE")
                elif operation == "patch":
                    await service.update_storage_space(session, existing.id, owner.id, changes={"name": "Blocked", "type": "FREEZER"})
                else:
                    await service.set_storage_space_status(session, existing.id, owner.id, target_status="ACTIVE")
            # Queries and a subsequent write succeed on the SAME session after rollback.
            assert await session.scalar(text("SELECT count(*) FROM storage_space WHERE name='Blocked' AND status='ACTIVE'")) == 0
            if existing is not None:
                stored = await session.get(StorageSpace, existing.id)
                assert stored.name == existing.name and stored.status == existing.status and stored.type == "FRIDGE"
            saved = await service.create_storage_space(session, owner.id, name="Allowed", type="OTHER")
            assert saved.name == "Allowed"
    asyncio.run(exercise(database, scenario))


def test_list_count_and_page_use_one_database_statement(database, monkeypatch):
    """An empty page still returns the count from the same SQL statement/snapshot."""
    owner, headers = setup_owner(database)
    seed_space(database, owner.id)
    execute = AsyncSession.execute
    statements = []
    async def observe(session, statement, *args, **kwargs):
        sql = str(statement)
        if "storage_space" in sql:
            statements.append(sql)
        return await execute(session, statement, *args, **kwargs)
    monkeypatch.setattr(AsyncSession, "execute", observe)
    async def scenario(client, sessions):
        response = await client.get(BASE + "?page=2", headers=headers)
        assert response.status_code == 200 and response.json()["items"] == [] and response.json()["total"] == 1
    asyncio.run(exercise(database, scenario))
    assert len(statements) == 1 and "count(" in statements[0].lower()
