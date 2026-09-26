"""Inspect or explicitly initialize LangGraph PostgreSQL storage."""
from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Any
from uuid import uuid4

from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langgraph.store.postgres import AsyncPostgresStore
from psycopg import AsyncConnection, sql
from psycopg.rows import dict_row

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.agents.persistence import (  # noqa: E402
    AgentPersistenceSettings,
    create_agent_pool,
    get_agent_persistence_settings,
)


@dataclass(frozen=True, slots=True)
class DatabaseTarget:
    host: str
    port: int | None
    database: str
    user: str

    def display_host(self) -> str:
        host = redact(self.host)
        return f"{host}:{self.port}" if self.port is not None else host


def redact(value: str) -> str:
    if len(value) <= 2:
        return "***"
    if len(value) <= 6:
        return f"{value[0]}***{value[-1]}"
    return f"{value[:2]}***{value[-2:]}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check or initialize the isolated Agent PostgreSQL schema.",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--check",
        action="store_true",
        help="Run read-only target, schema, table, and privilege checks.",
    )
    mode.add_argument(
        "--initialize",
        action="store_true",
        help="Require confirmation, initialize Agent storage, then verify it.",
    )
    return parser.parse_args()


def connection_target(connection: AsyncConnection[Any]) -> DatabaseTarget:
    info = connection.info
    return DatabaseTarget(
        host=info.host or "unknown",
        port=info.port,
        database=info.dbname or "unknown",
        user=info.user or "unknown",
    )


def looks_like_pooler(target: DatabaseTarget) -> bool:
    host = target.host.lower()
    return "pooler" in host or target.port == 6543


async def inspect_database(
    connection: AsyncConnection[Any],
    schema_name: str,
) -> tuple[DatabaseTarget, bool, list[str], bool, bool | None, bool | None]:
    target = connection_target(connection)
    schema_row = await (
        await connection.execute(
            "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = %s) "
            "AS schema_exists",
            (schema_name,),
        )
    ).fetchone()
    schema_exists = bool(schema_row["schema_exists"])

    rows = await (
        await connection.execute(
            "SELECT tablename FROM pg_catalog.pg_tables "
            "WHERE schemaname = %s ORDER BY tablename",
            (schema_name,),
        )
    ).fetchall()
    tables = [row[0] if isinstance(row, tuple) else row["tablename"] for row in rows]

    database_create = await (
        await connection.execute(
            "SELECT has_database_privilege(current_user, current_database(), 'CREATE') "
            "AS database_create"
        )
    ).fetchone()
    database_create = bool(database_create["database_create"])

    schema_usage: bool | None = None
    schema_create: bool | None = None
    if schema_exists:
        privileges = await (
            await connection.execute(
                "SELECT has_schema_privilege(current_user, %s, 'USAGE') AS schema_usage, "
                "has_schema_privilege(current_user, %s, 'CREATE') AS schema_create",
                (schema_name, schema_name),
            )
        ).fetchone()
        schema_usage = bool(privileges["schema_usage"])
        schema_create = bool(privileges["schema_create"])

    return target, schema_exists, tables, database_create, schema_usage, schema_create


def print_inspection(
    *,
    source: str,
    schema_name: str,
    result: tuple[DatabaseTarget, bool, list[str], bool, bool | None, bool | None],
) -> None:
    target, schema_exists, tables, database_create, schema_usage, schema_create = result
    print("Agent storage target (credentials hidden):")
    print(f"  URL source: {source}")
    print(f"  host: {target.display_host()}")
    print(f"  database: {redact(target.database)}")
    print(f"  user: {redact(target.user)}")
    print(f"  schema: {schema_name}")
    print(f"  schema exists: {'yes' if schema_exists else 'no'}")
    print(f"  existing tables: {', '.join(tables) if tables else '(none)'}")
    if schema_exists:
        print(f"  required existing-schema USAGE privilege: {'yes' if schema_usage else 'no'}")
        print(f"  required existing-schema CREATE privilege: {'yes' if schema_create else 'no'}")
    else:
        print(f"  required database CREATE privilege: {'yes' if database_create else 'no'}")
    if looks_like_pooler(target):
        print("WARNING: The target resembles a pooled endpoint; use a direct PostgreSQL endpoint for setup.")


async def read_only_inspection(settings: AgentPersistenceSettings):
    async with await AsyncConnection.connect(
        settings.psycopg_url(),
        autocommit=True,
        row_factory=dict_row,
    ) as connection:
        await connection.execute("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY")
        return await inspect_database(connection, settings.schema_name)


async def public_objects(connection: AsyncConnection[Any]) -> list[tuple[str, str]]:
    rows = await (
        await connection.execute(
            "SELECT c.relkind::text AS object_kind, c.relname AS object_name "
            "FROM pg_catalog.pg_class AS c "
            "JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace "
            "WHERE n.nspname = 'public' ORDER BY c.relkind, c.relname"
        )
    ).fetchall()
    return [(row["object_kind"], row["object_name"]) for row in rows]


async def run_check() -> None:
    settings = get_agent_persistence_settings()
    result = await read_only_inspection(settings)
    print_inspection(
        source=settings.database_url_source,
        schema_name=settings.schema_name,
        result=result,
    )


async def run_initialize() -> None:
    settings = get_agent_persistence_settings()
    inspection = await read_only_inspection(settings)
    print_inspection(
        source=settings.database_url_source,
        schema_name=settings.schema_name,
        result=inspection,
    )
    confirmation = input("Type INITIALIZE to create/update the Agent storage tables: ").strip()
    if confirmation != "INITIALIZE":
        raise SystemExit("Cancelled; no database changes were requested.")

    async with await AsyncConnection.connect(
        settings.psycopg_url(),
        autocommit=True,
        row_factory=dict_row,
    ) as connection:
        public_before = await public_objects(connection)
        await connection.execute(
            sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(
                sql.Identifier(settings.schema_name)
            )
        )

    pool = await create_agent_pool(settings)
    try:
        checkpointer = AsyncPostgresSaver(pool)
        store = AsyncPostgresStore(pool)
        await checkpointer.setup()
        await store.setup()

        async with pool.connection() as connection:
            search_path_row = await (await connection.execute("SHOW search_path")).fetchone()
            search_path = search_path_row["search_path"]

        empty_thread_id = f"storage-verification-{uuid4()}"
        empty_checkpoint = await checkpointer.aget_tuple(
            {"configurable": {"thread_id": empty_thread_id}}
        )
        empty_store_items = await store.asearch(
            ("storage-verification", str(uuid4())),
            limit=1,
        )
    finally:
        await pool.close()

    async with await AsyncConnection.connect(
        settings.psycopg_url(),
        autocommit=True,
        row_factory=dict_row,
    ) as connection:
        public_after = await public_objects(connection)

    if empty_checkpoint is not None:
        raise RuntimeError("Checkpointer verification unexpectedly found data.")
    if empty_store_items:
        raise RuntimeError("Store verification unexpectedly found data.")
    if public_before != public_after:
        raise RuntimeError("Public schema objects changed during Agent initialization.")

    print("Agent checkpoint and store tables are initialized and verified:")
    print(f"  search_path: {search_path}")
    print("  Checkpointer empty read: passed")
    print("  Store empty query: passed")
    print("  public schema objects unchanged: passed")


async def main() -> None:
    args = parse_args()
    if args.check:
        await run_check()
    else:
        await run_initialize()


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(main())
