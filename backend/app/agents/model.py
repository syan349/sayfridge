"""Lazy configuration and construction of the Agent chat model."""
from functools import lru_cache
from pathlib import Path

from langchain_openai import ChatOpenAI
from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from app.agents.context_budget import Budget, BudgetModel


BACKEND_DIR = Path(__file__).resolve().parents[2]


class AgentModelSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        hide_input_in_errors=True,
    )

    model_name: str = Field(alias="AGENT_MODEL")
    api_base: str = Field(alias="AGENT_API_BASE")
    api_key: SecretStr = Field(alias="AGENT_API_KEY", repr=False)
    timeout_seconds: float = Field(default=60, alias="AGENT_TIMEOUT_SECONDS", gt=0, le=600)
    max_retries: int = Field(default=2, alias="AGENT_MAX_RETRIES", ge=0, le=10)
    context_trigger: int = Field(default=80000, alias="AGENT_CONTEXT_TRIGGER")
    context_target: int = Field(default=40000, alias="AGENT_CONTEXT_TARGET")
    context_limit: int = Field(default=160000, alias="AGENT_CONTEXT_LIMIT")
    model_context_limit: int = Field(default=160000, alias="AGENT_MODEL_CONTEXT_LIMIT")
    output_tokens: int = Field(default=8000, alias="AGENT_OUTPUT_TOKENS")
    summary_timeout_seconds: float = Field(default=45, alias="AGENT_SUMMARY_TIMEOUT_SECONDS", gt=0, le=120)

    @field_validator("model_name", "api_base")
    @classmethod
    def require_nonempty(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("Agent model name and API base must not be empty")
        return value

    @field_validator("api_key")
    @classmethod
    def require_api_key(cls, value: SecretStr) -> SecretStr:
        if not value.get_secret_value().strip():
            raise ValueError("AGENT_API_KEY must not be empty")
        return value


@lru_cache
def get_agent_model_settings() -> AgentModelSettings:
    return AgentModelSettings()


def create_agent_model() -> BudgetModel:
    settings = get_agent_model_settings()
    budget = Budget(trigger=settings.context_trigger, target=settings.context_target,
                    limit=settings.context_limit, model_limit=settings.model_context_limit,
                    output=settings.output_tokens)
    model = BudgetModel(ChatOpenAI(
        model=settings.model_name,
        base_url=settings.api_base,
        api_key=settings.api_key,
        timeout=settings.timeout_seconds,
        max_retries=settings.max_retries,
        streaming=True,
        max_tokens=settings.output_tokens,
    ), budget)
    model.summary_timeout_seconds = settings.summary_timeout_seconds
    return model
