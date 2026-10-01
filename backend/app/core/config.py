from functools import lru_cache
from pathlib import Path
import re
from urllib.parse import urlsplit

from pydantic import AliasChoices, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Read backend settings from backend/.env or process environment variables."""

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        hide_input_in_errors=True,
    )

    # repr=False prevents full connection strings from appearing in debug representations.
    app_version: str = Field(default="0.1.0", alias="APP_VERSION")
    app_commit_sha: str | None = Field(
        default=None,
        validation_alias=AliasChoices("APP_COMMIT_SHA", "VERCEL_GIT_COMMIT_SHA"),
    )
    database_url: SecretStr = Field(alias="DATABASE_URL", repr=False)
    database_url_direct: SecretStr = Field(alias="DATABASE_URL_DIRECT", repr=False)
    jwt_secret_key: SecretStr = Field(alias="JWT_SECRET_KEY", repr=False)
    access_token_expire_minutes: int = Field(
        default=15,
        alias="ACCESS_TOKEN_EXPIRE_MINUTES",
        ge=1,
        le=1440,
    )
    refresh_token_idle_days: int = Field(default=30, alias="REFRESH_TOKEN_IDLE_DAYS", ge=1, le=90)
    refresh_token_absolute_days: int = Field(default=90, alias="REFRESH_TOKEN_ABSOLUTE_DAYS", ge=1, le=365)
    login_rate_limit_attempts: int = Field(
        default=5,
        alias="LOGIN_RATE_LIMIT_ATTEMPTS",
        ge=1,
        le=100,
    )
    login_rate_limit_window_seconds: int = Field(
        default=60,
        alias="LOGIN_RATE_LIMIT_WINDOW_SECONDS",
        ge=1,
        le=3600,
    )
    cors_origins: list[str] = Field(default_factory=list, alias="CORS_ORIGINS")

    @field_validator("app_version")
    @classmethod
    def require_safe_app_version(cls, value: str) -> str:
        value = value.strip()
        if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._+\-]{0,63}", value):
            raise ValueError("APP_VERSION must be a short release identifier")
        return value

    @field_validator("app_commit_sha")
    @classmethod
    def require_git_commit_sha(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        value = value.strip().lower()
        if not re.fullmatch(r"[0-9a-f]{7,40}", value):
            raise ValueError("APP_COMMIT_SHA must contain 7 to 40 hexadecimal characters")
        return value

    @field_validator("database_url", "database_url_direct")
    @classmethod
    def require_psycopg_driver(cls, value: SecretStr) -> SecretStr:
        if not value.get_secret_value().startswith("postgresql+psycopg://"):
            raise ValueError("Database URLs must use the postgresql+psycopg:// driver prefix")
        return value

    @field_validator("jwt_secret_key")
    @classmethod
    def require_strong_jwt_secret(cls, value: SecretStr) -> SecretStr:
        # HS256 security depends on the shared secret; reject short secrets to prevent startup with weak settings.
        if len(value.get_secret_value()) < 32:
            raise ValueError("JWT_SECRET_KEY must contain at least 32 characters")
        return value

    @field_validator("cors_origins")
    @classmethod
    def require_explicit_http_origins(cls, values: list[str]) -> list[str]:
        """Accept browser origins only; paths and wildcard access are not valid origins."""

        normalized: list[str] = []
        for value in values:
            origin = value.strip().rstrip("/")
            parsed = urlsplit(origin)
            if (
                origin == "*"
                or parsed.scheme not in {"http", "https"}
                or not parsed.netloc
                or parsed.path
                or parsed.query
                or parsed.fragment
                or parsed.username is not None
                or parsed.password is not None
            ):
                raise ValueError(
                    "CORS_ORIGINS entries must be explicit HTTP(S) origins without paths"
                )
            if origin not in normalized:
                normalized.append(origin)
        return normalized


@lru_cache
def get_settings() -> Settings:
    """Cache settings to avoid rereading the environment for each new session."""

    return Settings()
