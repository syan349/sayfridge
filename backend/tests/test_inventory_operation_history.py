"""Global inventory-operation list/detail filters, isolation, and contracts."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from urllib.parse import urlencode
import uuid

import pytest
from sqlalchemy.orm import Session

from app.db.models import InventoryOperation
from auth_test_support import request
from inventory_test_support import inventory_context, seed_inventory, seed_space

BASE = "/api/v1/inventory-operations"
pytestmark = pytest.mark.postgres


def seed_operation(
    context,
    item_id,
    *,
    operation_id=None,
    created_at=None,
    operation_type="ADD",
    status="SUCCESS",
):
    operation_id = operation_id or uuid.uuid4()
    created_at = created_at or datetime.now(timezone.utc)
    reconcile = operation_type == "RECONCILE"
    with Session(context[0][2], expire_on_commit=False) as session:
        operation = InventoryOperation(
            id=operation_id,
            inventory_item_id=item_id,
            operation_type=operation_type,
            affects_state="CONFIRMED",
            input_method="MANUAL",
            quantity_kind="AMOUNT",
            quantity_value="1.0",
            quantity_unit="kg",
            calculation_method="EXACT",
            applied_change_amount=None if reconcile else Decimal("1"),
            applied_change_unit=None if reconcile else "kg",
            status=status,
            idempotency_key=f"global-history:{operation_id}",
            created_at=created_at,
            undone_at=created_at if status == "UNDONE" else None,
        )
        session.add(operation)
        session.commit()
        return operation


def build_history(context):
    first_item = seed_inventory(context)
    second_item = seed_inventory(context)
    foreign_space = seed_space(context[0], context[2].id)
    foreign_item = seed_inventory(context, storage_space_id=foreign_space.id)
    first_time = datetime(2026, 9, 1, 10, tzinfo=timezone.utc)
    middle_time = first_time + timedelta(days=1)
    last_time = middle_time + timedelta(days=1)
    operations = [
        seed_operation(context, first_item.id, operation_id=uuid.UUID(int=1),
                       created_at=first_time),
        seed_operation(context, first_item.id, operation_id=uuid.UUID(int=2),
                       created_at=middle_time, operation_type="CONSUME", status="FAILED"),
        seed_operation(context, second_item.id, operation_id=uuid.UUID(int=3),
                       created_at=middle_time, operation_type="RECONCILE", status="UNDONE"),
        seed_operation(context, second_item.id, operation_id=uuid.UUID(int=4),
                       created_at=last_time, status="PENDING_CONFIRMATION"),
    ]
    foreign = seed_operation(
        context, foreign_item.id, operation_id=uuid.UUID(int=5),
        created_at=last_time + timedelta(days=1),
    )
    return first_item, second_item, foreign_item, operations, foreign, first_time, middle_time, last_time


@pytest.mark.ci
def test_global_history_lists_only_owned_operations_with_stable_pagination(inventory_context):
    context = inventory_context
    _, _, _, operations, _, _, _, _ = build_history(context)

    first = request(context[0], "GET", f"{BASE}?page_size=2", headers=context[-1])
    second = request(context[0], "GET", f"{BASE}?page=2&page_size=2", headers=context[-1])
    empty = request(context[0], "GET", f"{BASE}?page=99&page_size=2", headers=context[-1])

    assert first.status_code == second.status_code == empty.status_code == 200
    assert first.json()["total"] == second.json()["total"] == empty.json()["total"] == 4
    assert [row["id"] for row in first.json()["items"]] == [
        str(operations[3].id), str(operations[2].id),
    ]
    assert [row["id"] for row in second.json()["items"]] == [
        str(operations[1].id), str(operations[0].id),
    ]
    assert empty.json()["items"] == []
    assert all("idempotency_key" not in row for row in first.json()["items"])


def test_global_history_filters_inventory_type_status_and_half_open_time_range(inventory_context):
    context = inventory_context
    first_item, _, _, operations, _, first_time, middle_time, last_time = build_history(context)

    queries = {
        "item": ({"inventory_item_id": first_item.id}, [operations[1].id, operations[0].id]),
        "type": ({"operation_type": "RECONCILE"}, [operations[2].id]),
        "status": ({"status": "FAILED"}, [operations[1].id]),
        "from": ({"created_from": middle_time.isoformat()},
                 [operations[3].id, operations[2].id, operations[1].id]),
        "to": ({"created_to": middle_time.isoformat()}, [operations[0].id]),
        "range": ({"created_from": middle_time.isoformat(), "created_to": last_time.isoformat()},
                  [operations[2].id, operations[1].id]),
    }
    for parameters, expected in queries.values():
        response = request(
            context[0], "GET", f"{BASE}?{urlencode(parameters)}", headers=context[-1]
        )
        assert response.status_code == 200, response.text
        assert response.json()["total"] == len(expected)
        assert [row["id"] for row in response.json()["items"]] == [str(value) for value in expected]

    inclusive = request(
        context[0], "GET",
        f"{BASE}?{urlencode({'created_from': first_time.isoformat(), 'created_to': middle_time.isoformat()})}",
        headers=context[-1],
    )
    assert [row["id"] for row in inclusive.json()["items"]] == [str(operations[0].id)]


@pytest.mark.ci
def test_global_history_foreign_inventory_filter_returns_empty_page(inventory_context):
    context = inventory_context
    _, _, foreign_item, _, _, _, _, _ = build_history(context)
    response = request(
        context[0], "GET", f"{BASE}?inventory_item_id={foreign_item.id}", headers=context[-1]
    )
    assert response.status_code == 200
    assert response.json()["items"] == [] and response.json()["total"] == 0


def test_operation_detail_returns_owned_record_including_historical_state(inventory_context):
    context = inventory_context
    item = seed_inventory(context, status="ARCHIVED")
    operation = seed_operation(
        context, item.id, operation_type="RECONCILE", status="UNDONE"
    )

    response = request(context[0], "GET", f"{BASE}/{operation.id}", headers=context[-1])

    assert response.status_code == 200
    assert response.json()["id"] == str(operation.id)
    assert response.json()["inventory_item_id"] == str(item.id)
    assert response.json()["status"] == "UNDONE"
    assert "idempotency_key" not in response.json()


@pytest.mark.ci
def test_operation_detail_hides_foreign_and_missing_records(inventory_context):
    context = inventory_context
    foreign_space = seed_space(context[0], context[2].id)
    foreign_item = seed_inventory(context, storage_space_id=foreign_space.id)
    foreign = seed_operation(context, foreign_item.id)

    responses = [
        request(context[0], "GET", f"{BASE}/{operation_id}", headers=context[-1])
        for operation_id in (foreign.id, uuid.uuid4())
    ]

    assert all(response.status_code == 404 for response in responses)
    assert responses[0].json() == responses[1].json()


@pytest.mark.parametrize("path", ["", "/" + str(uuid.uuid4())])
def test_global_history_endpoints_require_authentication(inventory_context, path):
    assert request(inventory_context[0], "GET", BASE + path).status_code == 401


@pytest.mark.parametrize(
    "query",
    [
        "page=0", "page_size=101", "inventory_item_id=bad",
        "operation_type=REMOVE", "status=UNKNOWN",
        "created_from=2026-09-02T00%3A00%3A00Z&created_to=2026-09-02T00%3A00%3A00Z",
        "created_from=2026-09-03T00%3A00%3A00Z&created_to=2026-09-02T00%3A00%3A00Z",
        "created_from=2026-09-02T00%3A00%3A00", "unknown=1",
    ],
)
def test_global_history_rejects_invalid_queries(inventory_context, query):
    response = request(inventory_context[0], "GET", f"{BASE}?{query}", headers=inventory_context[-1])
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "VALIDATION_ERROR"


def test_operation_detail_rejects_invalid_uuid(inventory_context):
    response = request(
        inventory_context[0], "GET", f"{BASE}/not-a-uuid", headers=inventory_context[-1]
    )
    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "VALIDATION_ERROR"
