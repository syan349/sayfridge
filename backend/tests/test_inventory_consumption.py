"""CONSUME API acceptance using real isolated PostgreSQL schemas."""
from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import update, select, func
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, StorageSpace, ItemDefinition, ItemCategory
from auth_test_support import request
from inventory_test_support import inventory_context, seed_inventory, seed_space
from test_inventory_additions import headers, url, assert_unchanged, send as add
from test_inventory_consumption_quantities import consumption

pytestmark = pytest.mark.postgres


def send(context, item, key="consumption-1", **changes):
    return request(context[0], "POST", url(item), json=consumption(**changes), headers=headers(context, key))


@pytest.mark.ci
def test_consumption_and_replay_preserve_history_and_empty_state(inventory_context):
    c = inventory_context; item = seed_inventory(c)
    response = send(c, item, quantity_value="2500.0", quantity_unit=" G ")
    assert response.status_code == 201, response.text
    result = response.json(); operation = result["operation"]
    assert result["inventory"]["status"] == "EMPTY" and result["inventory"]["version"] == 2
    assert Decimal(result["inventory"]["confirmed_current_amount"]) == 0
    assert Decimal(result["inventory"]["initial_amount"]) == Decimal("2.5")
    assert operation["operation_type"] == "CONSUME" and operation["quantity_kind"] == "AMOUNT"
    assert operation["quantity_value"] == "2500.0" and operation["quantity_unit"] == "G"
    assert operation["calculation_method"] == "CONVERTED" and operation["affects_state"] == "CONFIRMED"
    assert operation["input_method"] == "MANUAL" and operation["status"] == "SUCCESS"
    assert Decimal(operation["applied_change_amount"]) == Decimal("2.5")
    assert operation["applied_change_unit"] == "kg" and "idempotency_key" not in operation
    replay = send(c, item, quantity_value="2500.0", quantity_unit="G", expected_version=99)
    assert replay.status_code == 200 and replay.json()["replayed"] is True
    assert replay.json()["operation"] == operation
    with Session(c[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 1


@pytest.mark.ci
def test_fraction_consumption_preserves_estimated_state_at_zero(inventory_context):
    c = inventory_context; now = datetime.now(timezone.utc)
    item = seed_inventory(c, estimated_current_amount=Decimal("1"), estimated_current_unit="kg", estimated_at=now)
    response = send(c, item, quantity_kind="FRACTION", quantity_value="2/2", quantity_unit=" remaining ")
    assert response.status_code == 201, response.text
    operation = response.json()["operation"]
    assert operation["quantity_value"] == "2/2" and operation["quantity_unit"] == "remaining"
    assert operation["affects_state"] == "ESTIMATED" and operation["calculation_method"] == "EXACT"
    with Session(c[0][2]) as session:
        actual = session.get(InventoryItem, item.id)
        assert actual.estimated_current_amount == 0 and actual.status == "IN_STOCK"
        assert actual.estimated_at > now and actual.version == 2
        assert actual.confirmed_current_amount == item.confirmed_current_amount
        assert actual.confirmed_at == item.confirmed_at and actual.initial_amount == item.initial_amount


def test_fraction_rounds_applied_change_once(inventory_context):
    c = inventory_context; item = seed_inventory(c, confirmed_current_amount=Decimal("1"))
    response = send(c, item, quantity_kind="FRACTION", quantity_value="1/3", quantity_unit="remaining")
    assert response.status_code == 201, response.text
    assert Decimal(response.json()["operation"]["applied_change_amount"]) == Decimal(".333")
    assert Decimal(response.json()["inventory"]["confirmed_current_amount"]) == Decimal(".667")


@pytest.mark.parametrize("value,kind,unit,code", [
    pytest.param("1.001", "AMOUNT", "g", "INSUFFICIENT_QUANTITY", marks=pytest.mark.ci),
    ("1/2", "FRACTION", "remaining", "QUANTITY_PRECISION_UNSUPPORTED"),
    ("1/3", "FRACTION", "remaining", "QUANTITY_TOO_SMALL"),
    ("1", "AMOUNT", "ml", "UNIT_NOT_CONVERTIBLE"),
])
def test_failed_consumption_is_atomic_and_does_not_reserve_key(inventory_context, value, kind, unit, code):
    c = inventory_context; item = seed_inventory(c, confirmed_current_amount=Decimal(".001"))
    response = send(c, item, quantity_value=value, quantity_kind=kind, quantity_unit=unit)
    assert response.status_code == 422 and response.json()["detail"]["code"] == code
    assert_unchanged(c, item)
    assert send(c, item, quantity_kind="FRACTION", quantity_value="1/1", quantity_unit="remaining").status_code == 201


@pytest.mark.parametrize("state", ["EMPTY", "DISCARDED", "ARCHIVED"])
def test_consumption_requires_in_stock(inventory_context, state):
    c = inventory_context; item = seed_inventory(c, status=state, confirmed_current_amount=Decimal("0") if state == "EMPTY" else Decimal("2.5"))
    response = send(c, item)
    assert response.status_code == 409 and response.json()["detail"]["code"] == "STATE_CONFLICT"
    assert_unchanged(c, item)


@pytest.mark.parametrize("version,expected,code", [(2, 1, "VERSION_CONFLICT"), (2147483647, 2147483647, "VERSION_LIMIT_REACHED")])
def test_consumption_version_checks(inventory_context, version, expected, code):
    c = inventory_context; item = seed_inventory(c, version=version)
    response = send(c, item, expected_version=expected)
    assert response.status_code == 409 and response.json()["detail"]["code"] == code
    assert_unchanged(c, item)


def test_archived_catalog_and_space_allow_consumption_of_existing_stock(inventory_context):
    c = inventory_context; item = seed_inventory(c)
    with Session(c[0][2]) as session:
        for model, row in [(StorageSpace, c[4]), (ItemCategory, c[3]), (ItemDefinition, c[5])]:
            session.execute(update(model).where(model.id == row.id).values(status="ARCHIVED"))
        session.commit()
    assert send(c, item).status_code == 201


@pytest.mark.parametrize("changes", [
    {"quantity_value": "2/4"},
    {"quantity_kind": "AMOUNT", "quantity_value": "1.25", "quantity_unit": "kg"},
    {"operation_type": "ADD", "quantity_kind": "AMOUNT", "quantity_value": "1.25", "quantity_unit": "kg"},
])
def test_same_key_requires_same_literal_operation(inventory_context, changes):
    c = inventory_context; item = seed_inventory(c)
    original = dict(quantity_kind="FRACTION", quantity_value="1/2", quantity_unit="remaining")
    assert send(c, item, **original).status_code == 201
    response = send(c, item, **(original | changes))
    assert response.status_code == 409 and response.json()["detail"]["code"] == "IDEMPOTENCY_CONFLICT"


def test_addition_key_cannot_be_reused_for_consumption(inventory_context):
    c = inventory_context; item = seed_inventory(c)
    assert add(c, item, key="shared").status_code == 201
    response = send(c, item, key="shared")
    assert response.status_code == 409 and response.json()["detail"]["code"] == "IDEMPOTENCY_CONFLICT"


def test_consumption_requires_authentication_and_ownership(inventory_context):
    c = inventory_context; item = seed_inventory(c)
    assert request(c[0], "POST", url(item), json=consumption(), headers={"Idempotency-Key": "x"}).status_code == 401
    foreign = seed_space(c[0], c[2].id, "Foreign")
    with Session(c[0][2]) as session:
        session.execute(update(InventoryItem).where(InventoryItem.id == item.id).values(storage_space_id=foreign.id))
        session.commit()
    assert send(c, item).status_code == 404
    assert_unchanged(c, item)
