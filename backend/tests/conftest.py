import os
from pathlib import Path
from dotenv import dotenv_values


# Override all required settings in the test process without relying on or modifying the local .env.
os.environ["DATABASE_URL"] = (
    "postgresql+psycopg://test_user@localhost/sayfridge_test"
)
os.environ["DATABASE_URL_DIRECT"] = (
    "postgresql+psycopg://test_user@localhost/sayfridge_test"
)
os.environ["JWT_SECRET_KEY"] = "s" * 40
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "15"


# Database tests require an explicit, separate test connection; never fall back to the application .env.
test_config = dotenv_values(Path(__file__).resolve().parents[1] / ".env.test")
if test_config.get("TEST_DATABASE_URL"):
    os.environ.setdefault("TEST_DATABASE_URL", test_config["TEST_DATABASE_URL"])


import uuid

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.pool import NullPool

from app.main import app
from app.db.session import get_db_session


# Each database test owns a migrated schema, including committed test data.
@pytest.fixture
def database():
    value = os.environ.get("TEST_DATABASE_URL")
    if not value:
        pytest.fail("Set TEST_DATABASE_URL in the environment or backend/.env.test; "
                    "use -m 'not postgres' to run only database-free tests", pytrace=False)
    url = make_url(value)
    if url.drivername != "postgresql+psycopg" or not (url.database or "").endswith("_test"):
        pytest.fail("TEST_DATABASE_URL must use psycopg and an isolated database ending in _test")
    if "-pooler" in (url.host or ""):
        pytest.fail("PostgreSQL integration tests require a direct connection")
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
