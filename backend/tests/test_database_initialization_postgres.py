"""The documented initializer builds a complete backend in an empty database."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

import pytest
from sqlalchemy import inspect, text

from app.core.category_catalog import CATEGORIES
from app.db.base import Base
from app.db import models  # noqa: F401  # Register ORM metadata.
from app.db.schema_verification import SchemaVerificationError, verify_schema


pytestmark = pytest.mark.postgres


@pytest.mark.ci
def test_fresh_database_initializer_is_complete_and_repeatable(database):
    url, schema, engine = database
    agent_schema = f"{schema}_agent"

    # The shared fixture gives this test a private schema. Return it to a truly
    # empty state so the command, rather than the fixture, creates every object.
    with engine.begin() as connection:
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.execute(text(f'CREATE SCHEMA "{schema}"'))

    env = dict(os.environ)
    direct_url = url.render_as_string(hide_password=False)
    env.update(
        DATABASE_URL=direct_url,
        DATABASE_URL_DIRECT=direct_url,
        AGENT_DATABASE_URL=direct_url,
        AGENT_DATABASE_SCHEMA=agent_schema,
    )
    backend = Path(__file__).resolve().parents[1]

    def initialize():
        return subprocess.run(
            [
                sys.executable,
                "scripts/initialize_database.py",
                "--business-schema",
                schema,
            ],
            cwd=backend,
            env=env,
            text=True,
            capture_output=True,
            timeout=60,
        )

    try:
        first = initialize()
        assert first.returncode == 0, first.stderr
        second = initialize()
        assert second.returncode == 0, second.stderr

        expected_tables = set(Base.metadata.tables)
        actual_tables = set(inspect(engine).get_table_names(schema=schema))
        assert expected_tables <= actual_tables
        with engine.connect() as connection:
            report = verify_schema(connection, Base.metadata, schema=schema)
            assert report.tables == len(expected_tables)
            assert report.columns == sum(
                len(table.columns) for table in Base.metadata.tables.values()
            )
            assert report.foreign_keys > 0
            assert report.check_constraints > 0
            assert report.indexes > 0
            assert connection.scalar(
                text("SELECT count(*) FROM item_category WHERE status = 'ACTIVE'")
            ) == len(CATEGORIES)
            assert connection.scalar(
                text(
                    "SELECT count(*) FROM pg_catalog.pg_tables "
                    "WHERE schemaname = :schema"
                ),
                {"schema": agent_schema},
            ) > 0
    finally:
        # The fixture only owns its business schema.
        with engine.begin() as connection:
            connection.execute(
                text(f'DROP SCHEMA IF EXISTS "{agent_schema}" CASCADE')
            )


def test_schema_verification_reports_missing_required_objects(database):
    _url, schema, engine = database

    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE inventory_item DROP COLUMN notes"))
        connection.execute(
            text(
                "ALTER TABLE conversation DROP CONSTRAINT "
                "fk_conversation_user_id_user"
            )
        )
        connection.execute(
            text(
                "ALTER TABLE inventory_operation DROP CONSTRAINT "
                "ck_inventory_operation_status_allowed"
            )
        )
        connection.execute(text('ALTER TABLE "user" DROP CONSTRAINT uq_user_email'))
        connection.execute(text("DROP INDEX ix_inventory_item_definition"))

    with engine.connect() as connection:
        with pytest.raises(SchemaVerificationError) as error:
            verify_schema(connection, Base.metadata, schema=schema)

    message = str(error.value)
    assert "inventory_item: missing column notes" in message
    assert "conversation: missing foreign key" in message
    assert "ck_inventory_operation_status_allowed" in message
    assert "user: missing unique constraint on ('email',)" in message
    assert "inventory_item: missing index ix_inventory_item_definition" in message
