"""Real PostgreSQL concurrency and transaction failure checks for ADD."""
import asyncio
from decimal import Decimal

import pytest
from sqlalchemy import select, func, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation
from app.services import inventory as service
from auth_test_support import exercise
from inventory_test_support import inventory_context, seed_inventory, seed_space
from test_inventory_additions import addition, headers, url

pytestmark = pytest.mark.postgres


@pytest.mark.parametrize(
    "same_key",
    [
        pytest.param(
            True,
            marks=[pytest.mark.database_acceptance],
        ),
        False,
    ],
)
def test_concurrent_additions_apply_once_for_one_version(inventory_context, monkeypatch, same_key):
    c=inventory_context;item=seed_inventory(c)
    original=service._operation_by_key
    async def scenario(client,sessions):
        ready=asyncio.Event(); seen=set()
        async def lookup(session,key):
            row=await original(session,key)
            if id(session) not in seen:
                seen.add(id(session))
                if len(seen)==2: ready.set()
                await asyncio.wait_for(ready.wait(),10)
            return row
        monkeypatch.setattr(service,"_operation_by_key",lookup)
        async def send(key):
            return await client.post(url(item),json=addition(),headers=headers(c,key))
        responses=await asyncio.wait_for(asyncio.gather(send("first"),send("first" if same_key else "second")),20)
        assert sorted(r.status_code for r in responses)==([200,201] if same_key else [201,409])
        if same_key:
            assert responses[0].json()["operation"]["id"]==responses[1].json()["operation"]["id"]
        async with sessions() as session:
            actual=await session.get(InventoryItem,item.id)
            assert actual.version==2 and actual.confirmed_current_amount==Decimal("3000.000")
            assert await session.scalar(select(func.count()).select_from(InventoryOperation))==1
    asyncio.run(exercise(c[0],scenario))


def test_concurrent_same_key_across_spaces_uses_unique_constraint(inventory_context,monkeypatch):
    c=inventory_context;first=seed_inventory(c)
    other_space=seed_space(c[0],c[1].id,"Other")
    second=seed_inventory(c,storage_space_id=other_space.id)
    original=service._operation_by_key
    async def scenario(client,sessions):
        ready=asyncio.Event();calls={};arrivals=0
        async def lookup(session,key):
            nonlocal arrivals
            row=await original(session,key)
            calls[id(session)]=calls.get(id(session),0)+1
            # Both transactions have their different space/item locks and see no key.
            if calls[id(session)]==2:
                arrivals+=1
                if arrivals==2:ready.set()
                await asyncio.wait_for(ready.wait(),10)
            return row
        monkeypatch.setattr(service,"_operation_by_key",lookup)
        responses=await asyncio.wait_for(asyncio.gather(*[
            client.post(url(item),json=addition(),headers=headers(c,"shared")) for item in (first,second)
        ]),20)
        assert sorted(r.status_code for r in responses)==[201,409]
        assert next(r for r in responses if r.status_code==409).json()["detail"]["code"]=="IDEMPOTENCY_CONFLICT"
        assert max(calls.values())==3  # Losing transaction re-read after rollback.
        async with sessions() as session:
            rows=(await session.scalars(select(InventoryItem))).all()
            assert sorted(row.version for row in rows)==[1,2]
            assert sum(row.confirmed_current_amount * (1000 if row.confirmed_current_unit == "kg" else 1) for row in rows)==Decimal("5500")
            assert await session.scalar(select(func.count()).select_from(InventoryOperation))==1
    asyncio.run(exercise(c[0],scenario))


