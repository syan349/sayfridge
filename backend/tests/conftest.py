import os
import sys
import asyncio
from pathlib import Path
from dotenv import dotenv_values

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())


# Override all required settings in the test process without relying on or modifying the local .env.
os.environ["DATABASE_URL"] = (
    "postgresql+psycopg://test_user@localhost/sayfridge_test"
)
os.environ["DATABASE_URL_DIRECT"] = (
    "postgresql+psycopg://test_user@localhost/sayfridge_test"
)
os.environ["JWT_SECRET_KEY"] = "s" * 40
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "15"
os.environ["CORS_ORIGINS"] = '["http://localhost:5173"]'


# Database tests require an explicit, separate test connection; never fall back to the application .env.
test_config = dotenv_values(Path(__file__).resolve().parents[1] / ".env.test")
if test_config.get("TEST_DATABASE_URL"):
    os.environ.setdefault("TEST_DATABASE_URL", test_config["TEST_DATABASE_URL"])


import uuid

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool

from app.main import app
from app.db.database_target import (
    DatabasePurpose,
    UnsafeDatabaseTarget,
    validate_disposable_database_url,
)
from app.db.session import get_db_session
from app.services.inventory_expiry import estimate_shelf_lives as REAL_EXPIRY_ESTIMATOR


@pytest.fixture(scope="session")
def live_runner():
    # Both live Agent modules share the loop used by the cached model HTTP client.
    with asyncio.Runner() as runner:
        yield runner


# Each database test owns a migrated schema, including committed test data.
@pytest.fixture(autouse=True)
def isolated_login_attempts():
    from app.core.login_rate_limit import login_rate_limiter
    with login_rate_limiter._lock:
        login_rate_limiter._attempts.clear()
    yield
    with login_rate_limiter._lock:
        login_rate_limiter._attempts.clear()


@pytest.fixture(autouse=True)
def isolated_expiry_model(request, monkeypatch):
    """Only explicitly opted-in live tests can spend model tokens for enrichment."""
    if os.getenv("AGENT_LIVE_MODEL") == "1" and "live" in request.node.module.__name__:
        return
    from app.services import inventory_expiry
    async def unavailable(items):
        return {}
    monkeypatch.setattr(inventory_expiry, "estimate_shelf_lives", unavailable)


@pytest.fixture
def database():
    value = os.environ.get("TEST_DATABASE_URL")
    if not value:
        pytest.fail("Set TEST_DATABASE_URL in the environment or backend/.env.test; "
                    "use -m 'not postgres' to run only database-free tests", pytrace=False)
    try:
        url = validate_disposable_database_url(value, DatabasePurpose.TEST)
    except UnsafeDatabaseTarget as error:
        pytest.fail(str(error), pytrace=False)
    schema = "auth_test_" + uuid.uuid4().hex
    control = create_engine(url, poolclass=NullPool, hide_parameters=True,
                            connect_args={"connect_timeout": 15})
    with control.begin() as conn:
        conn.execute(text(f'CREATE SCHEMA "{schema}"'))
    scoped = create_engine(url, poolclass=NullPool, hide_parameters=True,
                           connect_args={"options": f"-csearch_path={schema}", "connect_timeout": 15})
    try:
        with scoped.begin() as conn:
            cfg = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
            cfg.attributes["connection"] = conn
            command.upgrade(cfg, "head")
        yield url, schema, scoped
    finally:
        app.dependency_overrides.pop(get_db_session, None)
        scoped.dispose()
        with control.begin() as conn:
            conn.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        control.dispose()
