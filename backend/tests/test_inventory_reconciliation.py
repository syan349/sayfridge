"""RECONCILE API acceptance using isolated real PostgreSQL schemas."""
from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, StorageSpace
from auth_test_support import request
from inventory_test_support import inventory_context, seed_inventory, seed_space
from test_inventory_additions import assert_unchanged, headers, url
from test_inventory_reconciliation_quantities import reconciliation

pytestmark = pytest.mark.postgres


def send(context, item, key="reconciliation-1", **changes):
    return request(context[0], "POST", url(item), json=reconciliation(**changes),
                   headers=headers(context, key))


@pytest.mark.ci
def test_reconcile_confirms_total_clears_estimate_and_replays(inventory_context):
    context = inventory_context
    previous_confirmation = datetime.now(timezone.utc)
    previous_estimate = datetime.now(timezone.utc)
    item = seed_inventory(
        context,
        confirmed_current_amount=Decimal("10"), confirmed_current_unit="kg",
        confirmed_at=previous_confirmation,
        estimated_current_amount=Decimal("7"), estimated_current_unit="kg",
        estimated_at=previous_estimate,
    )

    response = send(context, item, quantity_value="6000.0", quantity_unit=" g ")
    assert response.status_code == 201, response.text
    result = response.json(); operation = result["operation"]; inventory = result["inventory"]
    assert result["replayed"] is False and inventory["version"] == 2
    assert Decimal(inventory["confirmed_current_amount"]) == Decimal("6000")
    assert inventory["confirmed_current_unit"] == "g" and inventory["status"] == "IN_STOCK"
    assert inventory["estimated_current_amount"] is None
    assert inventory["estimated_current_unit"] is None and inventory["estimated_at"] is None
    assert Decimal(inventory["initial_amount"]) == item.initial_amount
    assert operation["operation_type"] == "RECONCILE" and operation["quantity_kind"] == "AMOUNT"
    assert operation["quantity_value"] == "6000.0" and operation["quantity_unit"] == "g"
    assert operation["calculation_method"] == "EXACT"
    assert operation["affects_state"] == "CONFIRMED" and operation["status"] == "SUCCESS"
    assert operation["applied_change_amount"] is None and operation["applied_change_unit"] is None

    replay = send(context, item, quantity_value="6000.0", quantity_unit="g", expected_version=99)
    assert replay.status_code == 200 and replay.json()["replayed"] is True
    assert replay.json()["operation"] == operation
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 1


@pytest.mark.parametrize("total,status", [("0", "EMPTY"), ("2.5", "IN_STOCK")])
def test_reconcile_records_a_new_confirmation_even_when_total_is_unchanged(
        inventory_context, total, status):
    context = inventory_context
    amount = Decimal(total)
    item = seed_inventory(context, confirmed_current_amount=amount,
                          status="EMPTY" if amount == 0 else "IN_STOCK")
    response = send(context, item, quantity_value=total)
    assert response.status_code == 201, response.text
    assert response.json()["inventory"]["version"] == 2
    assert response.json()["inventory"]["status"] == status
    with Session(context[0][2]) as session:
        actual = session.get(InventoryItem, item.id)
        assert actual.confirmed_at > item.confirmed_at
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 1


@pytest.mark.parametrize("total,space_status,expected", [
    ("1", "ACTIVE", 201),
    pytest.param("1", "ARCHIVED", 409),
    ("0", "ARCHIVED", 201),
])
def test_reconcile_empty_inventory_applies_space_rules(
        inventory_context, total, space_status, expected):
    context = inventory_context
    item = seed_inventory(context, status="EMPTY", confirmed_current_amount=Decimal("0"))
    with Session(context[0][2]) as session:
        session.execute(update(StorageSpace).where(StorageSpace.id == context[4].id)
                        .values(status=space_status))
        session.commit()
    response = send(context, item, quantity_value=total)
    assert response.status_code == expected, response.text
    if expected == 201:
        expected_status = "EMPTY" if total == "0" else "IN_STOCK"
        assert response.json()["inventory"]["status"] == expected_status
    else:
        assert response.json()["detail"]["code"] == "STATE_CONFLICT"
        assert_unchanged(context, item)


@pytest.mark.parametrize("state", ["DISCARDED", "ARCHIVED"])
def test_reconciliation_rejects_terminal_inventory(inventory_context, state):
    context = inventory_context; item = seed_inventory(context, status=state)
    response = send(context, item)
    assert response.status_code == 409 and response.json()["detail"]["code"] == "STATE_CONFLICT"
    assert_unchanged(context, item)


@pytest.mark.parametrize("version,expected,code", [
    (2, 1, "VERSION_CONFLICT"),
    (2147483647, 2147483647, "VERSION_LIMIT_REACHED"),
])
def test_reconciliation_version_checks_are_atomic(inventory_context, version, expected, code):
    context = inventory_context; item = seed_inventory(context, version=version)
    response = send(context, item, expected_version=expected)
    assert response.status_code == 409 and response.json()["detail"]["code"] == code
    assert_unchanged(context, item)


@pytest.mark.parametrize("changes", [
    {"quantity_value": "6.0"}, {"quantity_unit": "G"},
    {"operation_type": "ADD"}, {"operation_type": "CONSUME"},
])
def test_reconciliation_idempotency_compares_literal_business_input(inventory_context, changes):
    context = inventory_context; item = seed_inventory(context, confirmed_current_amount=Decimal("10"))
    assert send(context, item).status_code == 201
    response = send(context, item, **changes)
    assert response.status_code == 409 and response.json()["detail"]["code"] == "IDEMPOTENCY_CONFLICT"


def test_reconciliation_requires_authentication_and_ownership(inventory_context):
    context = inventory_context; item = seed_inventory(context)
    assert request(context[0], "POST", url(item), json=reconciliation(),
                   headers={"Idempotency-Key": "x"}).status_code == 401
    foreign_space = seed_space(context[0], context[2].id, "Foreign")
    with Session(context[0][2]) as session:
        session.execute(update(InventoryItem).where(InventoryItem.id == item.id)
                        .values(storage_space_id=foreign_space.id))
        session.commit()
    response = send(context, item)
    assert response.status_code == 404 and response.json()["detail"]["code"] == "NOT_FOUND"
    assert_unchanged(context, item)
