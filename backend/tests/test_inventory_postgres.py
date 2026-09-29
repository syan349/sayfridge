"""Inventory lock coordination, atomic writes, and migration compatibility."""
import asyncio

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.models import InventoryItem
from app.services import inventory as service
from auth_test_support import exercise
from inventory_test_support import inventory_context, seed_inventory, seed_space, payload, BASE

pytestmark = pytest.mark.postgres


@pytest.mark.ci
def test_concurrent_metadata_writes_with_same_version_have_one_winner(inventory_context):
    c=inventory_context;row=seed_inventory(c)
    async def scenario(client,sessions):
        async def change(note):
            return await client.patch(BASE+"/"+str(row.id),json={"expected_version":1,"notes":note},headers=c[-1])
        results=await asyncio.gather(change("first"),change("second"))
        assert sorted(r.status_code for r in results)==[200,409]
        async with sessions() as session:
            item=await session.get(InventoryItem,row.id)
            assert item.version==2 and item.notes in {"first","second"}
    asyncio.run(exercise(c[0],scenario))


@pytest.mark.parametrize("operation",[pytest.param("create",marks=[]),"move"])
def test_waiting_inventory_write_rechecks_archived_target_space(inventory_context,monkeypatch,operation):
    c=inventory_context
    target=seed_space(c[0],c[1].id,"Destination") if operation=="move" else c[4]
    row=seed_inventory(c) if operation=="move" else None
    original=service._space
    async def scenario(client,sessions):
        started=asyncio.Event();waiter_pid=None
        async def observed(session,space_id,user_id):
            nonlocal waiter_pid
            if space_id==target.id:
                waiter_pid=await session.scalar(text("SELECT pg_backend_pid()"));started.set()
            return await original(session,space_id,user_id)
        monkeypatch.setattr(service,"_space",observed)
        async with sessions() as writer:
            writer_pid=await writer.scalar(text("SELECT pg_backend_pid()"))
            await writer.execute(text("UPDATE storage_space SET status='ARCHIVED' WHERE id=:id"),{"id":target.id})
            if operation=="create":
                pending=asyncio.create_task(client.post(BASE,json=payload(c),headers=c[-1]))
            else:
                pending=asyncio.create_task(client.patch(BASE+"/"+str(row.id),json={"expected_version":1,"storage_space_id":str(target.id)},headers=c[-1]))
            try:
                await asyncio.wait_for(started.wait(),15)
                async def blocked():
                    while writer_pid not in await writer.scalar(text("SELECT pg_blocking_pids(:pid)"),{"pid":waiter_pid}):
                        assert not pending.done(), "Request did not wait for target lock"
                        await asyncio.sleep(.01)
                await asyncio.wait_for(blocked(),15)
                await writer.commit()
                response=await asyncio.wait_for(pending,15)
                assert response.status_code==409,response.text
                assert response.json()["detail"]["code"]=="STATE_CONFLICT"
            finally:
                await writer.rollback()
                if not pending.done():
                    pending.cancel()
                await asyncio.gather(pending,return_exceptions=True)
        async with sessions() as session:
            if row is None:
                assert await session.scalar(select(func.count()).select_from(InventoryItem))==0
            else:
                actual=await session.get(InventoryItem,row.id)
                assert actual.storage_space_id==c[4].id and actual.version==1
    asyncio.run(exercise(c[0],scenario))


@pytest.mark.parametrize("operation",["create","patch"])
def test_database_failure_rolls_back_stock_and_keeps_session_usable(inventory_context,operation):
    c=inventory_context;row=seed_inventory(c) if operation=="patch" else None
    with c[0][2].begin() as connection:
        connection.execute(text("ALTER TABLE inventory_item ADD CONSTRAINT reject_test_note CHECK (notes IS DISTINCT FROM 'blocked')"))
    async def scenario(client,sessions):
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                if operation=="create":
                    values=payload(c,notes="blocked")
                    # Services receive validated UUIDs and normalized units from schemas.
                    from app.schemas.inventory import InventoryCreate
                    await service.create_inventory(session,c[1].id,**InventoryCreate(**values).model_dump())
                else:
                    await service.update_inventory(session,row.id,c[1].id,expected_version=1,changes={"notes":"blocked"})
            if operation=="create":
                assert await session.scalar(select(func.count()).select_from(InventoryItem))==0
                from app.schemas.inventory import InventoryCreate
                result=await service.create_inventory(session,c[1].id,**InventoryCreate(**payload(c,notes="allowed")).model_dump())
                assert result.version==1
            else:
                actual=await session.get(InventoryItem,row.id)
                assert actual.version==1 and actual.notes is None
                result=await service.update_inventory(session,row.id,c[1].id,expected_version=1,changes={"notes":"allowed"})
                assert result.version==2
    asyncio.run(exercise(c[0],scenario))


def test_fresh_schema_supports_nullable_notes_without_changing_stock(inventory_context):
    c = inventory_context
    row = seed_inventory(c, version=7)
    with Session(c[0][2]) as session:
        actual = session.get(InventoryItem, row.id)
        assert actual.notes is None
        actual.notes = "Opened today"
        session.commit()
    with Session(c[0][2]) as session:
        actual = session.get(InventoryItem, row.id)
        assert actual.notes == "Opened today" and actual.version == 7
        assert actual.confirmed_current_amount == row.confirmed_current_amount
        assert actual.confirmed_at == row.confirmed_at
