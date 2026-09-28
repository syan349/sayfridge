"""Database-target guards for disposable test and E2E environments."""
from __future__ import annotations

from enum import StrEnum

from sqlalchemy.engine import URL, make_url


class DatabasePurpose(StrEnum):
    TEST = "test"
    E2E = "e2e"


class UnsafeDatabaseTarget(ValueError):
    """Raised before a disposable workload can reach a shared database."""


def _identity(url: URL) -> tuple[str, int | None, str]:
    return ((url.host or "").lower(), url.port, (url.database or "").lower())


def validate_disposable_database_url(
    value: str,
    purpose: DatabasePurpose,
    *,
    runtime_database_url: str | None = None,
) -> URL:
    """Return a parsed URL only when it is visibly isolated for its purpose.

    Credentials and full URLs are deliberately omitted from every error message.
    """

    try:
        url = make_url(value)
    except Exception as error:
        raise UnsafeDatabaseTarget("Database URL is invalid") from error

    expected_suffix = "_test" if purpose is DatabasePurpose.TEST else "_e2e"
    if url.drivername != "postgresql+psycopg":
        raise UnsafeDatabaseTarget(
            f"{purpose.value} database must use postgresql+psycopg"
        )
    if not (url.database or "").lower().endswith(expected_suffix):
        raise UnsafeDatabaseTarget(
            f"{purpose.value} database name must end in {expected_suffix}"
        )
    if "pooler" in (url.host or "").lower() or url.port == 6543:
        raise UnsafeDatabaseTarget(
            f"{purpose.value} database must use a direct PostgreSQL endpoint"
        )

    if runtime_database_url:
        try:
            runtime_url = make_url(runtime_database_url)
        except Exception as error:
            raise UnsafeDatabaseTarget("Runtime database URL is invalid") from error
        if _identity(url) == _identity(runtime_url):
            raise UnsafeDatabaseTarget(
                f"{purpose.value} database must not be the runtime/predeploy database"
            )
    return url
