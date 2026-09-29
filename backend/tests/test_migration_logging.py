"""Migrations must preserve application logging for subsequent requests."""
import os
from pathlib import Path
import subprocess
import sys

import pytest


@pytest.mark.ci
def test_safe_error_logging_survives_migration_configuration():
    # Isolate Alembic's global logging configuration from pytest's own handlers.
    # Offline SQL generation exercises the real migration environment without a DB.
    script = """
import io
from alembic import command
from alembic.config import Config
from app.middleware.safe_errors import logger

assert not logger.disabled
config = Config('alembic.ini', output_buffer=io.StringIO())
command.upgrade(config, 'head', sql=True)
assert not logger.disabled, 'Alembic disabled the application error logger'

import pytest
raise SystemExit(pytest.main(['-q', 'tests/test_safe_errors.py', '--strict-markers']))
"""
    result = subprocess.run(
        [sys.executable, '-c', script],
        cwd=Path(__file__).resolve().parents[1],
        env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'},
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
