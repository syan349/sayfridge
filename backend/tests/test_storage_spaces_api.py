"""B04 API contracts against real PostgreSQL, including isolation and rollback."""
import asyncio
from datetime import datetime, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from auth_test_support import session_token
from app.db.models import InventoryItem, ItemCategory, ItemDefinition, StorageSpace
from auth_test_support import exercise, make_user, request, seed_users

pytestmark = pytest.mark.postgres
BASE = "/api/v1/storage-spaces"
PUBLIC_FIELDS = {"is_default", "id", "name", "type", "status", "created_at", "updated_at"}


@pytest.fixture
def space_context(database):
    owner = make_user(email="space-owner@example.com")
    other = make_user(email="space-other@example.com")
    seed_users(database, owner, other)
    token = session_token(database, owner.id)
    return database, owner, other, {"Authorization": f"Bearer {token}"}


def seed_space(database, user_id, *, name="Kitchen", status="ACTIVE", space_id=None):
    with Session(database[2], expire_on_commit=False) as session:
        space = StorageSpace(id=space_id or uuid.uuid4(), user_id=user_id, name=name, type="FRIDGE", status=status)
        session.add(space)
        session.commit()
        return space


def read_space(database, space_id):
    with Session(database[2]) as session:
        return session.get(StorageSpace, space_id)


def seed_inventory(database, space_id, *, status="IN_STOCK"):
    with Session(database[2], expire_on_commit=False) as session:
        category = ItemCategory(name="Food", normalized_name="food")
        session.add(category)
        session.flush()
        definition = ItemDefinition(name="Rice", normalized_name="rice", category_id=category.id)
        session.add(definition)
        session.flush()
        item = InventoryItem(
            storage_space_id=space_id, item_definition_id=definition.id,
            status=status, initial_amount=Decimal("1"), initial_unit="kg",
            confirmed_current_amount=Decimal("1") if status == "IN_STOCK" else Decimal("0"),
            confirmed_current_unit="kg", confirmed_at=datetime.now(timezone.utc),
        )
        session.add(item)
        session.commit()
        return item


@pytest.mark.parametrize("space_type", [pytest.param("FRIDGE", marks=pytest.mark.ci), "FREEZER", "PANTRY", "WAREHOUSE", "OTHER"])
def test_create_trims_name_sets_owner_and_returns_public_fields(space_context, space_type):
    """All allowed types persist; ownership/state are server supplied, not public fields."""
    db, owner, _, headers = space_context
    response = request(db, "POST", BASE, json={"name": "  Kitchen  ", "type": space_type}, headers=headers)
    assert response.status_code == 201
    body = response.json()
    assert set(body) == PUBLIC_FIELDS
    assert body["name"] == "Kitchen" and body["type"] == space_type and body["status"] == "ACTIVE"
    assert datetime.fromisoformat(body["created_at"]).tzinfo is not None
    assert datetime.fromisoformat(body["updated_at"]).tzinfo is not None
    stored = read_space(db, uuid.UUID(body["id"]))
    assert stored.user_id == owner.id and stored.name == "Kitchen"


@pytest.mark.parametrize("payload", [
    {}, {"type": "FRIDGE"}, {"name": "Kitchen"},
    {"name": "", "type": "FRIDGE"}, {"name": "   ", "type": "FRIDGE"},
    {"name": "x" * 101, "type": "FRIDGE"}, {"name": None, "type": "FRIDGE"},
    {"name": 123, "type": "FRIDGE"}, {"name": "Kitchen", "type": "fridge"},
    {"name": "Kitchen", "type": None},
    pytest.param({"name": "Kitchen", "type": "FRIDGE", "user_id": str(uuid.uuid4())},
                 id="reject_client_owner"),
    {"name": "Kitchen", "type": "FRIDGE", "status": "ARCHIVED"},
    {"name": "Kitchen", "type": "FRIDGE", "id": str(uuid.uuid4())},
    {"name": "Kitchen", "type": "FRIDGE", "password": "must-not-echo"},
])
def test_invalid_create_returns_safe_422_without_writes(space_context, payload):
    """Reject missing, invalid and server-owned fields without exposing raw input."""
    db, _, _, headers = space_context
    response = request(db, "POST", BASE, json=payload, headers=headers)
    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["code"] == "VALIDATION_ERROR"
    assert all(set(error) == {"loc", "msg"} for error in detail["errors"])
    assert "must-not-echo" not in response.text
    with Session(db[2]) as session:
        assert session.scalars(select(StorageSpace)).all() == []


