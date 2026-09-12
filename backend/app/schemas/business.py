"""Request and response contracts for storage-space business APIs."""
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

SpaceType = Literal["FRIDGE", "FREEZER", "PANTRY", "WAREHOUSE", "OTHER"]
SpaceStatus = Literal["ACTIVE", "ARCHIVED"]
SpaceName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class StorageSpaceCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: SpaceName
    type: SpaceType


class StorageSpaceUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: SpaceName | None = None
    type: SpaceType | None = None

    @model_validator(mode="after")
    def require_non_null_changes(self) -> "StorageSpaceUpdate":
        if not self.model_fields_set:
            raise ValueError("Provide at least one of name or type")
        if any(getattr(self, field) is None for field in self.model_fields_set):
            raise ValueError("Submitted fields must not be null")
        return self


class StorageSpaceListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ACTIVE", "ARCHIVED", "ALL"] = "ACTIVE"
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)


class StorageSpaceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    type: SpaceType
    status: SpaceStatus
    created_at: datetime
    updated_at: datetime


class StorageSpacePage(BaseModel):
    items: list[StorageSpaceRead]
    total: int
    page: int
    page_size: int


class ValidationIssue(BaseModel):
    loc: list[str | int]
    msg: str


class BusinessErrorDetail(BaseModel):
    code: str
    message: str
    errors: list[ValidationIssue] | None = None


class BusinessErrorResponse(BaseModel):
    detail: BusinessErrorDetail
