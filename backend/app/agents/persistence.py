"""Lazy Agent PostgreSQL resources and application-lifetime cleanup."""
from __future__ import annotations

import asyncio
import re
import logging
from time import perf_counter
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from langgraph.store.postgres import AsyncPostgresStore
from psycopg import AsyncConnection, sql
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool
from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_DIR = Path(__file__).resolve().parents[2]
SCHEMA_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*$")
logger = logging.getLogger(__name__)


class MeasuredPostgresSaver(AsyncPostgresSaver):
    """Pinned saver behavior with content-free timing/serialized-byte metrics."""

    def _dump_blobs(self, *args, **kwargs):
        rows = super()._dump_blobs(*args, **kwargs)
        logger.info("agent_checkpoint_payload kind=blobs rows=%s bytes=%s", len(rows), sum(len(r[-1] or b"") for r in rows))
        return rows

    def _dump_writes(self, *args, **kwargs):
        rows = super()._dump_writes(*args, **kwargs)
        logger.info("agent_checkpoint_payload kind=writes rows=%s bytes=%s", len(rows), sum(len(r[-1]) for r in rows))
        return rows

    async def _measured(self, operation, call):
        start, outcome = perf_counter(), "ok"
        try:
            return await call
        except BaseException:
            outcome = "failed"
            raise
        finally:
            logger.info("agent_checkpoint_io operation=%s outcome=%s elapsed_ms=%.3f",
                        operation, outcome, (perf_counter() - start) * 1000)

    async def aput(self, *args, **kwargs):
        return await self._measured("checkpoint_write", super().aput(*args, **kwargs))

    async def aput_writes(self, *args, **kwargs):
        return await self._measured("pending_write", super().aput_writes(*args, **kwargs))

    async def aget_tuple(self, *args, **kwargs):
        return await self._measured("checkpoint_read", super().aget_tuple(*args, **kwargs))

    async def aget_delta_channel_history(self, *args, **kwargs):
        return await self._measured("delta_read", super().aget_delta_channel_history(*args, **kwargs))


class AgentPersistenceSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    database_url: SecretStr | None = Field(
        default=None,
        alias="AGENT_DATABASE_URL",
        repr=False,
    )
    database_url_direct: SecretStr = Field(alias="DATABASE_URL_DIRECT", repr=False)
    schema_name: str = Field(default="agent", alias="AGENT_DATABASE_SCHEMA")
    pool_min_size: int = Field(default=1, alias="AGENT_DB_POOL_MIN_SIZE", ge=1, le=20)
    pool_max_size: int = Field(default=4, alias="AGENT_DB_POOL_MAX_SIZE", ge=1, le=20)
    pool_timeout_seconds: float = Field(
        default=10,
        alias="AGENT_DB_POOL_TIMEOUT_SECONDS",
        gt=0,
        le=120,
    )
    recursion_limit: int = Field(default=12, alias="AGENT_RECURSION_LIMIT", ge=3, le=50)
    workflow_step_limit: int = Field(default=128, alias="AGENT_WORKFLOW_STEP_LIMIT", ge=16, le=512)
    delta_snapshot_frequency: int = Field(default=50, alias="AGENT_DELTA_SNAPSHOT_FREQUENCY", ge=1, le=1000)

    @field_validator("database_url", mode="before")
    @classmethod
    def empty_agent_database_url_uses_default(cls, value: object) -> object:
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @field_validator("database_url", "database_url_direct")
    @classmethod
    def validate_database_url(cls, value: SecretStr | None) -> SecretStr | None:
        if value is None:
            return None
        url = value.get_secret_value()
        if not url.startswith(("postgresql://", "postgres://", "postgresql+psycopg://")):
            raise ValueError("Agent database URLs must be PostgreSQL connection URLs")
        return value

    @field_validator("schema_name")
    @classmethod
    def validate_schema_name(cls, value: str) -> str:
        value = value.strip()
        if not SCHEMA_PATTERN.fullmatch(value):
            raise ValueError("AGENT_DATABASE_SCHEMA must be a lowercase PostgreSQL identifier")
        return value

    @model_validator(mode="after")
    def validate_pool_sizes(self):
        if self.pool_min_size > self.pool_max_size:
            raise ValueError("AGENT_DB_POOL_MIN_SIZE must not exceed AGENT_DB_POOL_MAX_SIZE")
        return self

    def psycopg_url(self) -> str:
        configured_url = self.database_url or self.database_url_direct
        return configured_url.get_secret_value().replace(
            "postgresql+psycopg://", "postgresql://", 1,
        )

    @property
    def database_url_source(self) -> str:
        return "AGENT_DATABASE_URL" if self.database_url is not None else "DATABASE_URL_DIRECT"


@lru_cache
def get_agent_persistence_settings() -> AgentPersistenceSettings:
    return AgentPersistenceSettings()


async def create_agent_pool(settings: AgentPersistenceSettings) -> AsyncConnectionPool:
    async def configure_connection(connection: AsyncConnection) -> None:
        await connection.execute(
            sql.SQL("SET search_path TO {}").format(sql.Identifier(settings.schema_name))
        )

    pool = AsyncConnectionPool(
        conninfo=settings.psycopg_url(),
        min_size=settings.pool_min_size,
        max_size=settings.pool_max_size,
        timeout=settings.pool_timeout_seconds,
        kwargs={"autocommit": True, "prepare_threshold": 0, "row_factory": dict_row},
        configure=configure_connection,
        open=False,
        name="sayfridge-agent",
    )
    try:
        await pool.open(wait=True, timeout=settings.pool_timeout_seconds)
    except BaseException:
        await pool.close()
        raise
    return pool


@dataclass(slots=True)
class AgentResources:
    pool: AsyncConnectionPool
    checkpointer: AsyncPostgresSaver
    store: AsyncPostgresStore
    graph: Any


_resources: AgentResources | None = None
_resource_lock = asyncio.Lock()


async def get_agent_resources() -> AgentResources:
    """Initialize model, pool, store, and graph only when the Agent endpoint is used."""
    global _resources
    if _resources is not None:
        return _resources

    async with _resource_lock:
        if _resources is not None:
            return _resources

        from app.agents.graph import build_agent_graph
        from app.agents.model import create_agent_model

        model = create_agent_model()
        settings = get_agent_persistence_settings()
        pool: AsyncConnectionPool | None = None
        try:
            pool = await create_agent_pool(settings)
            checkpointer = MeasuredPostgresSaver(pool)
            store = AsyncPostgresStore(pool)
            graph = build_agent_graph(
                model,
                checkpointer=checkpointer,
                store=store,
                snapshot_frequency=settings.delta_snapshot_frequency,
            )
            _resources = AgentResources(
                pool=pool,
                checkpointer=checkpointer,
                store=store,
                graph=graph,
            )
        except BaseException:
            if pool is not None:
                await pool.close()
            raise
        return _resources


async def close_agent_resources() -> None:
    global _resources
    async with _resource_lock:
        resources, _resources = _resources, None
    if resources is not None:
        await resources.pool.close()
