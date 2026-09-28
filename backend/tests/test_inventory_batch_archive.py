"""B15 atomic inventory batch-archive acceptance tests."""
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
BATCH_URL = BASE + "/batch-archive"


def reference(item, expected_version=None):
    return {
        "id": str(item.id),
        "expected_version": item.version if expected_version is None else expected_version,
    }


@pytest.mark.ci
def test_batch_archive_preserves_input_order_facts_and_history(inventory_context):
    context = inventory_context
    estimated_at = datetime.now(timezone.utc)
    first = seed_inventory(
        context,
        notes="estimated",
        version=3,
        estimated_current_amount=Decimal("1.250"),
        estimated_current_unit="kg",
        estimated_at=estimated_at,
    )
    second = seed_inventory(
        context,
        notes="empty",
        status="EMPTY",
        version=8,
        confirmed_current_amount=Decimal("0"),
    )
    with Session(context[0][2]) as session:
        session.execute(
            update(StorageSpace)
            .where(StorageSpace.id == context[4].id)
            .values(status="ARCHIVED")
        )
        session.commit()

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [reference(first), reference(second)]},
        headers=context[-1],
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["count"] == 2
    assert [item["id"] for item in body["items"]] == [str(first.id), str(second.id)]
    assert [item["status"] for item in body["items"]] == ["ARCHIVED", "ARCHIVED"]
    assert [item["version"] for item in body["items"]] == [4, 9]
    assert body["items"][0]["estimated_current_amount"] == "1.250"
    assert body["items"][0]["estimated_at"] == estimated_at.isoformat().replace("+00:00", "Z")
    assert body["items"][1]["confirmed_current_amount"] == "0.000"
    assert [item["notes"] for item in body["items"]] == ["estimated", "empty"]
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 0


@pytest.mark.parametrize(
    ("failure", "expected_status", "expected_code"),
    [
        ("missing", 404, "NOT_FOUND"),
        ("foreign", 404, "NOT_FOUND"),
        pytest.param(
            "stale",
            409,
            "VERSION_CONFLICT",
            marks=[pytest.mark.ci, pytest.mark.database_acceptance],
        ),
        ("discarded", 409, "STATE_CONFLICT"),
        ("archived", 409, "STATE_CONFLICT"),
    ],
)
def test_batch_archive_rolls_back_first_item_when_later_item_fails(
    inventory_context,
    failure,
    expected_status,
    expected_code,
):
    context = inventory_context
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
                .values(status=failure.upper())
            )
            session.commit()

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [reference(first), second_reference]},
        headers=context[-1],
    )

    assert response.status_code == expected_status, response.text
    assert response.json()["detail"]["code"] == expected_code
    assert response.json()["detail"]["item_index"] == 1
    with Session(context[0][2]) as session:
        unchanged = session.get(InventoryItem, first.id)
        assert unchanged.status == "IN_STOCK" and unchanged.version == 1


@pytest.mark.ci
def test_batch_archive_rejects_duplicate_ids_without_writes(inventory_context):
    context = inventory_context
    item = seed_inventory(context)
    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [reference(item), reference(item)]},
        headers=context[-1],
    )
    assert response.status_code == 422, response.text
    assert response.json()["detail"]["code"] == "VALIDATION_ERROR"
    assert response.json()["detail"]["item_index"] == 1
    with Session(context[0][2]) as session:
        unchanged = session.get(InventoryItem, item.id)
        assert unchanged.status == "IN_STOCK" and unchanged.version == 1


@pytest.mark.parametrize(
    ("case", "expected_index"),
    [
        ("empty", None),
        ("too_many", None),
        ("invalid_second_version", 1),
        ("unknown_item_field", 0),
    ],
)
def test_batch_archive_rejects_invalid_request_shapes(inventory_context, case, expected_index):
    context = inventory_context
    item = seed_inventory(context)
    valid = reference(item)
    if case == "empty":
        body = {"items": []}
    elif case == "too_many":
        body = {"items": [valid] * 101}
    elif case == "invalid_second_version":
        body = {"items": [valid, {"id": str(uuid.uuid4()), "expected_version": 0}]}
    else:
        body = {"items": [{**valid, "status": "ARCHIVED"}]}
    response = request(context[0], "POST", BATCH_URL, json=body, headers=context[-1])
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["code"] == "VALIDATION_ERROR"
    if expected_index is None:
        assert "item_index" not in detail
    else:
        assert detail["item_index"] == expected_index


def test_batch_archive_requires_authentication(inventory_context):
    item = seed_inventory(inventory_context)
    response = request(
        inventory_context[0],
        "POST",
        BATCH_URL,
        json={"items": [reference(item)]},
    )
    assert response.status_code == 401


def test_batch_archive_rejects_version_limit_without_changes(inventory_context):
    context = inventory_context
    item = seed_inventory(context, version=2147483647)
    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [reference(item)]},
        headers=context[-1],
    )
    assert response.status_code == 409
    assert response.json()["detail"] == {
        "code": "VERSION_LIMIT_REACHED",
        "message": "Inventory version limit reached",
        "item_index": 0,
    }
    with Session(context[0][2]) as session:
        unchanged = session.get(InventoryItem, item.id)
        assert unchanged.status == "IN_STOCK" and unchanged.version == 2147483647
