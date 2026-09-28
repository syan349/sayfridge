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


pytestmark = pytest.mark.postgres


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
