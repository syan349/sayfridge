"""Measured detail edits must preserve provenance and commit atomically."""
from datetime import datetime, timezone
from decimal import Decimal
from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, ItemDefinition
from app.schemas.inventory import InventoryUpdate
from app.services.inventory import InventoryError, _edit_quantity
from auth_test_support import request
from inventory_test_support import BASE, inventory_context, seed_inventory


@pytest.mark.parametrize("quantity", [
    {"mode": "ESTIMATED", "amount": "4"},
    {"mode": "ESTIMATED", "unit": "kg"},
    {"mode": "EXACT", "amount": "-1", "unit": "kg"},
    {"mode": "EXACT", "amount": "1.0001", "unit": "kg"},
    {"mode": "EXACT", "amount": "0" * 33, "unit": "kg"},
    {"mode": "EXACT", "amount": "1"},
    {"mode": "EXACT", "amount": "1", "unit": " "},
])
def test_detail_edit_rejects_fabricated_estimates_and_invalid_measurements(quantity):
    with pytest.raises(ValidationError):
        InventoryUpdate(expected_version=1, quantity=quantity)


def test_free_text_units_and_zero_measurements_are_supported():
    edit = InventoryUpdate(expected_version=1, item_name=" My rice ",
                           quantity={"mode": "EXACT", "amount": "0.0", "unit": " Scoops "})
    assert edit.item_name == "My rice"
    assert edit.quantity.unit == "scoops"


def batch(**overrides):
    values = dict(id=uuid4(), status="IN_STOCK", initial_amount=Decimal("5"), initial_unit="kg",
                  confirmed_current_amount=Decimal("3"), confirmed_current_unit="kg",
                  estimated_current_amount=Decimal("2"), estimated_current_unit="kg",
                  estimated_at=datetime.now(timezone.utc))
    values.update(overrides)
    return SimpleNamespace(**values)


def test_measured_edit_clears_estimate_and_records_reconciliation():
    item = batch()
    operation = _edit_quantity(item, {"mode": "EXACT", "amount": "1.75", "unit": "scoops"}, None)
    assert item.confirmed_current_amount == Decimal("1.75")
    assert item.confirmed_current_unit == "scoops"
    assert item.estimated_current_amount is item.estimated_current_unit is item.estimated_at is None
    assert (item.initial_amount, item.initial_unit) == (Decimal("5"), "kg")
    assert operation.operation_type == "RECONCILE"
    assert operation.calculation_method == "EXACT"
    assert operation.input_method == "MANUAL"
    assert operation.affects_state == "CONFIRMED"


def test_estimate_mode_preserves_the_existing_estimate():
    item = batch()
    timestamp = item.estimated_at
    assert _edit_quantity(item, {"mode": "ESTIMATED"}, None) is None
    assert item.estimated_current_amount == Decimal("2")
    assert item.estimated_at == timestamp
    assert item.confirmed_current_amount == Decimal("3")


def test_switching_to_estimate_freezes_the_confirmed_quantity():
    item = batch(estimated_current_amount=None, estimated_current_unit=None, estimated_at=None)
    assert _edit_quantity(item, {"mode": "ESTIMATED"}, None) is None
    assert (item.estimated_current_amount, item.estimated_current_unit) == (Decimal("3"), "kg")
    assert item.confirmed_current_amount == Decimal("3")


def test_empty_batches_require_a_measurement_and_an_active_space_to_restock():
    item = batch(status="EMPTY", confirmed_current_amount=Decimal("0"), estimated_current_amount=None)
    with pytest.raises(InventoryError):
        _edit_quantity(item, {"mode": "ESTIMATED"}, None)
    with pytest.raises(InventoryError):
        _edit_quantity(item, {"mode": "EXACT", "amount": "2", "unit": "kg"}, SimpleNamespace(status="ARCHIVED"))
    assert item.confirmed_current_amount == 0


@pytest.mark.postgres
def test_name_and_measured_balance_save_atomically_without_renaming_other_batches(inventory_context):
    context = inventory_context
    item, sibling = seed_inventory(context), seed_inventory(context)
    response = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1], json={
        "expected_version": 1, "item_name": "My rice", "notes": "Measured today",
        "quantity": {"mode": "EXACT", "amount": "1.75", "unit": "Scoops"},
    })
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["version"] == 2
    assert result["item_definition_name"] == "My rice"
    assert Decimal(result["display_amount"]) == Decimal("1.75")
    assert result["display_unit"] == "scoops"
    assert result["created_at"] == item.created_at.isoformat().replace("+00:00", "Z")
    with Session(context[0][2]) as session:
        assert session.get(InventoryItem, sibling.id).item_definition_id == context[5].id
        assert session.get(ItemDefinition, context[5].id).name != "My rice"
        operations = session.scalars(select(InventoryOperation).where(InventoryOperation.inventory_item_id == item.id)).all()
        assert len(operations) == 1 and operations[0].operation_type == "RECONCILE"
    stale = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1], json={
        "expected_version": 1, "item_name": "Stale name", "quantity": {"mode": "EXACT", "amount": "9", "unit": "kg"},
    })
    assert stale.status_code == 409


@pytest.mark.postgres
def test_rejected_restock_rolls_back_the_new_name_and_notes(inventory_context):
    from sqlalchemy import update
    from app.db.models import StorageSpace
    context = inventory_context
    item = seed_inventory(context, status="EMPTY", confirmed_current_amount=Decimal("0"))
    with Session(context[0][2]) as session:
        session.execute(update(StorageSpace).where(StorageSpace.id == context[4].id).values(status="ARCHIVED"))
        session.commit()
    response = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1], json={
        "expected_version": 1, "item_name": "Rollback name", "notes": "Do not save",
        "quantity": {"mode": "EXACT", "amount": "1", "unit": "kg"},
    })
    assert response.status_code == 409
    with Session(context[0][2]) as session:
        stored = session.get(InventoryItem, item.id)
        assert stored.version == 1 and stored.notes is None
        assert stored.item_definition_id == context[5].id
        assert not session.scalars(select(ItemDefinition).where(ItemDefinition.name == "Rollback name")).all()
