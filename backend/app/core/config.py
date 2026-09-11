from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Read backend settings from backend/.env or process environment variables."""

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # repr=False prevents full connection strings from appearing in debug representations.
    database_url: SecretStr = Field(alias="DATABASE_URL", repr=False)
    database_url_direct: SecretStr = Field(alias="DATABASE_URL_DIRECT", repr=False)
    jwt_secret_key: SecretStr = Field(alias="JWT_SECRET_KEY", repr=False)
    access_token_expire_minutes: int = Field(
        default=15,
        alias="ACCESS_TOKEN_EXPIRE_MINUTES",
        ge=1,
        le=1440,
    )

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


@lru_cache
def get_settings() -> Settings:
    """Cache settings to avoid rereading the environment for each new session."""

    return Settings()
