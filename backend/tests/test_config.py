import pytest
from pydantic import SecretStr, ValidationError

from app.core.config import Settings


BASE_CONFIG = {
    "DATABASE_URL": "postgresql+psycopg://test_user@localhost/test",
    "DATABASE_URL_DIRECT": "postgresql+psycopg://test_user@localhost/test",
}


def test_jwt_secret_is_stored_as_secret_str() -> None:
    settings = Settings(
        **BASE_CONFIG,
        JWT_SECRET_KEY="s" * 40,
    )

    assert isinstance(settings.jwt_secret_key, SecretStr)
    assert "s" * 40 not in repr(settings)


def test_short_jwt_secret_is_rejected() -> None:
    with pytest.raises(ValidationError):
        Settings(**BASE_CONFIG, JWT_SECRET_KEY="too-short")
