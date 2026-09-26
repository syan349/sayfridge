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


def test_cors_origins_default_to_closed(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("CORS_ORIGINS", raising=False)
    settings = Settings(
        **BASE_CONFIG,
        JWT_SECRET_KEY="s" * 40,
        _env_file=None,
    )

    assert settings.cors_origins == []


def test_cors_origins_are_normalized_and_deduplicated() -> None:
    settings = Settings(
        **BASE_CONFIG,
        JWT_SECRET_KEY="s" * 40,
        CORS_ORIGINS=[
            " http://localhost:5173/ ",
            "http://localhost:5173",
            "https://web.example.com",
        ],
    )

    assert settings.cors_origins == [
        "http://localhost:5173",
        "https://web.example.com",
    ]


@pytest.mark.parametrize("origin", ["*", "ftp://localhost:5173", "https://example.com/app"])
def test_invalid_cors_origin_is_rejected(origin: str) -> None:
    with pytest.raises(ValidationError):
        Settings(
            **BASE_CONFIG,
            JWT_SECRET_KEY="s" * 40,
            CORS_ORIGINS=[origin],
        )