@pytest.mark.ci
@pytest.mark.database_acceptance
def test_operation_insert_failure_rolls_back_inventory_and_session_recovers(inventory_context):
    c=inventory_context;item=seed_inventory(c)
    with c[0][2].begin() as connection:
        connection.execute(text("ALTER TABLE inventory_operation ADD CONSTRAINT reject_test_operation CHECK (quantity_value <> '500')"))
    async def scenario(client,sessions):
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                await service.add_inventory(session,item.id,c[1].id,expected_version=1,
                    quantity_value="500",quantity_unit="g",idempotency_key="retry")
            actual=await session.get(InventoryItem,item.id)
            assert actual.version==1 and actual.confirmed_current_amount==item.confirmed_current_amount
            assert actual.confirmed_at==item.confirmed_at and actual.updated_at==item.updated_at
            assert await session.scalar(select(func.count()).select_from(InventoryOperation))==0
            result=await service.add_inventory(session,item.id,c[1].id,expected_version=1,
                quantity_value="250",quantity_unit="g",idempotency_key="retry")
            assert result.inventory.version==2 and not result.replayed
    asyncio.run(exercise(c[0],scenario))


@pytest.mark.parametrize("action,code",[
    pytest.param("archive","STATE_CONFLICT",marks=[]),
    ("move","RESOURCE_CHANGED"),
])
def test_addition_rechecks_changes_after_waiting_for_space_lock(inventory_context,monkeypatch,action,code):
    c=inventory_context
    item=seed_inventory(c,status="EMPTY",confirmed_current_amount=Decimal("0"))
    target=seed_space(c[0],c[1].id,"Destination") if action=="move" else None
    original=service._space
    async def scenario(client,sessions):
        started=asyncio.Event();waiter_pid=None
        async def observed(session,space_id,user_id):
            nonlocal waiter_pid
            waiter_pid=await session.scalar(text("SELECT pg_backend_pid()"));started.set()
            return await original(session,space_id,user_id)
        monkeypatch.setattr(service,"_space",observed)
        async with sessions() as writer:
            writer_pid=await writer.scalar(text("SELECT pg_backend_pid()"))
            await writer.execute(text("SELECT id FROM storage_space WHERE id=:id FOR UPDATE"),{"id":c[4].id})
            pending=asyncio.create_task(client.post(url(item),json=addition(),headers=headers(c)))
            try:
                await asyncio.wait_for(started.wait(),10)
                async def blocked():
                    while writer_pid not in await writer.scalar(text("SELECT pg_blocking_pids(:pid)"),{"pid":waiter_pid}):
                        assert not pending.done()
                        await asyncio.sleep(.01)
                await asyncio.wait_for(blocked(),10)
                if action=="archive":
                    await writer.execute(text("UPDATE storage_space SET status='ARCHIVED' WHERE id=:id"),{"id":c[4].id})
                else:
                    await writer.execute(text("UPDATE inventory_item SET storage_space_id=:target, version=version+1 WHERE id=:id"),{"target":target.id,"id":item.id})
                await writer.commit()
                response=await asyncio.wait_for(pending,10)
                assert response.status_code==409 and response.json()["detail"]["code"]==code
            finally:
                await writer.rollback()
                if not pending.done():pending.cancel()
                await asyncio.gather(pending,return_exceptions=True)
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryOperation))==0
            assert (await session.get(InventoryItem,item.id)).confirmed_current_amount==Decimal("0")
    asyncio.run(exercise(c[0],scenario))


def test_idempotency_key_is_scoped_to_each_user(inventory_context):
    c=inventory_context;first=seed_inventory(c)
    other_space=seed_space(c[0],c[2].id,"Other user")
    second=seed_inventory(c,storage_space_id=other_space.id)
    async def scenario(client,sessions):
        for row,owner in [(first,c[1]),(second,c[2])]:
            async with sessions() as session:
                result=await service.add_inventory(session,row.id,owner.id,expected_version=1,
                    quantity_value="500",quantity_unit="g",idempotency_key="same-client-key")
                assert not result.replayed
        async with sessions() as session:
            assert await session.scalar(select(func.count()).select_from(InventoryOperation))==2
    asyncio.run(exercise(c[0],scenario))