def test_trimmed_name_boundary_and_duplicate_scope(space_context):
    """Length applies after trimming; active-name uniqueness is case insensitive per owner."""
    db, owner, other, headers = space_context
    seed_space(db, other.id, name="Kitchen")
    seed_space(db, owner.id, name="Kitchen", status="ARCHIVED")
    created = request(db, "POST", BASE, json={"name": "Kitchen", "type": "FRIDGE"}, headers=headers)
    assert created.status_code == 201
    duplicate = request(db, "POST", BASE, json={"name": " kitchen ", "type": "FRIDGE"}, headers=headers)
    assert duplicate.status_code == 409 and duplicate.json()["detail"]["code"] == "NAME_CONFLICT"
    boundary = request(db, "POST", BASE, json={"name": "  " + "x" * 100 + "  ", "type": "OTHER"}, headers=headers)
    assert boundary.status_code == 201 and len(boundary.json()["name"]) == 100


@pytest.mark.parametrize("state", ["ACTIVE", pytest.param("ARCHIVED")])
def test_detail_returns_owned_space_in_either_state(space_context, state):
    db, owner, _, headers = space_context
    space = seed_space(db, owner.id, status=state)
    response = request(db, "GET", f"{BASE}/{space.id}", headers=headers)
    assert response.status_code == 200 and response.json()["status"] == state
    assert set(response.json()) == PUBLIC_FIELDS


@pytest.mark.parametrize("method,suffix,payload", [
    ("GET", "", None), ("PATCH", "", {"name": "Changed"}),
    ("POST", "/archive", None), ("POST", "/restore", None),
])
def test_missing_and_other_owners_resources_have_identical_404(space_context, method, suffix, payload):
    """Resource IDs alone never authorize reads or writes."""
    db, _, other, headers = space_context
    foreign = seed_space(db, other.id)
    responses = [request(db, method, f"{BASE}/{sid}{suffix}", json=payload, headers=headers)
                 for sid in [foreign.id, uuid.uuid4()]]
    assert all(r.status_code == 404 for r in responses)
    assert responses[0].json() == responses[1].json() == {
        "detail": {"code": "NOT_FOUND", "message": "Storage space not found"}}
    assert read_space(db, foreign.id).name == "Kitchen"
    assert read_space(db, foreign.id).status == "ACTIVE"


@pytest.mark.parametrize("method,path,payload", [
    ("GET", "", None), ("GET", "/{id}", None),
    pytest.param("POST", "", {"name": "Kitchen", "type": "FRIDGE"},
                 id="create_requires_authentication"),
    ("PATCH", "/{id}", {"name": "Changed"}),
    ("POST", "/{id}/archive", None), ("POST", "/{id}/restore", None),
])
def test_every_endpoint_requires_authentication(space_context, method, path, payload):
    db, owner, _, _ = space_context
    space = seed_space(db, owner.id)
    response = request(db, method, BASE + path.format(id=space.id), json=payload)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("account_status", ["SUSPENDED", "DISABLED"])
def test_current_account_state_is_checked_for_business_requests(space_context, account_status):
    db, owner, _, headers = space_context
    with Session(db[2]) as session:
        from app.db.models import User
        session.get(User, owner.id).status = account_status
        session.commit()
    assert request(db, "GET", BASE, headers=headers).status_code == 401
    assert request(db, "POST", BASE, json={"name": "Kitchen", "type": "FRIDGE"}, headers=headers).status_code == 401


