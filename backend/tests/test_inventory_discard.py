"""Inventory discard state transition, isolation, and concurrency checks."""
import asyncio
from datetime import date, datetime, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, StorageSpace
from auth_test_support import exercise, request
from inventory_test_support import BASE, inventory_context, seed_inventory, seed_space

pytestmark = pytest.mark.postgres


def discard(context, item_id, body=None, headers=None):
    return request(
        context[0],
        "POST",
        f"{BASE}/{item_id}/discard",
        json={"expected_version": 1} if body is None else body,
        headers=context[-1] if headers is None else headers,
    )


@pytest.mark.ci
def test_discard_preserves_inventory_facts_and_creates_no_operation(inventory_context):
    context = inventory_context
    estimated_at = datetime.now(timezone.utc)
    item = seed_inventory(
        context,
        initial_amount=Decimal("10"),
        confirmed_current_amount=Decimal("8"),
        estimated_current_amount=Decimal("7"),
        estimated_current_unit="kg",
        estimated_at=estimated_at,
        purchase_date=date(2026, 9, 1),
        expiry_date=date(2026, 10, 1),
        notes="Opened",
    )

    response = discard(context, item.id)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "DISCARDED" and body["version"] == 2
    assert Decimal(body["initial_amount"]) == item.initial_amount
    assert body["initial_unit"] == item.initial_unit
    assert Decimal(body["confirmed_current_amount"]) == item.confirmed_current_amount
    assert body["confirmed_current_unit"] == item.confirmed_current_unit
    assert Decimal(body["estimated_current_amount"]) == item.estimated_current_amount
    assert body["estimated_current_unit"] == item.estimated_current_unit
    assert body["notes"] == item.notes
    assert body["storage_space_id"] == str(item.storage_space_id)
    assert body["item_definition_id"] == str(item.item_definition_id)
    assert body["purchase_date"] == item.purchase_date.isoformat()
    assert body["expiry_date"] == item.expiry_date.isoformat()
    for field in ("confirmed_at", "estimated_at"):
        actual = datetime.fromisoformat(body[field].replace("Z", "+00:00"))
        assert actual == getattr(item, field)
    assert datetime.fromisoformat(body["created_at"].replace("Z", "+00:00")) == item.created_at
    assert datetime.fromisoformat(body["updated_at"].replace("Z", "+00:00")) > item.updated_at
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 0


@pytest.mark.parametrize("state", ["EMPTY", "DISCARDED", "ARCHIVED"])
def test_discard_rejects_non_in_stock_states_without_changes(inventory_context, state):
    context = inventory_context
    item = seed_inventory(
        context,
        status=state,
        confirmed_current_amount=Decimal("0") if state == "EMPTY" else Decimal("2.5"),
    )

    response = discard(context, item.id)

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "STATE_CONFLICT"
    with Session(context[0][2]) as session:
        stored = session.get(InventoryItem, item.id)
        assert stored.status == state and stored.version == 1


def test_discard_requires_current_version_and_enforces_version_limit(inventory_context):
    context = inventory_context
    stale = seed_inventory(context, version=2)
    maximum = seed_inventory(context, version=2147483647)

    stale_response = discard(context, stale.id)
    maximum_response = discard(context, maximum.id, {"expected_version": 2147483647})

    assert stale_response.status_code == 409
    assert stale_response.json()["detail"]["code"] == "VERSION_CONFLICT"
    assert maximum_response.status_code == 409
    assert maximum_response.json()["detail"]["code"] == "VERSION_LIMIT_REACHED"


def test_discard_hides_foreign_and_missing_inventory(inventory_context):
    context = inventory_context
    foreign_space = seed_space(context[0], context[2].id)
    foreign = seed_inventory(context, storage_space_id=foreign_space.id)

    responses = [discard(context, item_id) for item_id in (foreign.id, uuid.uuid4())]

    assert all(response.status_code == 404 for response in responses)
    assert responses[0].json() == responses[1].json()


@pytest.mark.parametrize(
    "body",
    [None, {}, {"expected_version": None}, {"expected_version": True},
     {"expected_version": 0}, {"expected_version": 2147483648},
     {"expected_version": 1, "status": "DISCARDED"}],
)
def test_discard_rejects_invalid_bodies(inventory_context, body):
    context = inventory_context
    item = seed_inventory(context)
    response = request(
        context[0], "POST", f"{BASE}/{item.id}/discard",
        json=body, headers=context[-1],
    )
    assert response.status_code == 422
    with Session(context[0][2]) as session:
        stored = session.get(InventoryItem, item.id)
        assert stored.status == "IN_STOCK" and stored.version == 1


def test_discard_requires_authentication(inventory_context):
    item = seed_inventory(inventory_context)
    assert discard(inventory_context, item.id, headers={}).status_code == 401


def test_discard_is_allowed_in_an_archived_space(inventory_context):
    context = inventory_context
    item = seed_inventory(context)
    with Session(context[0][2]) as session:
        space = session.get(StorageSpace, context[4].id)
        space.status = "ARCHIVED"
        session.commit()

    response = discard(context, item.id)

    assert response.status_code == 200
    assert response.json()["status"] == "DISCARDED"


@pytest.mark.ci
def test_concurrent_discards_with_one_version_have_one_winner(inventory_context):
    context = inventory_context
    item = seed_inventory(context)

    async def scenario(client, _sessions):
        async def send():
            return await client.post(
                f"{BASE}/{item.id}/discard",
                json={"expected_version": 1}, headers=context[-1],
            )

        responses = await asyncio.wait_for(asyncio.gather(send(), send()), 20)
        assert sorted(response.status_code for response in responses) == [200, 409]
        conflict = next(response for response in responses if response.status_code == 409)
        assert conflict.json()["detail"]["code"] == "VERSION_CONFLICT"
        async with _sessions() as session:
            stored = await session.get(InventoryItem, item.id)
            assert stored.status == "DISCARDED" and stored.version == 2

    asyncio.run(exercise(context[0], scenario))
