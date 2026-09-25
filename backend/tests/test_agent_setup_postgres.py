"""Existing-database setup operates only on the fixture's disposable schema."""
import os
from pathlib import Path
import subprocess
import sys

import pytest
from sqlalchemy import inspect, text

pytestmark = pytest.mark.postgres


def test_receipt_setup_check_create_and_incompatible_schema(database):
    url, schema, engine = database
    env = dict(os.environ)
    env["DATABASE_URL_DIRECT"] = url.set(query={**dict(url.query), "options": f"-csearch_path={schema}"}).render_as_string(hide_password=False)
    backend = Path(__file__).resolve().parents[1]
    def run(mode, answer=None):
        return subprocess.run([sys.executable, "scripts/setup_agent_actions.py", mode],
            cwd=backend, env=env, input=answer, text=True, capture_output=True, timeout=30)
    assert run("--check").returncode == 0
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE agent_inventory_action"))
    assert run("--check").returncode == 1
    assert run("--initialize", "CANCEL\n").returncode == 0
    assert not inspect(engine).has_table("agent_inventory_action")
    assert run("--initialize", "INITIALIZE\n").returncode == 0
    assert run("--check").returncode == 0
    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE agent_inventory_action ALTER COLUMN action DROP NOT NULL"))
    assert run("--check").returncode == 1