def test_list_filters_ownership_state_and_orders_pages_including_empty_pages(space_context):
    """Stable name/UUID ordering and total survive pagination beyond the last row."""
    db, owner, other, headers = space_context
    seed_space(db, other.id, name="A foreign space")
    z = seed_space(db, owner.id, name="Zebra")
    a = seed_space(db, owner.id, name="Alpha")
    archived = [seed_space(db, owner.id, name="Old", status="ARCHIVED", space_id=uuid.UUID(int=i)) for i in [2, 1]]
    default = request(db, "GET", BASE, headers=headers).json()
    assert default["total"] == 2 and default["page"] == 1 and default["page_size"] == 20
    assert [x["id"] for x in default["items"]] == [str(a.id), str(z.id)]
    old = request(db, "GET", BASE + "?status=ARCHIVED", headers=headers).json()
    assert old["total"] == 2 and [x["id"] for x in old["items"]] == [str(s.id) for s in reversed(archived)]
    page = request(db, "GET", BASE + "?status=ALL&page=2&page_size=2", headers=headers).json()
    assert page["total"] == 4 and page["page"] == 2 and page["page_size"] == 2
    assert [x["id"] for x in page["items"]] == [str(archived[0].id), str(z.id)]
    for page_number in [99, 10**30]:
        empty = request(db, "GET", BASE + f"?status=ALL&page={page_number}&page_size=2", headers=headers)
        assert empty.status_code == 200 and empty.json()["items"] == [] and empty.json()["total"] == 4


def test_empty_list_has_zero_total(space_context):
    db, _, _, headers = space_context
    response = request(db, "GET", BASE, headers=headers)
    assert response.json() == {"items": [], "total": 0, "page": 1, "page_size": 20}


@pytest.mark.parametrize("query", ["page=0", "page=-1", "page=abc", "page_size=0", "page_size=101", "status=bad", "user_id=other"])
def test_invalid_list_query_returns_business_422(space_context, query):
    db, _, _, headers = space_context
    response = request(db, "GET", BASE + "?" + query, headers=headers)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "VALIDATION_ERROR"


def test_invalid_uuid_and_malformed_json_return_safe_business_errors(space_context):
    db, _, _, headers = space_context
    invalid = request(db, "GET", BASE + "/not-a-uuid", headers=headers)
    assert invalid.status_code == 422 and invalid.json()["detail"]["code"] == "VALIDATION_ERROR"
    async def scenario(client, sessions):
        response = await client.post(BASE, content='{"name": "do-not-echo",', headers={**headers, "Content-Type": "application/json"})
        assert response.status_code == 422
        assert response.json()["detail"]["code"] == "VALIDATION_ERROR" and "do-not-echo" not in response.text
    asyncio.run(exercise(db, scenario))


@pytest.mark.parametrize("payload", [{}, pytest.param({"name": None}, id="reject_null_name"), {"type": None}, {"name": " "}, {"name": "x" * 101}, {"type": "BAD"}, {"status": "ARCHIVED"}, {"user_id": str(uuid.uuid4())}])
def test_patch_rejects_empty_null_invalid_or_extra_fields(space_context, payload):
    db, owner, _, headers = space_context
    space = seed_space(db, owner.id)
    response = request(db, "PATCH", f"{BASE}/{space.id}", json=payload, headers=headers)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "VALIDATION_ERROR"
    stored = read_space(db, space.id)
    assert stored.name == space.name and stored.updated_at == space.updated_at


