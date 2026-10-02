"""Shared authentication test helpers backed by real PostgreSQL sessions."""
import asyncio
from datetime import datetime, timezone
import uuid
import os
import json
from pathlib import Path

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool

from app.core.security import hash_password
from app.db.models import User
from app.db.session import get_db_session
from app.main import app

VALID_PASSWORD = "p" * 16


def make_user(
    *,
    email: str = "user@example.com",
    password: str = VALID_PASSWORD,
    status: str = "ACTIVE",
    role: str = "USER",
    auth_provider: str = "LOCAL",
) -> User:
    now = datetime.now(timezone.utc)
    return User(
        id=uuid.uuid4(),
        email=email,
        password_hash=hash_password(password),
        auth_provider=auth_provider,
        role=role,
        status=status,
        voice_limit_seconds=0,
        voice_used_seconds=0,
        created_at=now,
        updated_at=now,
    )


def seed_users(database, *users):
    """Commit fixture users so separate HTTP request sessions can read them."""
    with Session(database[2], expire_on_commit=False) as session:
        session.add_all(users)
        session.commit()
    return database


def read_users(database):
    """Read persisted users through SQL, separate from the request session."""
    with Session(database[2]) as session:
        return list(session.scalars(select(User)))


async def exercise(database, scenario):
    url, schema, _ = database
    engine = create_async_engine(url, poolclass=NullPool, hide_parameters=True,
                                 connect_args={"options": f"-csearch_path={schema}", "connect_timeout": 15})
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async def override():
        async with sessions() as session:
            yield session
    previous = app.dependency_overrides.get(get_db_session)
    app.dependency_overrides[get_db_session] = override
    try:
        async def capture(response):
            target = os.getenv("AGENT_CLIENT_CAPTURE_FILE")
            path = response.request.url.path
            capture_path = path.startswith("/api/v1/agent/") or (
                path.startswith("/api/v1/inventory-items/") and path.endswith("/discard"))
            if not target or not capture_path:
                return
            await response.aread()
            payload = json.loads(response.request.content) if response.request.content else None
            row = {"path": response.request.url.path, "method": response.request.method,
                   "request": payload, "status": response.status_code,
                   "content_type": response.headers.get("content-type", ""), "body": response.text}
            with Path(target).open("a", encoding="utf-8") as output:
                output.write(json.dumps(row, ensure_ascii=False) + "\n")
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test",
                event_hooks={"response": [capture]}) as client:
            return await scenario(client, sessions)
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db_session, None)
        else:
            app.dependency_overrides[get_db_session] = previous
        await engine.dispose()


def request(database, method, path, *, json=None, headers=None):
    """Run the real ASGI app with a request-scoped PostgreSQL session."""
    async def scenario(client, sessions):
        return await client.request(method, path, json=json, headers=headers)

    return asyncio.run(exercise(database, scenario))
