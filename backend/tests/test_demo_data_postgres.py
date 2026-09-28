"""Demo data is complete, idempotent, and reset without touching baseline data."""
from __future__ import annotations

from datetime import date

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.category_catalog import CATEGORIES
from app.core.demo_catalog import (
    DEMO_USERS,
    INVENTORY_SCENARIOS,
    PUBLIC_ITEM_DEFINITIONS,
)
from app.core.security import hash_password
from app.db.models import (
    InventoryItem,
    InventoryOperation,
    ItemCategory,
    ItemDefinition,
    StorageSpace,
    User,
)
from scripts.manage_demo_data import (
    inspect_demo_data,
    reset_demo_data,
    seed_demo_data,
)


pytestmark = pytest.mark.postgres


def _seed_categories(session: Session) -> None:
    for category in CATEGORIES:
        session.add(
            ItemCategory(
                name=category["name"],
                normalized_name=category["normalized_name"],
                status="ACTIVE",
                sort_order=category["sort_order"],
            )
        )
    session.flush()


def test_demo_seed_is_complete_idempotent_and_resettable(database):
    _url, _schema, engine = database
    existing_id = None
    existing_hash = hash_password("existing-account-password")

    with Session(engine) as session, session.begin():
        _seed_categories(session)
        existing = User(
            email=DEMO_USERS[0].email,
            password_hash=existing_hash,
            auth_provider="LOCAL",
            role="USER",
            status="ACTIVE",
            voice_limit_seconds=0,
            voice_used_seconds=0,
        )
        session.add(existing)
        session.flush()
        existing_id = existing.id

    with Session(engine) as session, session.begin():
        first = seed_demo_data(
            session,
            user_password="ordinary-demo-password",
            admin_password="administrator-demo-password",
            today=date(2026, 9, 28),
        )
    with Session(engine) as session, session.begin():
        second = seed_demo_data(
            session,
            user_password="a-different-password-is-not-applied",
            admin_password="another-password-is-not-applied",
            today=date(2026, 10, 1),
        )
        preserved = session.scalar(select(User).where(User.email == DEMO_USERS[0].email))
        assert preserved is not None
        assert preserved.id == existing_id
        assert preserved.password_hash == existing_hash

    expected_operations_per_user = sum(
        scenario.operation is not None for scenario in INVENTORY_SCENARIOS
    )
    assert first == second
    assert first.users == len(DEMO_USERS) == 11
    assert first.storage_spaces == len(DEMO_USERS) * 3 == 33
    assert first.public_definitions == len(PUBLIC_ITEM_DEFINITIONS) == 25
    assert first.inventory_items == len(DEMO_USERS) * len(INVENTORY_SCENARIOS) == 77
    assert first.inventory_operations == len(DEMO_USERS) * expected_operations_per_user == 66

    with Session(engine) as session, session.begin():
        status_counts = dict(
            session.execute(
                select(InventoryItem.status, func.count()).group_by(InventoryItem.status)
            ).all()
        )
        assert status_counts == {
            "ARCHIVED": 11,
            "DISCARDED": 11,
            "EMPTY": 11,
            "IN_STOCK": 44,
        }
        reset_demo_data(session)

    with Session(engine) as session:
        report = inspect_demo_data(session)
        assert report.inventory_items == 0
        assert report.inventory_operations == 0
        assert report.storage_spaces == 0
        assert session.scalar(select(func.count()).select_from(ItemCategory)) == 25
        assert session.scalar(select(func.count()).select_from(StorageSpace)) == 0
        assert session.scalar(select(func.count()).select_from(InventoryItem)) == 0
        assert session.scalar(select(func.count()).select_from(InventoryOperation)) == 0
        assert session.scalar(
            select(func.count()).select_from(ItemDefinition)
        ) == 0
        preserved = session.scalar(select(User).where(User.email == DEMO_USERS[0].email))
        assert preserved is not None
        assert preserved.id == existing_id
