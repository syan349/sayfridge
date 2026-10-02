"""Build credential-free, read-only evidence for a deployed business database."""
from __future__ import annotations

from dataclasses import asdict
from datetime import date, datetime, timezone
from typing import Any

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import bindparam, text
from sqlalchemy.engine import Connection, URL

from app.core.category_catalog import CATEGORIES, category_seed_version
from app.db.base import Base
from app.db.schema_verification import verify_schema


def _category_rows(connection: Connection, schema: str) -> list[dict[str, Any]]:
    quoted = connection.dialect.identifier_preparer.quote(schema)
    expected = tuple(row["normalized_name"] for row in CATEGORIES)
    rows = connection.execute(
        text(
            f"SELECT name, normalized_name, sort_order "
            f"FROM {quoted}.item_category "
            "WHERE normalized_name IN :names AND status = 'ACTIVE' AND owner_user_id IS NULL "
            "ORDER BY sort_order, normalized_name"
        ).bindparams(bindparam("names", expanding=True)),
        {"names": expected},
    ).mappings()
    return [dict(row) for row in rows]


def build_database_acceptance_evidence(
    connection: Connection,
    *,
    url: URL,
    schema: str,
    environment: str,
    initialized_at: date,
    alembic_config: Config,
    commit_sha: str,
) -> dict[str, Any]:
    """Verify the schema and seed, then return a serializable evidence record."""

    quoted = connection.dialect.identifier_preparer.quote(schema)
    report = verify_schema(connection, Base.metadata, schema=schema)
    current_revisions = list(
        connection.scalars(text(f"SELECT version_num FROM {quoted}.alembic_version"))
    )
    expected_heads = list(ScriptDirectory.from_config(alembic_config).get_heads())
    actual_categories = _category_rows(connection, schema)
    expected_by_name = {row["normalized_name"]: row for row in CATEGORIES}
    actual_by_name = {row["normalized_name"]: row for row in actual_categories}
    missing = sorted(set(expected_by_name) - set(actual_by_name))
    mismatched = sorted(
        name
        for name in set(expected_by_name) & set(actual_by_name)
        if any(
            actual_by_name[name][field] != expected_by_name[name][field]
            for field in ("name", "sort_order")
        )
    )
    migration_matches = sorted(current_revisions) == sorted(expected_heads)
    seed_matches = not missing and not mismatched
    return {
        "evidence_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "environment": environment,
        "initialized_at": initialized_at.isoformat(),
        "application_commit": commit_sha,
        "target": {
            "host": url.host or "unknown",
            "port": url.port,
            "database": url.database or "unknown",
            "schema": schema,
        },
        "migration": {
            "current_revisions": sorted(current_revisions),
            "expected_heads": sorted(expected_heads),
            "matches": migration_matches,
        },
        "category_seed": {
            "version": category_seed_version(),
            "expected_count": len(CATEGORIES),
            "present_count": len(actual_categories),
            "missing": missing,
            "mismatched": mismatched,
            "matches": seed_matches,
        },
        "schema_verification": {"passed": True, **asdict(report)},
        "passed": migration_matches and seed_matches,
    }
