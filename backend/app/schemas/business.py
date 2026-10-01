"""Request and response contracts for space and catalog business APIs."""
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

from app.core.catalog import normalize_catalog_name

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
    is_default: bool = False
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
    item_index: int | None = None
    errors: list[ValidationIssue] | None = None


class BusinessErrorResponse(BaseModel):
    detail: BusinessErrorDetail


class CatalogListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ACTIVE", "ARCHIVED", "ALL"] = "ACTIVE"
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)


class ItemDefinitionListQuery(CatalogListQuery):
    q: Annotated[str, StringConstraints(strip_whitespace=True, max_length=100)] = ""
    category_id: UUID | None = None
    scope: Literal["PUBLIC", "PRIVATE", "ALL"] = "ALL"


CatalogName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class ItemDefinitionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: CatalogName
    category_id: UUID

    @field_validator("name")
    @classmethod
    def validate_normalized_length(cls, name: str) -> str:
        if not 1 <= len(normalize_catalog_name(name)) <= 100:
            raise ValueError("Normalized name must contain 1 to 100 characters")
        return name


class ItemDefinitionUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: CatalogName | None = None
    category_id: UUID | None = None

    @field_validator("name")
    @classmethod
    def validate_normalized_length(cls, name: str | None) -> str | None:
        if name is not None:
            ItemDefinitionCreate.validate_normalized_length(name)
        return name

    @model_validator(mode="after")
    def require_non_null_changes(self) -> "ItemDefinitionUpdate":
        if not self.model_fields_set:
            raise ValueError("Provide at least one of name or category_id")
        if any(getattr(self, field) is None for field in self.model_fields_set):
            raise ValueError("Submitted fields must not be null")
        return self


class ItemCategoryRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    status: Literal["ACTIVE", "ARCHIVED"]
    sort_order: int


class ItemCategoryPage(BaseModel):
    items: list[ItemCategoryRead]
    total: int
    page: int
    page_size: int


class ItemDefinitionRead(BaseModel):
    id: UUID
    name: str
    category_id: UUID
    status: Literal["ACTIVE", "ARCHIVED"]
    scope: Literal["PUBLIC", "PRIVATE"]


class ItemDefinitionPage(BaseModel):
    items: list[ItemDefinitionRead]
    total: int
    page: int
    page_size: int
