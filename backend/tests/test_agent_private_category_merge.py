"""Private categories work with the stock classification/snapshot policy."""
import asyncio
from uuid import uuid4

import pytest
from langgraph.store.memory import InMemoryStore
from sqlalchemy.orm import Session

from app.agents.memory import MemoryService
from app.core.catalog import normalize_category_name
from app.db.models import ItemCategory
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import PreparationError, execute_action, prepare_action
from auth_test_support import exercise
from catalog_test_support import seed_definition
from inventory_test_support import inventory_context

pytestmark = pytest.mark.postgres


def private_category(context, owner, name):
    with Session(context[0][2], expire_on_commit=False) as session:
        category = ItemCategory(owner_user_id=owner.id, name=name,
                                normalized_name=normalize_category_name(name))
        session.add(category)
        session.commit()
        return category


@pytest.mark.parametrize("existing", [False, True])
def test_owned_category_is_normalized_and_survives_preview_execution(inventory_context, existing):
    c = inventory_context
    category = private_category(c, c[1], "Meal Prep")
    # A different user may have the same normalized name, but must not be selected.
    private_category(c, c[2], "Meal Prep")
    definition = seed_definition(c[0], c[3].id, name="Prepared lunch", owner_id=c[1].id) if existing else None
    draft = ActionDraft(item_key="lunch", original_text="Add 2 prepared lunches", action="CREATE_STOCK",
        storage_space_id=c[4].id, quantity_value="2", quantity_unit="each",
        item_definition_id=definition.id if definition else None,
        new_definition=None if definition else {"name": "Prepared lunch", "category_id": category.id},
        category_name="  ＭＥＡＬ   ＰＲＥＰ  ")

    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        async with sessions() as session:
            preview = await prepare_action(session, c[1].id, draft, memory)
        assert preview["display"]["category_id"] == str(category.id)
        assert preview["association"]["category_id"] == str(category.id)
        assert preview["association"]["correction"] == ("PRIVATE" if existing else None)
        async with sessions() as session:
            result = await execute_action(session, c[1].id, uuid4(), uuid4(), uuid4(), preview, memory, approved=True)
        assert result["inventory"]["category_id"] == str(category.id)
        assert result["inventory"]["confirmed_current_amount"] == "2.000"
    asyncio.run(exercise(c[0], scenario))


@pytest.mark.parametrize("selection", ["id", "name"])
def test_other_users_category_is_rejected_and_not_offered(inventory_context, selection):
    c = inventory_context
    hidden = private_category(c, c[2], "Private snacks")
    draft = ActionDraft(item_key="snacks", original_text="Add 2 snacks", action="CREATE_STOCK",
        storage_space_id=c[4].id, quantity_value="2", quantity_unit="each",
        new_definition={"name": "Snacks", "category_id": hidden.id if selection == "id" else c[3].id},
        category_name=hidden.name if selection == "name" else None)

    async def scenario(client, sessions):
        memory = MemoryService(InMemoryStore(), c[1].id)
        async with sessions() as session:
            with pytest.raises(PreparationError) as rejected:
                await prepare_action(session, c[1].id, draft, memory)
        assert rejected.value.code == "CATEGORY_REQUIRED"
        offered = {row["id"] for row in rejected.value.details["categories"]}
        assert str(hidden.id) not in offered
        assert str(c[3].id) in offered
    asyncio.run(exercise(c[0], scenario))
