"""Typed categories deduplicate per account; batch category changes are isolated."""
import asyncio
from uuid import UUID, uuid4

import pytest
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.models import InventoryItem, ItemCategory, ItemDefinition
from auth_test_support import exercise, request
from catalog_test_support import CATEGORIES, DEFINITIONS, catalog_context, seed_category
from inventory_test_support import BASE, inventory_context, seed_inventory

pytestmark = pytest.mark.postgres


def auth(user):
    return {"Authorization": f"Bearer {create_access_token(user.id, get_settings().jwt_secret_key, 15)}"}


def test_typed_category_reuses_public_and_owned_normalized_names(catalog_context):
    db, owner, _, category, headers = catalog_context
    public = request(db, "POST", CATEGORIES, headers=headers, json={"name": "  FOOD  "})
    assert public.status_code == 201 and public.json()["id"] == str(category.id)
    first = request(db, "POST", CATEGORIES, headers=headers, json={"name": "Meal Prep"})
    again = request(db, "POST", CATEGORIES, headers=headers, json={"name": "  ＭＥＡＬ   ＰＲＥＰ "})
    assert first.status_code == again.status_code == 201
    assert first.json()["id"] == again.json()["id"]
    with Session(db[2]) as session:
        row = session.get(ItemCategory, UUID(first.json()["id"]))
        assert row.owner_user_id == owner.id
        assert row.normalized_name == "meal prep"


def test_private_categories_are_not_listed_or_usable_by_other_accounts(catalog_context):
    db, _, other, _, headers = catalog_context
    category = request(db, "POST", CATEGORIES, headers=headers, json={"name": "Family snacks"}).json()
    other_headers = auth(other)
    listed = request(db, "GET", CATEGORIES + "?status=ALL", headers=other_headers).json()
    assert category["id"] not in {row["id"] for row in listed["items"]}
    denied = request(db, "POST", DEFINITIONS, headers=other_headers,
                     json={"name": "My rice", "category_id": category["id"]})
    assert denied.status_code == 404
    own = request(db, "POST", CATEGORIES, headers=other_headers, json={"name": "Family snacks"})
    assert own.status_code == 201 and own.json()["id"] != category["id"]


def test_category_list_alphabetizes_across_public_and_private_rows(catalog_context):
    db, _, _, _, headers = catalog_context
    seed_category(db, "Zucchini", sort_order=0)
    seed_category(db, "Apples", sort_order=99)
    request(db, "POST", CATEGORIES, headers=headers, json={"name": "Baking"})
    rows = request(db, "GET", CATEGORIES, headers=headers).json()["items"]
    assert [row["name"] for row in rows] == ["Apples", "Baking", "Food", "Zucchini"]


def test_concurrent_typed_categories_return_the_same_row(catalog_context):
    db, _, _, _, headers = catalog_context
    async def scenario(client, sessions):
        responses = await asyncio.gather(*[
            client.post(CATEGORIES, headers=headers, json={"name": name})
            for name in ["Snacks", " snacks "]
        ])
        assert all(response.status_code == 201 for response in responses)
        assert responses[0].json()["id"] == responses[1].json()["id"]
    asyncio.run(exercise(db, scenario))


def test_detail_category_edit_changes_only_this_batch_and_is_used_in_filters(inventory_context):
    context = inventory_context
    item, sibling = seed_inventory(context), seed_inventory(context)
    category = request(context[0], "POST", CATEGORIES, headers=context[-1], json={"name": "Meal Prep"}).json()
    response = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1],
                       json={"expected_version": 1, "category_id": category["id"]})
    assert response.status_code == 200, response.text
    assert response.json()["category_id"] == category["id"]
    assert response.json()["version"] == 2
    unchanged = request(context[0], "GET", f"{BASE}/{sibling.id}", headers=context[-1]).json()
    assert unchanged["category_id"] == str(context[3].id)
    filtered = request(context[0], "GET", f"{BASE}?category_id={category['id']}", headers=context[-1]).json()
    assert [row["id"] for row in filtered["items"]] == [str(item.id)]
    stale = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1],
                    json={"expected_version": 1, "category_id": str(context[3].id)})
    assert stale.status_code == 409


def test_renaming_and_reclassifying_a_batch_uses_the_selected_category(inventory_context):
    context = inventory_context
    item = seed_inventory(context)
    category = request(context[0], "POST", CATEGORIES, headers=context[-1], json={"name": "Meal Prep"}).json()
    response = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1],
                       json={"expected_version": 1, "category_id": category["id"], "item_name": "Prepared meal"})
    assert response.status_code == 200, response.text
    assert response.json()["category_id"] == category["id"]
    with Session(context[0][2]) as session:
        definition = session.get(ItemDefinition, UUID(response.json()["item_definition_id"]))
        assert str(definition.category_id) == category["id"]


@pytest.mark.parametrize("target", ["other-account", "missing", "archived", "null"])
def test_invalid_category_edits_do_not_save_other_fields(inventory_context, target):
    context = inventory_context
    item = seed_inventory(context)
    if target == "other-account":
        category_id = request(context[0], "POST", CATEGORIES, headers=auth(context[2]), json={"name": "Private"}).json()["id"]
    elif target == "archived":
        category_id = str(seed_category(context[0], "Old", status="ARCHIVED").id)
    else:
        category_id = None if target == "null" else str(uuid4())
    response = request(context[0], "PATCH", f"{BASE}/{item.id}", headers=context[-1],
                       json={"expected_version": 1, "category_id": category_id, "notes": "Must roll back"})
    assert response.status_code == (422 if target == "null" else 409 if target == "archived" else 404)
    with Session(context[0][2]) as session:
        stored = session.get(InventoryItem, item.id)
        assert stored.version == 1 and stored.notes is None and stored.category_override_id is None
