"""Real PostgreSQL fixtures for inventory acceptance."""
from datetime import datetime, timezone
from decimal import Decimal
import uuid

import pytest
from sqlalchemy.orm import Session

from app.db.models import InventoryItem, StorageSpace
from catalog_test_support import seed_category, seed_definition
from auth_test_support import make_user, seed_users
from app.core.config import get_settings
from app.core.security import create_access_token

BASE = "/api/v1/inventory-items"


def seed_space(database, user_id, name="Kitchen", status="ACTIVE"):
    with Session(database[2], expire_on_commit=False) as session:
        row = StorageSpace(user_id=user_id, name=name, type="FRIDGE", status=status)
        session.add(row)
        session.commit()
        return row


@pytest.fixture
def inventory_context(database):
    owner, other = make_user(email="inventory-owner@example.com"), make_user(email="inventory-other@example.com")
    seed_users(database, owner, other)
    category = seed_category(database)
    token = create_access_token(owner.id, get_settings().jwt_secret_key, 15)
    headers = {"Authorization": f"Bearer {token}"}
    space = seed_space(database, owner.id)
    definition = seed_definition(database, category.id)
    return database, owner, other, category, space, definition, headers


def payload(context, **overrides):
    values = {"storage_space_id": str(context[4].id), "item_definition_id": str(context[5].id),
              "amount": "2.5", "unit": "kg"}
    values.update(overrides)
    return values


def seed_inventory(context, **overrides):
    values = dict(id=uuid.uuid4(), storage_space_id=context[4].id, item_definition_id=context[5].id,
                  initial_amount=Decimal("2.5"), initial_unit="kg", confirmed_current_amount=Decimal("2.5"),
                  confirmed_current_unit="kg", confirmed_at=datetime.now(timezone.utc), status="IN_STOCK", version=1)
    values.update(overrides)
    with Session(context[0][2], expire_on_commit=False) as session:
        row = InventoryItem(**values)
        session.add(row)
        session.commit()
        return row
