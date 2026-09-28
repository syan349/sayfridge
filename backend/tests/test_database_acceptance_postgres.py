"""Database acceptance evidence is complete and contains no credentials."""
from datetime import date
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy.orm import Session

from app.core.category_catalog import CATEGORIES, category_seed_version
from app.db.database_acceptance import build_database_acceptance_evidence
from app.db.models import ItemCategory


pytestmark = [
    pytest.mark.postgres,
    pytest.mark.ci,
    pytest.mark.database_acceptance,
]


def test_database_acceptance_evidence_records_revision_seed_and_structure(database):
    url, schema, engine = database
    with Session(engine) as session:
        session.add_all(
            ItemCategory(
                name=row["name"],
                normalized_name=row["normalized_name"],
                status="ACTIVE",
                sort_order=row["sort_order"],
            )
            for row in CATEGORIES
        )
        session.commit()

    backend = Path(__file__).resolve().parents[1]
    with engine.connect() as connection:
        evidence = build_database_acceptance_evidence(
            connection,
            url=url,
            schema=schema,
            environment="ci",
            initialized_at=date(2026, 9, 28),
            alembic_config=Config(str(backend / "alembic.ini")),
            commit_sha="test-commit",
        )

    assert evidence["passed"] is True
    assert evidence["migration"]["matches"] is True
    assert evidence["category_seed"] == {
        "version": category_seed_version(),
        "expected_count": 25,
        "present_count": 25,
        "missing": [],
        "mismatched": [],
        "matches": True,
    }
    assert evidence["schema_verification"]["passed"] is True
    assert evidence["schema_verification"]["tables"] > 0
    assert evidence["initialized_at"] == "2026-09-28"
    assert evidence["application_commit"] == "test-commit"
    rendered = str(evidence)
    assert "password" not in rendered.lower()
    assert "secret" not in rendered.lower()
