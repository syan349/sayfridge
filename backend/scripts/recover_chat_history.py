"""Preview/recover observed legacy public messages; default is read-only dry-run."""
import argparse
import asyncio
import json
import sys
from pathlib import Path
from uuid import UUID

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import create_engine, text, make_url
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver

from app.core.config import get_settings
from app.agents.persistence import get_agent_persistence_settings, create_agent_pool
from app.services.conversation_history import user_threads, recover_messages, write_messages, bind_primary


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-id", type=UUID)
    parser.add_argument("--source-thread", type=UUID, help="Requires --user-id; other threads are not read")
    parser.add_argument("--apply", action="store_true", help="Explicitly write messages after target confirmation")
    parser.add_argument("--dry-run", action="store_true", help="Read-only preview (the default)")
    args = parser.parse_args()
    if args.source_thread and not args.user_id:
        parser.error("--source-thread requires --user-id")
    if args.apply and args.dry_run:
        parser.error("Choose --apply or --dry-run")
    return args


async def run(args):
    settings, agent = get_settings(), get_agent_persistence_settings()
    url = settings.database_url_direct.get_secret_value()
    target = make_url(url)
    engine = create_engine(url, hide_parameters=True, connect_args={"connect_timeout": 15})
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("SET TRANSACTION READ ONLY")
            revision = connection.scalar(text("SELECT version_num FROM alembic_version"))
            business_schema = connection.scalar(text("SELECT current_schema()"))
            users = [args.user_id] if args.user_id else list(connection.scalars(text('SELECT id FROM "user"')))
            print(json.dumps({"mode": "apply" if args.apply else "dry-run", "host": target.host,
                "database": target.database, "business_schema": business_schema, "agent_schema": agent.schema_name,
                "revision": revision, "users": len(users)}))
    finally:
        engine.dispose()
    if args.apply:
        if revision != "a261002_chat":
            raise ValueError("Apply the reviewed chat migration before backfill")
        if input("Type BACKFILL to write recovered public messages to this target: ").strip() != "BACKFILL":
            print("Cancelled; no writes")
            return
    pool = await create_agent_pool(agent)
    async_engine = create_async_engine(url, hide_parameters=True)
    sessions = async_sessionmaker(async_engine, expire_on_commit=False)
    try:
        saver = AsyncPostgresSaver(pool)
        counts = {"threads": 0, "recoverable_messages": 0, "written_candidates": 0}
        for user_id in users:
            threads = await user_threads(saver, user_id, pool=pool)
            selected = [t for t in threads if not args.source_thread or t[0] == args.source_thread]
            if args.apply and selected:
                async with sessions() as session:
                    # Bind from all threads even when this recovery is source-limited.
                    await bind_primary(session, user_id, threads)
            for cid, _ in selected:
                records = await recover_messages(saver, user_id, cid)
                counts["threads"] += 1
                counts["recoverable_messages"] += len(records)
                if args.apply and records:
                    async with sessions() as session:
                        await write_messages(session, user_id, cid, records, complete=False)
                    counts["written_candidates"] += len(records)
        print(json.dumps({**counts, "history_complete": False,
            "note": "Observed public text only; missing messages/confirmations are not invented. Existing IDs deduplicate repeated runs."}))
    finally:
        await async_engine.dispose()
        await pool.close()


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    try:
        asyncio.run(run(arguments()))
    except Exception as exc:
        # Connection exceptions may contain secret-bearing URLs.
        print(f"Recovery stopped ({type(exc).__name__}); no completion is assumed", file=sys.stderr)
        raise SystemExit(1) from None
