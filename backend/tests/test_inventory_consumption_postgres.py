"""CONSUME transaction rollback and concurrent submission checks."""
import asyncio
from decimal import Decimal

import pytest
from sqlalchemy import select, func, text
from sqlalchemy.exc import IntegrityError

from app.db.models import InventoryItem, InventoryOperation
from app.services import inventory as service
from auth_test_support import exercise
from inventory_test_support import inventory_context, seed_inventory
from test_inventory_additions import headers, url
from test_inventory_consumption_quantities import consumption

pytestmark = pytest.mark.postgres


@pytest.mark.parametrize("same_key", [pytest.param(True, marks=pytest.mark.ci), False])
def test_concurrent_consumptions_cannot_double_consume(inventory_context, monkeypatch, same_key):
    c = inventory_context; item = seed_inventory(c)
    original = service._operation_by_key
    async def scenario(client, sessions):
        ready = asyncio.Event(); seen = set()
        async def lookup(session, key):
            row = await original(session, key)
            if id(session) not in seen:
                seen.add(id(session))
                if len(seen) == 2:
                    ready.set()
                await asyncio.wait_for(ready.wait(), 10)
            return row
        monkeypatch.setattr(service, "_operation_by_key", lookup)
        async def send(key):
            return await client.post(url(item), json=consumption(quantity_value="2", quantity_unit="kg"), headers=headers(c, key))
        responses = await asyncio.wait_for(asyncio.gather(send("first"), send("first" if same_key else "second")), 20)
        assert sorted(r.status_code for r in responses) == ([200, 201] if same_key else [201, 409])
        if same_key:
            assert responses[0].json()["operation"]["id"] == responses[1].json()["operation"]["id"]
        else:
            assert next(r for r in responses if r.status_code == 409).json()["detail"]["code"] == "VERSION_CONFLICT"
        async with sessions() as session:
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 2 and actual.confirmed_current_amount == Decimal(".5")
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.ci
def test_consumption_insert_failure_rolls_back_and_allows_retry(inventory_context):
    c = inventory_context; item = seed_inventory(c)
    with c[0][2].begin() as connection:
        connection.execute(text("ALTER TABLE inventory_operation ADD CONSTRAINT reject_consumption_test CHECK (quantity_value <> '500')"))
    async def scenario(client, sessions):
        async with sessions() as session:
            arguments = dict(expected_version=1, operation_type="CONSUME", quantity_kind="AMOUNT", quantity_unit="g", idempotency_key="retry")
            with pytest.raises(IntegrityError):
                await service.submit_inventory_operation(session, item.id, c[1].id, quantity_value="500", **arguments)
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 1 and actual.confirmed_current_amount == item.confirmed_current_amount
            assert actual.confirmed_at == item.confirmed_at and actual.updated_at == item.updated_at
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 0
            result = await service.submit_inventory_operation(session, item.id, c[1].id, quantity_value="250", **arguments)
            assert result.inventory.version == 2 and not result.replayed
            assert result.inventory.confirmed_current_amount == Decimal("2.25")
    asyncio.run(exercise(c[0], scenario))
