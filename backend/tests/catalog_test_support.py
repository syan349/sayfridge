"""Isolated PostgreSQL fixtures for category and definition acceptance tests."""
import uuid

import pytest
from sqlalchemy.orm import Session

from app.core.catalog import normalize_catalog_name
from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.models import ItemCategory, ItemDefinition
from auth_test_support import make_user, seed_users

CATEGORIES = "/api/v1/item-categories"
DEFINITIONS = "/api/v1/item-definitions"


def seed_category(database, name="Food", *, status="ACTIVE", sort_order=0):
    with Session(database[2], expire_on_commit=False) as session:
        row = ItemCategory(name=name, normalized_name=normalize_catalog_name(name), status=status, sort_order=sort_order)
        session.add(row)
        session.commit()
        return row


def seed_definition(database, category_id, *, name="Rice", owner_id=None, status="ACTIVE", normalized_name=None, row_id=None):
    with Session(database[2], expire_on_commit=False) as session:
        row = ItemDefinition(id=row_id or uuid.uuid4(), name=name, category_id=category_id,
                             normalized_name=normalized_name if normalized_name is not None else normalize_catalog_name(name),
                             owner_user_id=owner_id, status=status)
        session.add(row)
        session.commit()
        return row


def read_definition(database, definition_id):
    with Session(database[2]) as session:
        return session.get(ItemDefinition, definition_id)


@pytest.fixture
def catalog_context(database):
    owner = make_user(email="catalog-owner@example.com")
    other = make_user(email="catalog-other@example.com")
    seed_users(database, owner, other)
    category = seed_category(database)
    token = create_access_token(owner.id, get_settings().jwt_secret_key, 15)
    return database, owner, other, category, {"Authorization": f"Bearer {token}"}
