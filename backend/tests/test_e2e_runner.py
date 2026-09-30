"""Safety checks for the disposable browser-test runner (no database required)."""
import pytest
from app.db.database_target import UnsafeDatabaseTarget
from scripts.run_e2e import database_target

@pytest.mark.parametrize("value", [
    None,
    "postgresql+psycopg://user:secret@127.0.0.1/sayfridge",
    "postgresql+psycopg://user:secret@cloud.example.com/sayfridge_e2e",
    "postgresql+psycopg://user:secret@127.0.0.1/sayfridge_e2e?host=cloud.example.com",
    "postgresql+psycopg://user:secret@127.0.0.1/sayfridge_e2e?dbname=production",
    "postgresql+psycopg://user:secret@127.0.0.1/sayfridge_e2e?options=-csearch_path=public",
])
def test_rejects_shared_or_overridden_targets_without_exposing_credentials(value):
    with pytest.raises(UnsafeDatabaseTarget) as error:
        database_target(value)
    assert "secret" not in str(error.value)


def test_accepts_explicit_local_disposable_database():
    url = database_target("postgresql+psycopg://user:secret@127.0.0.1:5433/sayfridge_e2e")
    assert url.database == "sayfridge_e2e"
    assert url.port == 5433
