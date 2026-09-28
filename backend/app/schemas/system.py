"""Public service metadata returned by unauthenticated system endpoints."""

from typing import Literal

from pydantic import BaseModel, ConfigDict


class HealthResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {"status": "ok", "service": "sayfridge-backend"}
        }
    )

    status: Literal["ok"]
    service: Literal["sayfridge-backend"]


class VersionResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "service": "sayfridge-backend",
                "version": "0.1.0",
                "commit_sha": "0123456789abcdef0123456789abcdef01234567",
            }
        }
    )

    service: Literal["sayfridge-backend"]
    version: str
    commit_sha: str | None