def test_patch_partial_fields_noop_and_conflict_rollback(space_context):
    db, owner, _, headers = space_context
    space = seed_space(db, owner.id)
    seed_space(db, owner.id, name="Taken")
    url = f"{BASE}/{space.id}"
    changed = request(db, "PATCH", url, json={"name": "  Changed  "}, headers=headers)
    assert changed.status_code == 200 and changed.json()["name"] == "Changed" and changed.json()["type"] == "FRIDGE"
    assert changed.json()["updated_at"] != space.updated_at.isoformat().replace("+00:00", "Z")
    noop = request(db, "PATCH", url, json={"name": " Changed ", "type": "FRIDGE"}, headers=headers)
    assert noop.json() == changed.json()
    conflict = request(db, "PATCH", url, json={"name": "TAKEN", "type": "FREEZER"}, headers=headers)
    assert conflict.status_code == 409 and conflict.json()["detail"]["code"] == "NAME_CONFLICT"
    stored = read_space(db, space.id)
    assert stored.name == "Changed" and stored.type == "FRIDGE"
    assert stored.updated_at == datetime.fromisoformat(changed.json()["updated_at"])
    changed_type = request(db, "PATCH", url, json={"type": "PANTRY"}, headers=headers)
    assert changed_type.status_code == 200 and changed_type.json()["name"] == "Changed" and changed_type.json()["type"] == "PANTRY"


def test_archive_restore_retries_and_archived_patch(space_context):
    db, owner, _, headers = space_context
    space = seed_space(db, owner.id)
    url = f"{BASE}/{space.id}"
    active_noop = request(db, "POST", url + "/restore", headers=headers)
    assert datetime.fromisoformat(active_noop.json()["updated_at"]) == space.updated_at
    archived = request(db, "POST", url + "/archive", headers=headers)
    assert archived.status_code == 200 and archived.json()["status"] == "ARCHIVED"
    retry = request(db, "POST", url + "/archive", headers=headers)
    assert retry.json() == archived.json()
    patch = request(db, "PATCH", url, json={"name": "Changed"}, headers=headers)
    assert patch.status_code == 409 and patch.json()["detail"]["code"] == "STATE_CONFLICT"
    assert read_space(db, space.id).name == "Kitchen"
    restored = request(db, "POST", url + "/restore", headers=headers)
    assert restored.status_code == 200 and restored.json()["status"] == "ACTIVE"
    assert request(db, "POST", url + "/restore", headers=headers).json() == restored.json()


def test_restore_conflicting_active_name_rolls_back(space_context):
    db, owner, _, headers = space_context
    archived = seed_space(db, owner.id, status="ARCHIVED")
    seed_space(db, owner.id, name="KITCHEN")
    response = request(db, "POST", f"{BASE}/{archived.id}/restore", headers=headers)
    assert response.status_code == 409 and response.json()["detail"]["code"] == "NAME_CONFLICT"
    stored = read_space(db, archived.id)
    assert stored.status == "ARCHIVED" and stored.updated_at == archived.updated_at


@pytest.mark.parametrize("inventory_status", [pytest.param("IN_STOCK", marks=pytest.mark.ci), "EMPTY", "DISCARDED", "ARCHIVED"])
def test_archive_checks_inventory_status_without_modifying_items(space_context, inventory_status):
    """Only IN_STOCK blocks archival; inventory data and versions stay unchanged."""
    db, owner, _, headers = space_context
    space = seed_space(db, owner.id)
    item = seed_inventory(db, space.id, status=inventory_status)
    response = request(db, "POST", f"{BASE}/{space.id}/archive", headers=headers)
    assert response.status_code == (409 if inventory_status == "IN_STOCK" else 200)
    assert read_space(db, space.id).status == ("ACTIVE" if inventory_status == "IN_STOCK" else "ARCHIVED")
    with Session(db[2]) as session:
        stored = session.get(InventoryItem, item.id)
        assert stored.status == item.status and stored.version == item.version
        assert stored.confirmed_current_amount == item.confirmed_current_amount
    if inventory_status == "IN_STOCK":
        assert response.json()["detail"]["code"] == "STATE_CONFLICT"
        assert read_space(db, space.id).updated_at == space.updated_at


@pytest.mark.parametrize("action", ["archive", "restore"])
def test_state_actions_reject_request_bodies(space_context, action):
    db, owner, _, headers = space_context
    space = seed_space(db, owner.id)
    response = request(db, "POST", f"{BASE}/{space.id}/{action}", json={"status": "ACTIVE"}, headers=headers)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "VALIDATION_ERROR"
    assert read_space(db, space.id).updated_at == space.updated_at
