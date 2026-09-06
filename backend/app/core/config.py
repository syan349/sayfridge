from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """从 backend/.env 或进程环境中读取后端配置。"""

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # repr=False 防止调试时意外把完整连接串打印到日志。
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
            raise ValueError("数据库连接必须使用 postgresql+psycopg:// 驱动前缀")
        return value

    @field_validator("jwt_secret_key")
    @classmethod
    def require_strong_jwt_secret(cls, value: SecretStr) -> SecretStr:
        # HS256 的安全性直接依赖共享密钥，拒绝短密钥以避免弱配置启动。
        if len(value.get_secret_value()) < 32:
            raise ValueError("JWT_SECRET_KEY 至少需要 32 个字符")
        return value


@lru_cache
def get_settings() -> Settings:
    """缓存配置对象，避免每次创建会话时重复读取环境。"""

    return Settings()
