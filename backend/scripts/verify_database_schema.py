"""Read-only verification of the deployed PostgreSQL business schema."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.config import get_settings  # noqa: E402
from app.db import models  # noqa: E402,F401  # Register ORM metadata.
from app.db.base import Base  # noqa: E402
from app.db.schema_verification import verify_schema  # noqa: E402


SCHEMA_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--business-schema",
        default="public",
        help="Business schema to inspect; production uses public.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not SCHEMA_PATTERN.fullmatch(args.business_schema):
        raise SystemExit(
            "--business-schema must be a lowercase PostgreSQL identifier"
        )

    settings = get_settings()
    engine = create_engine(
        settings.database_url_direct.get_secret_value(),
        poolclass=NullPool,
        hide_parameters=True,
        connect_args={"connect_timeout": 15},
    )
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("SET TRANSACTION READ ONLY")
            report = verify_schema(
                connection,
                Base.metadata,
                schema=args.business_schema,
            )
    finally:
        engine.dispose()

    print("Business schema verification passed (read-only):")
    print(f"  schema: {args.business_schema}")
    print(f"  tables: {report.tables}")
    print(f"  columns: {report.columns}")
    print(f"  foreign keys: {report.foreign_keys}")
    constraint_count = (
        report.primary_keys
        + report.unique_constraints
        + report.check_constraints
    )
    print(f"  constraints: {constraint_count}")
    print(f"  indexes: {report.indexes}")


if __name__ == "__main__":
    main()
