from sqlalchemy import CheckConstraint

from app.db.base import Base
from app.db import models  # noqa: F401  # Import models to register them with Base.metadata.


EXPECTED_TABLES = {
    "auth_session",
    "auth_refresh_credential",
    "user",
    "storage_space",
    "item_category",
    "item_definition",
    "inventory_item",
    "inventory_operation",
    "conversation",
    "conversation_message",
    "agent_inventory_action",
}


def test_database_metadata_contains_expected_business_tables() -> None:
    assert set(Base.metadata.tables) == EXPECTED_TABLES


def test_inventory_item_does_not_duplicate_dictionary_fields() -> None:
    columns = Base.metadata.tables["inventory_item"].columns

    assert "item_definition_id" in columns
    assert "name" not in columns
    assert "category_id" not in columns


def test_estimated_inventory_fields_are_present_as_one_trio() -> None:
    table = Base.metadata.tables["inventory_item"]
    columns = table.columns
    constraint_sql = {
        str(item.sqltext)
        for item in table.constraints
        if isinstance(item, CheckConstraint)
    }

    assert {
        "estimated_current_amount",
        "estimated_current_unit",
        "estimated_at",
    }.issubset(columns.keys())
    assert any("estimated_current_amount IS NULL" in sql for sql in constraint_sql)
