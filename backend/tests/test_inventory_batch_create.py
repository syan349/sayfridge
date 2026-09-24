"""B15 atomic inventory batch-creation acceptance tests."""
from copy import deepcopy
import uuid

import pytest
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, InventoryOperation, ItemDefinition, StorageSpace
from auth_test_support import request
from inventory_test_support import BASE, inventory_context, payload, seed_space

pytestmark = pytest.mark.postgres
BATCH_URL = BASE + "/batch-create"


@pytest.mark.ci
def test_batch_create_returns_input_order_and_allows_identical_stock(inventory_context):
    context = inventory_context
    second_space = seed_space(context[0], context[1].id, "Pantry")
    first = payload(context, amount="1.250", unit=" KG ", notes="first")
    second = payload(
        context,
        storage_space_id=str(second_space.id),
        amount="2",
        unit="each",
        notes="second",
    )
    duplicate = deepcopy(first)

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [first, second, duplicate]},
        headers=context[-1],
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["count"] == 3
    assert [item["notes"] for item in body["items"]] == ["first", "second", "first"]
    assert [item["storage_space_id"] for item in body["items"]] == [
        str(context[4].id),
        str(second_space.id),
        str(context[4].id),
    ]
    assert [item["initial_unit"] for item in body["items"]] == ["kg", "each", "kg"]
    assert all(item["version"] == 1 and item["status"] == "IN_STOCK" for item in body["items"])
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryItem)) == 3
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 0


@pytest.mark.parametrize(
    ("failure", "expected_status", "expected_code"),
    [
        pytest.param("missing_space", 404, "NOT_FOUND", marks=pytest.mark.ci),
        ("foreign_space", 404, "NOT_FOUND"),
        ("missing_definition", 404, "NOT_FOUND"),
        pytest.param("archived_definition", 409, "STATE_CONFLICT", marks=pytest.mark.ci),
    ],
)
def test_batch_create_rolls_back_every_item_and_reports_failing_index(
    inventory_context,
    failure,
    expected_status,
    expected_code,
):
    context = inventory_context
    first = payload(context, notes="must roll back")
    second = payload(context)
    with Session(context[0][2]) as session:
        if failure == "missing_space":
            second["storage_space_id"] = str(uuid.uuid4())
        elif failure == "foreign_space":
            foreign = StorageSpace(
                user_id=context[2].id,
                name="Foreign",
                type="FRIDGE",
                status="ACTIVE",
            )
            session.add(foreign)
            session.commit()
            second["storage_space_id"] = str(foreign.id)
        elif failure == "missing_definition":
            second["item_definition_id"] = str(uuid.uuid4())
        else:
            session.execute(
                update(ItemDefinition)
                .where(ItemDefinition.id == context[5].id)
                .values(status="ARCHIVED")
            )
            session.commit()

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [first, second]},
        headers=context[-1],
    )

    assert response.status_code == expected_status, response.text
    assert response.json()["detail"]["code"] == expected_code
    # A shared archived definition fails at its first occurrence; other failures belong to item 1.
    expected_index = 0 if failure == "archived_definition" else 1
    assert response.json()["detail"]["item_index"] == expected_index
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryItem)) == 0


@pytest.mark.parametrize(
    ("case", "expected_index"),
    [
        ("empty", None),
        ("too_many", None),
        ("invalid_second_item", 1),
        ("unknown_item_fields", 0),
    ],
)
def test_batch_create_rejects_invalid_request_shapes(inventory_context, case, expected_index):
    if case == "empty":
        body = {"items": []}
    elif case == "too_many":
        body = {"items": [payload(inventory_context)] * 101}
    elif case == "invalid_second_item":
        invalid = payload(inventory_context)
        invalid["amount"] = "0"
        body = {"items": [payload(inventory_context), invalid]}
    else:
        body = {"items": [{"unexpected": True}]}
    response = request(
        inventory_context[0],
        "POST",
        BATCH_URL,
        json=body,
        headers=inventory_context[-1],
    )
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["code"] == "VALIDATION_ERROR"
    if expected_index is None:
        assert "item_index" not in detail
    else:
        assert detail["item_index"] == expected_index
    with Session(inventory_context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryItem)) == 0


def test_batch_create_requires_authentication(inventory_context):
    response = request(
        inventory_context[0],
        "POST",
        BATCH_URL,
        json={"items": [payload(inventory_context)]},
    )
    assert response.status_code == 401


def test_batch_create_reports_first_input_error_instead_of_uuid_lock_order(inventory_context):
    context = inventory_context
    with Session(context[0][2]) as session:
        session.execute(
            update(StorageSpace)
            .where(StorageSpace.id == context[4].id)
            .values(status="ARCHIVED")
        )
        session.commit()
    later_missing = payload(context, storage_space_id=str(uuid.UUID(int=0)))

    response = request(
        context[0],
        "POST",
        BATCH_URL,
        json={"items": [payload(context), later_missing]},
        headers=context[-1],
    )

    assert response.status_code == 409, response.text
    assert response.json()["detail"]["code"] == "STATE_CONFLICT"
    assert response.json()["detail"]["item_index"] == 0
    with Session(context[0][2]) as session:
        assert session.scalar(select(func.count()).select_from(InventoryItem)) == 0
