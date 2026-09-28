"""Initialize and verify every PostgreSQL object required by a fresh backend."""
from __future__ import annotations

import argparse
import asyncio
import re
import sys
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.pool import NullPool


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.agents.persistence import get_agent_persistence_settings  # noqa: E402
from app.core.category_catalog import CATEGORIES  # noqa: E402
from app.core.config import get_settings  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db import models  # noqa: E402,F401  # Register ORM metadata.
from scripts.render_category_seed import render_seed_sql  # noqa: E402
from scripts.setup_agent_storage import initialize_and_verify  # noqa: E402


SCHEMA_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--business-schema",
        default="public",
        help="Business schema to initialize; production uses public.",
    )
    return parser.parse_args()


def validate_schema_name(value: str) -> str:
    if not SCHEMA_PATTERN.fullmatch(value):
        raise SystemExit(
            "--business-schema must be a lowercase PostgreSQL identifier"
        )
    return value


def initialize_business_database(schema_name: str) -> None:
    settings = get_settings()
    engine = create_engine(
        settings.database_url_direct.get_secret_value(),
        poolclass=NullPool,
        hide_parameters=True,
        connect_args={"connect_timeout": 15},
    )
    quoted_schema = engine.dialect.identifier_preparer.quote(schema_name)
    try:
        with engine.begin() as connection:
            connection.exec_driver_sql(
                f"CREATE SCHEMA IF NOT EXISTS {quoted_schema}"
            )
            connection.exec_driver_sql(
                f"SET LOCAL search_path TO {quoted_schema}"
            )
            config = Config(str(BACKEND_DIR / "alembic.ini"))
            config.attributes["connection"] = connection
            command.upgrade(config, "head")
            command.check(config)

        raw = engine.raw_connection()
        try:
            driver_connection = raw.driver_connection
            driver_connection.autocommit = True
            try:
                driver_connection.execute(render_seed_sql(schema_name))
            except Exception:
                driver_connection.execute("ROLLBACK")
                raise
            finally:
                driver_connection.autocommit = False
        finally:
            raw.close()

        expected_tables = set(Base.metadata.tables)
        with engine.connect() as connection:
            actual_tables = set(
                inspect(connection).get_table_names(schema=schema_name)
            )
            missing_tables = expected_tables - actual_tables
            if missing_tables:
                raise RuntimeError(
                    "Business initialization is missing ORM tables: "
                    + ", ".join(sorted(missing_tables))
                )
            active_categories = set(
                connection.scalars(
                    text(
                        f"SELECT normalized_name FROM {quoted_schema}.item_category "
                        "WHERE status = 'ACTIVE'"
                    )
                )
            )
            expected_categories = {
                category["normalized_name"] for category in CATEGORIES
            }
            missing_categories = expected_categories - active_categories
            if missing_categories:
                raise RuntimeError(
                    "Business initialization is missing public categories: "
                    + ", ".join(sorted(missing_categories))
                )
    finally:
        engine.dispose()

    print("Business database initialized and verified:")
    print(f"  schema: {schema_name}")
    print(f"  ORM tables: {len(expected_tables)} present")
    print(f"  public categories: {len(CATEGORIES)} present")


async def run() -> None:
    args = parse_args()
    schema_name = validate_schema_name(args.business_schema)
    initialize_business_database(schema_name)

    agent_settings = get_agent_persistence_settings()
    search_path = await initialize_and_verify(agent_settings)
    print("Agent database initialized and verified:")
    print(f"  schema: {agent_settings.schema_name}")
    print(f"  search_path: {search_path}")
    print("Fresh-database initialization completed successfully.")


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(run())
