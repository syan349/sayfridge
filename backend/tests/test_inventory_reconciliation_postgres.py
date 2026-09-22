"""RECONCILE transaction rollback and concurrent request checks."""
import asyncio
from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError

from app.db.models import InventoryItem, InventoryOperation
from app.services import inventory as service
from auth_test_support import exercise
from inventory_test_support import inventory_context, seed_inventory
from test_inventory_additions import headers, url
from test_inventory_reconciliation_quantities import reconciliation

pytestmark = pytest.mark.postgres


@pytest.mark.ci
def test_concurrent_identical_reconciliations_apply_once(inventory_context, monkeypatch):
    context = inventory_context; item = seed_inventory(context)
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

        async def send():
            return await client.post(url(item), json=reconciliation(), headers=headers(context, "same"))

        responses = await asyncio.wait_for(asyncio.gather(send(), send()), 20)
        assert sorted(response.status_code for response in responses) == [200, 201]
        assert responses[0].json()["operation"]["id"] == responses[1].json()["operation"]["id"]
        async with sessions() as session:
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 2 and actual.confirmed_current_amount == Decimal("6")
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 1

    asyncio.run(exercise(context[0], scenario))


@pytest.mark.ci
def test_reconciliation_insert_failure_rolls_back_and_allows_retry(inventory_context):
    context = inventory_context
    item = seed_inventory(
        context,
        confirmed_current_amount=Decimal("10"),
        estimated_current_amount=Decimal("7"), estimated_current_unit="kg",
        estimated_at=datetime.now(timezone.utc),
    )
    with context[0][2].begin() as connection:
        connection.execute(text(
            "ALTER TABLE inventory_operation ADD CONSTRAINT reject_reconciliation_test "
            "CHECK (quantity_value <> '6')"
        ))

    async def scenario(client, sessions):
        arguments = dict(expected_version=1, operation_type="RECONCILE", quantity_kind="AMOUNT",
                         quantity_unit="kg", idempotency_key="retry")
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                await service.submit_inventory_operation(
                    session, item.id, context[1].id, quantity_value="6", **arguments
                )
            actual = await session.get(InventoryItem, item.id)
            assert actual.version == 1 and actual.confirmed_current_amount == Decimal("10")
            assert actual.estimated_current_amount == Decimal("7")
            assert actual.confirmed_at == item.confirmed_at and actual.updated_at == item.updated_at
            assert await session.scalar(select(func.count()).select_from(InventoryOperation)) == 0

            result = await service.submit_inventory_operation(
                session, item.id, context[1].id, quantity_value="5", **arguments
            )
            assert result.inventory.version == 2 and not result.replayed
            assert result.inventory.confirmed_current_amount == Decimal("5")
            assert result.inventory.estimated_current_amount is None

    asyncio.run(exercise(context[0], scenario))
