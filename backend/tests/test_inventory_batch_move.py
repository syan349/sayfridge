"""B15 atomic inventory batch-move acceptance tests."""
from datetime import datetime, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, StorageSpace
from auth_test_support import request
from inventory_test_support import BASE, inventory_context, seed_inventory, seed_space

pytestmark = pytest.mark.postgres
BATCH_URL = BASE + "/batch-move"


def reference(item, expected_version=None):
    return {
        "id": str(item.id),
        "expected_version": item.version if expected_version is None else expected_version,
    }


@pytest.mark.ci
def test_batch_move_preserves_input_order_and_treats_current_target_as_noop(inventory_context):
    context = inventory_context
    target = seed_space(context[0], context[1].id, "Pantry")
    moved = seed_inventory(context, notes="move", version=3)
    already_there = seed_inventory(
        context,
        storage_space_id=target.id,
        notes="noop",
        status="EMPTY",
        version=7,
        confirmed_current_amount=Decimal("0"),
        confirmed_at=datetime.now(timezone.utc),
    )

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={
            "target_storage_space_id": str(target.id),
            "items": [reference(moved), reference(already_there)],
        },
        headers=context[-1],
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["count"] == 2
    assert [item["id"] for item in body["items"]] == [str(moved.id), str(already_there.id)]
    assert [item["storage_space_id"] for item in body["items"]] == [str(target.id)] * 2
    assert [item["storage_space_name"] for item in body["items"]] == ["Pantry"] * 2
    assert [item["version"] for item in body["items"]] == [4, 7]
    assert body["items"][0]["confirmed_current_amount"] == "2.500"
    assert body["items"][1]["status"] == "EMPTY"
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 0


@pytest.mark.parametrize(
    ("failure", "expected_status", "expected_code"),
    [
        ("missing", 404, "NOT_FOUND"),
        ("foreign", 404, "NOT_FOUND"),
        pytest.param("stale", 409, "VERSION_CONFLICT", marks=pytest.mark.ci),
        ("terminal", 409, "STATE_CONFLICT"),
    ],
)
def test_batch_move_rolls_back_first_item_when_later_item_fails(
    inventory_context,
    failure,
    expected_status,
    expected_code,
):
    context = inventory_context
    target = seed_space(context[0], context[1].id, "Target")
    first = seed_inventory(context, notes="first")
    second = seed_inventory(context, notes="second")
    second_reference = reference(second)
    if failure == "missing":
        second_reference["id"] = str(uuid.uuid4())
    elif failure == "foreign":
        foreign_space = seed_space(context[0], context[2].id, "Foreign")
        foreign_item = seed_inventory(context, storage_space_id=foreign_space.id)
        second_reference = reference(foreign_item)
    elif failure == "stale":
        second_reference["expected_version"] = 2
    else:
        with Session(context[0][2]) as session:
            session.execute(
                update(InventoryItem)
                .where(InventoryItem.id == second.id)
                .values(status="ARCHIVED")
            )
            session.commit()

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={
            "target_storage_space_id": str(target.id),
            "items": [reference(first), second_reference],
        },
        headers=context[-1],
    )

    assert response.status_code == expected_status, response.text
    assert response.json()["detail"]["code"] == expected_code
    assert response.json()["detail"]["item_index"] == 1
    with Session(context[0][2]) as session:
        unchanged = session.get(InventoryItem, first.id)
        assert unchanged.storage_space_id == context[4].id and unchanged.version == 1


@pytest.mark.ci
def test_batch_move_rejects_duplicate_ids_without_writes(inventory_context):
    context = inventory_context
    target = seed_space(context[0], context[1].id, "Target")
    item = seed_inventory(context)
    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={
            "target_storage_space_id": str(target.id),
            "items": [reference(item), reference(item)],
        },
        headers=context[-1],
    )
    assert response.status_code == 422, response.text
    assert response.json()["detail"]["code"] == "VALIDATION_ERROR"
    assert response.json()["detail"]["item_index"] == 1
    with Session(context[0][2]) as session:
        unchanged = session.get(InventoryItem, item.id)
        assert unchanged.storage_space_id == context[4].id and unchanged.version == 1


@pytest.mark.parametrize("failure", ["missing", "foreign", "archived"])
def test_batch_move_requires_an_owned_active_target(inventory_context, failure):
    context = inventory_context
    item = seed_inventory(context)
    if failure == "missing":
        target_id = uuid.uuid4()
        expected_status = 404
    elif failure == "foreign":
        target_id = seed_space(context[0], context[2].id, "Foreign target").id
        expected_status = 404
    else:
        target_id = seed_space(context[0], context[1].id, "Archived target", "ARCHIVED").id
        expected_status = 409

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"target_storage_space_id": str(target_id), "items": [reference(item)]},
        headers=context[-1],
    )
    assert response.status_code == expected_status, response.text
    assert "item_index" not in response.json()["detail"]
    with Session(context[0][2]) as session:
        unchanged = session.get(InventoryItem, item.id)
        assert unchanged.storage_space_id == context[4].id and unchanged.version == 1


@pytest.mark.parametrize(
    ("case", "expected_index"),
    [
        ("empty", None),
        ("too_many", None),
        ("invalid_second_version", 1),
        ("unknown_item_field", 0),
    ],
)
def test_batch_move_rejects_invalid_request_shapes(inventory_context, case, expected_index):
    context = inventory_context
    item = seed_inventory(context)
    valid = reference(item)
    if case == "empty":
        body = {"target_storage_space_id": str(context[4].id), "items": []}
    elif case == "too_many":
        body = {"target_storage_space_id": str(context[4].id), "items": [valid] * 101}
    elif case == "invalid_second_version":
        body = {
            "target_storage_space_id": str(context[4].id),
            "items": [valid, {"id": str(uuid.uuid4()), "expected_version": True}],
        }
    else:
        body = {
            "target_storage_space_id": str(context[4].id),
            "items": [{**valid, "status": "ARCHIVED"}],
        }
    response = request(context[0], "POST", BATCH_URL, json=body, headers=context[-1])
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["code"] == "VALIDATION_ERROR"
    if expected_index is None:
        assert "item_index" not in detail
    else:
        assert detail["item_index"] == expected_index


def test_batch_move_requires_authentication(inventory_context):
    item = seed_inventory(inventory_context)
    response = request(
        inventory_context[0],
        "POST",
        BATCH_URL,
        json={
            "target_storage_space_id": str(inventory_context[4].id),
            "items": [reference(item)],
        },
    )
    assert response.status_code == 401


def test_batch_move_allows_max_version_noop_but_rejects_real_move(inventory_context):
    context = inventory_context
    target = seed_space(context[0], context[1].id, "Target")
    noop = seed_inventory(context, storage_space_id=target.id, version=2147483647)
    blocked = seed_inventory(context, version=2147483647)

    no_op_response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"target_storage_space_id": str(target.id), "items": [reference(noop)]},
        headers=context[-1],
    )
    assert no_op_response.status_code == 200
    assert no_op_response.json()["items"][0]["version"] == 2147483647

    blocked_response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"target_storage_space_id": str(target.id), "items": [reference(blocked)]},
        headers=context[-1],
    )
    assert blocked_response.status_code == 409
    assert blocked_response.json()["detail"] == {
        "code": "VERSION_LIMIT_REACHED",
        "message": "Inventory version limit reached",
        "item_index": 0,
    }
