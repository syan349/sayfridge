"""Write a credential-free, read-only database acceptance evidence file."""
from __future__ import annotations

import argparse
from datetime import date
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from alembic.config import Config
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.config import get_settings  # noqa: E402
from app.db import models  # noqa: E402,F401
from app.db.database_acceptance import build_database_acceptance_evidence  # noqa: E402
from app.db.database_target import (  # noqa: E402
    DatabasePurpose,
    UnsafeDatabaseTarget,
    validate_disposable_database_url,
)


SCHEMA_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--environment",
        required=True,
        choices=("local", "ci", "e2e", "predeploy", "acceptance"),
    )
    parser.add_argument(
        "--initialized-at",
        required=True,
        type=date.fromisoformat,
        help="Operator-confirmed initialization date in YYYY-MM-DD form.",
    )
    parser.add_argument("--business-schema", default="public")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def _commit_sha() -> str:
    configured = os.getenv("APP_COMMIT_SHA") or os.getenv("VERCEL_GIT_COMMIT_SHA")
    if configured:
        return configured
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=BACKEND_DIR.parent,
        text=True,
        capture_output=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def _database_url(environment: str) -> str:
    if environment == "ci":
        variable = "TEST_DATABASE_URL"
        purpose = DatabasePurpose.TEST
    elif environment == "e2e":
        variable = "E2E_DATABASE_URL"
        purpose = DatabasePurpose.E2E
    else:
        return get_settings().database_url_direct.get_secret_value()

    value = os.getenv(variable)
    if not value:
        raise SystemExit(f"{variable} is required for {environment} evidence")
    try:
        validate_disposable_database_url(
            value,
            purpose,
            runtime_database_url=(
                os.getenv("DATABASE_URL_DIRECT") or os.getenv("DATABASE_URL")
                if environment == "e2e"
                else None
            ),
        )
    except UnsafeDatabaseTarget as error:
        raise SystemExit(str(error)) from error
    return value


def main() -> None:
    args = parse_args()
    if not SCHEMA_PATTERN.fullmatch(args.business_schema):
        raise SystemExit("--business-schema must be a lowercase PostgreSQL identifier")
    url = _database_url(args.environment)
    engine = create_engine(
        url,
        poolclass=NullPool,
        hide_parameters=True,
        connect_args={"connect_timeout": 15},
    )
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("SET TRANSACTION READ ONLY")
            evidence = build_database_acceptance_evidence(
                connection,
                url=engine.url,
                schema=args.business_schema,
                environment=args.environment,
                initialized_at=args.initialized_at,
                alembic_config=Config(str(BACKEND_DIR / "alembic.ini")),
                commit_sha=_commit_sha(),
            )
    finally:
        engine.dispose()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(f"Database acceptance evidence written to {args.output}")
    if not evidence["passed"]:
        raise SystemExit("Database migration or seed verification failed")


if __name__ == "__main__":
    main()
