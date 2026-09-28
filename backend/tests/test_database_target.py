"""Disposable database guards reject shared and ambiguous targets."""
import pytest

from app.db.database_target import (
    DatabasePurpose,
    UnsafeDatabaseTarget,
    validate_disposable_database_url,
)


pytestmark = pytest.mark.ci


def test_test_and_e2e_database_names_are_purpose_specific():
    test_url = validate_disposable_database_url(
        "postgresql+psycopg://user:secret@localhost/sayfridge_test",
        DatabasePurpose.TEST,
    )
    e2e_url = validate_disposable_database_url(
        "postgresql+psycopg://user:secret@localhost/sayfridge_e2e",
        DatabasePurpose.E2E,
    )
    assert test_url.database == "sayfridge_test"
    assert e2e_url.database == "sayfridge_e2e"


@pytest.mark.parametrize(
    "value,purpose",
    [
        ("postgresql+psycopg://user:secret@localhost/sayfridge", DatabasePurpose.TEST),
        ("postgresql+psycopg://user:secret@localhost/sayfridge_test", DatabasePurpose.E2E),
        ("postgresql+asyncpg://user:secret@localhost/sayfridge_test", DatabasePurpose.TEST),
        ("postgresql+psycopg://user:secret@db-pooler.example/sayfridge_e2e", DatabasePurpose.E2E),
        ("postgresql+psycopg://user:secret@localhost:6543/sayfridge_test", DatabasePurpose.TEST),
    ],
)
def test_disposable_database_rejects_ambiguous_or_pooled_targets(value, purpose):
    with pytest.raises(UnsafeDatabaseTarget):
        validate_disposable_database_url(value, purpose)


def test_e2e_database_cannot_equal_runtime_database():
    value = "postgresql+psycopg://e2e:secret@direct.example/sayfridge_e2e"
    runtime = "postgresql+psycopg://app:other@direct.example/sayfridge_e2e"
    with pytest.raises(UnsafeDatabaseTarget, match="runtime/predeploy"):
        validate_disposable_database_url(
            value,
            DatabasePurpose.E2E,
            runtime_database_url=runtime,
        )
