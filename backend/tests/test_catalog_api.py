"""B05/B06 API contracts, normalization, filtering, and owner isolation."""
import asyncio
from datetime import datetime, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, ItemDefinition, User
from auth_test_support import exercise, request
from catalog_test_support import (
    CATEGORIES, DEFINITIONS, catalog_context, read_definition, seed_category, seed_definition,
)
from test_storage_spaces_api import seed_space

pytestmark = pytest.mark.postgres
DEFINITION_FIELDS = {"id", "name", "category_id", "status", "scope"}


@pytest.mark.ci
def test_category_list_filters_orders_paginates_and_exposes_public_fields(catalog_context):
    db, _, _, category, headers = catalog_context
    first = seed_category(db, "First", sort_order=0)
    last = seed_category(db, "Last", sort_order=2)
    archived = seed_category(db, "Archived", status="ARCHIVED", sort_order=1)
    response = request(db, "GET", CATEGORIES, headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 3 and body["page"] == 1 and body["page_size"] == 20
    assert [x["id"] for x in body["items"]] == [str(first.id), str(category.id), str(last.id)]
    assert all(set(x) == {"id", "name", "status", "sort_order"} for x in body["items"])
    old = request(db, "GET", CATEGORIES + "?status=ARCHIVED", headers=headers).json()
    assert [x["id"] for x in old["items"]] == [str(archived.id)]
    page = request(db, "GET", CATEGORIES + "?status=ALL&page=2&page_size=2", headers=headers).json()
    assert page["total"] == 4 and [x["id"] for x in page["items"]] == [str(archived.id), str(last.id)]
    empty = request(db, "GET", CATEGORIES + "?page=999", headers=headers).json()
    assert empty["total"] == 3 and empty["items"] == []


@pytest.mark.ci
def test_definition_list_enforces_visibility_category_state_scope_and_order(catalog_context):
    db, owner, other, category, headers = catalog_context
    archived_cat = seed_category(db, "Old category", status="ARCHIVED")
    public = seed_definition(db, category.id, name="Same")
    private = seed_definition(db, category.id, name="Same", owner_id=owner.id)
    seed_definition(db, category.id, name="Hidden", owner_id=other.id)
    old = seed_definition(db, archived_cat.id, name="Old", status="ARCHIVED")
    active_under_old = seed_definition(db, archived_cat.id, name="Parent archived")
    def get(query=""):
        r = request(db, "GET", DEFINITIONS + query, headers=headers)
        assert r.status_code == 200
        return r.json()
    default = get()
    assert [x["id"] for x in default["items"]] == [str(private.id), str(public.id)]
    assert all(set(x) == DEFINITION_FIELDS for x in default["items"])
    assert get("?scope=PRIVATE")["items"][0]["id"] == str(private.id)
    assert get("?scope=PUBLIC")["total"] == 1
    assert get("?status=ARCHIVED")["items"][0]["id"] == str(old.id)
    assert get("?status=ALL")["total"] == 4
    assert get(f"?status=ALL&category_id={archived_cat.id}")["total"] == 2
    assert get(f"?category_id={uuid.uuid4()}")["total"] == 0
    assert get("?page=2&page_size=1")["items"][0]["id"] == str(public.id)
    beyond = get("?page=99999999999999999999999")
    assert beyond["total"] == 2 and beyond["items"] == []
    for row in [old, active_under_old]:
        assert request(db, "GET", f"{DEFINITIONS}/{row.id}", headers=headers).status_code == 200


@pytest.mark.parametrize("needle", ["%", "_", "/", "\\", "'", " MiLk ", "   "])
def test_definition_search_is_literal_case_insensitive_and_trimmed(catalog_context, needle):
    db, owner, _, category, headers = catalog_context
    literal = seed_definition(db, category.id, name="Milk 10%_ / \\ '", owner_id=owner.id)
    seed_definition(db, category.id, name="Unrelated")
    async def scenario(client, sessions):
        response = await client.get(DEFINITIONS, params={"q": needle}, headers=headers)
        assert response.status_code == 200
        body = response.json()
        assert body["total"] == (2 if not needle.strip() else 1)
        if needle.strip():
            assert body["items"][0]["id"] == str(literal.id)
    asyncio.run(exercise(db, scenario))


@pytest.mark.ci
def test_private_definition_lifecycle_persists_fields_and_preserves_noop_timestamps(catalog_context):
    db, owner, _, category, headers = catalog_context
    new_cat = seed_category(db, "Other")
    created = request(db, "POST", DEFINITIONS, json={"name": "  Rice  ", "category_id": str(category.id)}, headers=headers)
    assert created.status_code == 201
    body = created.json()
    assert set(body) == DEFINITION_FIELDS and body["scope"] == "PRIVATE" and body["name"] == "Rice"
    sid = uuid.UUID(body["id"])
    stored = read_definition(db, sid)
    assert stored.owner_user_id == owner.id and stored.normalized_name == "rice" and stored.status == "ACTIVE"
    url = f"{DEFINITIONS}/{sid}"
    assert request(db, "GET", url, headers=headers).json() == body
    noop = request(db, "PATCH", url, json={"name": " Rice "}, headers=headers)
    assert noop.status_code == 200 and read_definition(db, sid).updated_at == stored.updated_at
    changed = request(db, "PATCH", url, json={"name": "Brown rice", "category_id": str(new_cat.id)}, headers=headers)
    assert changed.status_code == 200 and changed.json()["category_id"] == str(new_cat.id)
    assert read_definition(db, sid).normalized_name == "brown rice"
    assert request(db, "POST", url + "/archive", headers=headers).json()["status"] == "ARCHIVED"
    timestamp = read_definition(db, sid).updated_at
    assert request(db, "POST", url + "/archive", headers=headers).status_code == 200
    assert read_definition(db, sid).updated_at == timestamp
    assert request(db, "PATCH", url, json={"name": "Blocked"}, headers=headers).status_code == 409
    assert request(db, "POST", url + "/restore", headers=headers).json()["status"] == "ACTIVE"
    timestamp = read_definition(db, sid).updated_at
    assert request(db, "POST", url + "/restore", headers=headers).status_code == 200
    assert read_definition(db, sid).updated_at == timestamp


@pytest.mark.parametrize("payload", [
    {}, {"category_id": "$category"}, {"name": "Rice"},
    {"name": " ", "category_id": "$category"}, {"name": None, "category_id": "$category"},
    {"name": 4, "category_id": "$category"}, {"name": "x" * 101, "category_id": "$category"},
    {"name": "\u00df" * 51, "category_id": "$category"},
    {"name": "\ufb03" * 34, "category_id": "$category"},
    {"name": "Rice", "category_id": None}, {"name": "Rice", "category_id": "invalid"},
    pytest.param({"name": "Rice", "category_id": "$category", "owner_user_id": str(uuid.uuid4())}, marks=pytest.mark.ci, id="reject_client_owner"),
    {"name": "Rice", "category_id": "$category", "status": "ARCHIVED"},
    {"name": "Rice", "category_id": "$category", "normalized_name": "other"},
    {"name": "Rice", "category_id": "$category", "password": "do-not-echo"},
])
def test_create_validation_rejects_invalid_or_server_owned_fields_without_writes(catalog_context, payload):
    db, _, _, category, headers = catalog_context
    payload = {key: str(category.id) if value == "$category" else value for key, value in payload.items()}
    response = request(db, "POST", DEFINITIONS, json=payload, headers=headers)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "VALIDATION_ERROR"
    assert "do-not-echo" not in response.text
    with Session(db[2]) as session:
        assert session.scalars(select(ItemDefinition)).all() == []


@pytest.mark.parametrize("payload", [{}, {"name": None}, {"category_id": None}, {"name": " "}, {"name": "x" * 101}, {"name": "\u00df" * 51}, {"category_id": "invalid"}, {"owner_user_id": str(uuid.uuid4())}])
def test_patch_validation_preserves_existing_data(catalog_context, payload):
    db, owner, _, category, headers = catalog_context
    row = seed_definition(db, category.id, owner_id=owner.id)
    response = request(db, "PATCH", f"{DEFINITIONS}/{row.id}", json=payload, headers=headers)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "VALIDATION_ERROR"
    assert read_definition(db, row.id).updated_at == row.updated_at


@pytest.mark.parametrize("method,suffix", [pytest.param("PATCH", "", marks=pytest.mark.ci), ("POST", "/archive"), ("POST", "/restore")])
def test_private_write_endpoints_reject_public_foreign_and_missing_ids_identically(catalog_context, method, suffix):
    db, _, other, category, headers = catalog_context
    public = seed_definition(db, category.id)
    foreign = seed_definition(db, category.id, owner_id=other.id)
    payload = {"name": "Changed"} if method == "PATCH" else None
    responses = [request(db, method, f"{DEFINITIONS}/{sid}{suffix}", json=payload, headers=headers) for sid in [public.id, foreign.id, uuid.uuid4()]]
    assert all(r.status_code == 404 for r in responses)
    assert responses[0].json() == responses[1].json() == responses[2].json()
    assert read_definition(db, foreign.id).name == "Rice"


def test_definition_detail_hides_foreign_and_missing_ids(catalog_context):
    db, _, other, category, headers = catalog_context
    foreign = seed_definition(db, category.id, owner_id=other.id)
    a = request(db, "GET", f"{DEFINITIONS}/{foreign.id}", headers=headers)
    b = request(db, "GET", f"{DEFINITIONS}/{uuid.uuid4()}", headers=headers)
    assert a.status_code == b.status_code == 404 and a.json() == b.json()


@pytest.mark.parametrize("method,path,payload", [
    ("GET", CATEGORIES, None), ("GET", DEFINITIONS, None), ("GET", DEFINITIONS + "/{id}", None),
    ("POST", DEFINITIONS, {"name": "Rice", "category_id": "$category"}),
    ("PATCH", DEFINITIONS + "/{id}", {"name": "Changed"}),
    ("POST", DEFINITIONS + "/{id}/archive", None), ("POST", DEFINITIONS + "/{id}/restore", None),
])
def test_all_catalog_endpoints_require_authentication(catalog_context, method, path, payload):
    db, owner, _, category, _ = catalog_context
    row = seed_definition(db, category.id, owner_id=owner.id)
    if payload:
        payload = {k: str(category.id) if v == "$category" else v for k, v in payload.items()}
    assert request(db, method, path.format(id=row.id), json=payload).status_code == 401


@pytest.mark.parametrize("state", ["SUSPENDED", "DISABLED"])
def test_catalog_reads_and_writes_reject_inactive_accounts(catalog_context, state):
    db, owner, _, category, headers = catalog_context
    with Session(db[2]) as session:
        session.get(User, owner.id).status = state
        session.commit()
    assert request(db, "GET", CATEGORIES, headers=headers).status_code == 401
    assert request(db, "POST", DEFINITIONS, json={"name": "Rice", "category_id": str(category.id)}, headers=headers).status_code == 401


@pytest.mark.parametrize("query", ["page=0", "page_size=101", "status=invalid", "owner_user_id=other", "scope=invalid", "category_id=bad", "q=" + "x" * 101])
def test_invalid_definition_queries_return_business_errors(catalog_context, query):
    db, _, _, _, headers = catalog_context
    response = request(db, "GET", DEFINITIONS + "?" + query, headers=headers)
    assert response.status_code == 422 and response.json()["detail"]["code"] == "VALIDATION_ERROR"


@pytest.mark.parametrize("query", ["page=-1", "page_size=0", "status=bad", "q=unexpected"])
def test_invalid_category_queries_return_business_errors(catalog_context, query):
    db, _, _, _, headers = catalog_context
    assert request(db, "GET", CATEGORIES + "?" + query, headers=headers).status_code == 422


@pytest.mark.parametrize("existing_state", [pytest.param("ARCHIVED", marks=pytest.mark.ci), "ACTIVE"])
def test_legacy_equivalent_names_remain_reserved_across_categories(catalog_context, existing_state):
    db, owner, _, category, headers = catalog_context
    old = seed_definition(db, category.id, name="\uff2d\uff49\uff4c\uff4b", normalized_name="legacy-key", owner_id=owner.id, status=existing_state)
    new_category = seed_category(db, "Other")
    response = request(db, "POST", DEFINITIONS, json={"name": " milk ", "category_id": str(new_category.id)}, headers=headers)
    assert response.status_code == 409 and response.json()["detail"]["code"] == "NAME_CONFLICT"
    editable = seed_definition(db, category.id, name="Oats", owner_id=owner.id)
    response = request(db, "PATCH", f"{DEFINITIONS}/{editable.id}", json={"name": "MILK", "category_id": str(new_category.id)}, headers=headers)
    assert response.status_code == 409
    assert read_definition(db, editable.id).category_id == category.id
    assert read_definition(db, editable.id).name == "Oats"
    assert read_definition(db, old.id).normalized_name == "legacy-key"


def test_normalized_names_allow_other_scopes_and_enforce_unicode_boundaries(catalog_context):
    db, owner, other, category, headers = catalog_context
    seed_definition(db, category.id, name="Milk")
    seed_definition(db, category.id, name="Milk", owner_id=other.id)
    response = request(db, "POST", DEFINITIONS, json={"name": "  \uff2d\uff49\uff4c\uff4b  ", "category_id": str(category.id)}, headers=headers)
    assert response.status_code == 201
    assert read_definition(db, uuid.UUID(response.json()["id"])).normalized_name == "milk"
    boundary = request(db, "POST", DEFINITIONS, json={"name": "\u00df" * 50, "category_id": str(category.id)}, headers=headers)
    assert boundary.status_code == 201
    assert len(read_definition(db, uuid.UUID(boundary.json()["id"])).normalized_name) == 100
    duplicate = request(db, "POST", DEFINITIONS, json={"name": "SS" * 50, "category_id": str(category.id)}, headers=headers)
    assert duplicate.status_code == 409


@pytest.mark.parametrize("operation", ["create", "patch", "restore"])
def test_category_state_and_existence_are_checked_before_associations(catalog_context, operation):
    db, owner, _, category, headers = catalog_context
    old_category = seed_category(db, "Archived", status="ARCHIVED")
    if operation == "restore":
        row = seed_definition(db, old_category.id, owner_id=owner.id, status="ARCHIVED")
        response = request(db, "POST", f"{DEFINITIONS}/{row.id}/restore", headers=headers)
        assert response.status_code == 409 and read_definition(db, row.id).status == "ARCHIVED"
    else:
        row = seed_definition(db, category.id, owner_id=owner.id)
        for category_id, expected in [(old_category.id, 409), (uuid.uuid4(), 404)]:
            payload = {"name": "New", "category_id": str(category_id)}
            response = request(db, "POST" if operation == "create" else "PATCH",
                               DEFINITIONS if operation == "create" else f"{DEFINITIONS}/{row.id}", json=payload, headers=headers)
            assert response.status_code == expected
        assert read_definition(db, row.id).category_id == category.id


def test_renaming_in_archived_category_and_repeated_restore_rules(catalog_context):
    db, owner, _, _, headers = catalog_context
    category = seed_category(db, "Archived", status="ARCHIVED")
    row = seed_definition(db, category.id, owner_id=owner.id)
    url = f"{DEFINITIONS}/{row.id}"
    assert request(db, "PATCH", url, json={"name": "Renamed"}, headers=headers).status_code == 200
    assert request(db, "POST", url + "/restore", headers=headers).status_code == 409
    assert request(db, "POST", url + "/archive", headers=headers).status_code == 200


def test_definition_archival_does_not_change_referenced_inventory(catalog_context):
    db, owner, _, category, headers = catalog_context
    row = seed_definition(db, category.id, owner_id=owner.id)
    space = seed_space(db, owner.id)
    with Session(db[2], expire_on_commit=False) as session:
        item = InventoryItem(storage_space_id=space.id, item_definition_id=row.id,
                             initial_amount=Decimal("1"), initial_unit="kg", confirmed_current_amount=Decimal("1"),
                             confirmed_current_unit="kg", confirmed_at=datetime.now(timezone.utc))
        session.add(item)
        session.commit()
        item_id = item.id
    assert request(db, "POST", f"{DEFINITIONS}/{row.id}/archive", headers=headers).status_code == 200
    with Session(db[2]) as session:
        item = session.get(InventoryItem, item_id)
        assert item.status == "IN_STOCK" and item.version == 1 and item.item_definition_id == row.id
        assert item.confirmed_current_amount == 1


@pytest.mark.parametrize("action", ["archive", "restore"])
def test_definition_state_actions_reject_request_bodies(catalog_context, action):
    db, owner, _, category, headers = catalog_context
    row = seed_definition(db, category.id, owner_id=owner.id)
    response = request(db, "POST", f"{DEFINITIONS}/{row.id}/{action}", json={}, headers=headers)
    assert response.status_code == 422 and read_definition(db, row.id).updated_at == row.updated_at
