"""Item-scoped inventory operation history contracts and ownership checks."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy.orm import Session

from app.db.models import InventoryOperation
from auth_test_support import request
from inventory_test_support import BASE, inventory_context, seed_inventory, seed_space

pytestmark = pytest.mark.postgres


def seed_operation(context, item_id, *, operation_id, created_at, status="SUCCESS"):
    with Session(context[0][2], expire_on_commit=False) as session:
        operation = InventoryOperation(
            id=operation_id,
            inventory_item_id=item_id,
            operation_type="ADD",
            affects_state="CONFIRMED",
            input_method="MANUAL",
            quantity_kind="AMOUNT",
            quantity_value="1.0",
            quantity_unit="kg",
            calculation_method="EXACT",
            applied_change_amount=Decimal("1"),
            applied_change_unit="kg",
            status=status,
            idempotency_key=f"history:{operation_id}",
            created_at=created_at,
            undone_at=created_at if status == "UNDONE" else None,
        )
        session.add(operation)
        session.commit()
        return operation


@pytest.mark.ci
def test_item_history_returns_all_states_newest_first_and_hides_internal_key(inventory_context):
    context = inventory_context
    item = seed_inventory(context)
    earlier = datetime(2026, 9, 1, tzinfo=timezone.utc)
    later = earlier + timedelta(days=1)
    operations = [
        seed_operation(context, item.id, operation_id=uuid.UUID(int=4), created_at=earlier,
                       status="PENDING_CONFIRMATION"),
        seed_operation(context, item.id, operation_id=uuid.UUID(int=1), created_at=later),
        seed_operation(context, item.id, operation_id=uuid.UUID(int=2), created_at=later,
                       status="FAILED"),
        seed_operation(context, item.id, operation_id=uuid.UUID(int=3), created_at=later,
                       status="UNDONE"),
    ]

    response = request(context[0], "GET", f"{BASE}/{item.id}/operations", headers=context[-1])

    assert response.status_code == 200, response.text
    body = response.json()
    assert [row["id"] for row in body] == [
        str(operations[3].id), str(operations[2].id),
        str(operations[1].id), str(operations[0].id),
    ]
    assert [row["status"] for row in body] == [
        "UNDONE", "FAILED", "SUCCESS", "PENDING_CONFIRMATION",
    ]
    assert all(row["inventory_item_id"] == str(item.id) for row in body)
    assert all("idempotency_key" not in row for row in body)


def test_item_history_returns_empty_list_when_no_operations_exist(inventory_context):
    context = inventory_context
    item = seed_inventory(context)

    response = request(context[0], "GET", f"{BASE}/{item.id}/operations", headers=context[-1])

    assert response.status_code == 200
    assert response.json() == []


@pytest.mark.parametrize("state", ["DISCARDED", "ARCHIVED"])
def test_item_history_remains_visible_for_terminal_inventory(inventory_context, state):
    context = inventory_context
    item = seed_inventory(context, status=state)
    operation = seed_operation(
        context, item.id, operation_id=uuid.uuid4(), created_at=datetime.now(timezone.utc)
    )

    response = request(context[0], "GET", f"{BASE}/{item.id}/operations", headers=context[-1])

    assert response.status_code == 200
    assert [row["id"] for row in response.json()] == [str(operation.id)]


def test_item_history_hides_foreign_and_missing_inventory(inventory_context):
    context = inventory_context
    foreign_space = seed_space(context[0], context[2].id)
    foreign = seed_inventory(context, storage_space_id=foreign_space.id)
    seed_operation(
        context, foreign.id, operation_id=uuid.uuid4(), created_at=datetime.now(timezone.utc)
    )

    responses = [
        request(context[0], "GET", f"{BASE}/{item_id}/operations", headers=context[-1])
        for item_id in (foreign.id, uuid.uuid4())
    ]

    assert all(response.status_code == 404 for response in responses)
    assert responses[0].json() == responses[1].json()


def test_item_history_requires_authentication(inventory_context):
    item = seed_inventory(inventory_context)
    response = request(inventory_context[0], "GET", f"{BASE}/{item.id}/operations")
    assert response.status_code == 401


def test_item_history_rejects_invalid_inventory_uuid(inventory_context):
    response = request(
        inventory_context[0], "GET", f"{BASE}/not-a-uuid/operations",
        headers=inventory_context[-1],
    )
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "VALIDATION_ERROR"
