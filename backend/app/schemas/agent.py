"""HTTP, SSE, tool-input, and long-term-memory contracts for Agent v0.1."""
from __future__ import annotations

from typing import Annotated, Literal
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.schemas.inventory import CalendarDate, ExpiryBucket, InventoryStatus
from app.schemas.agent_media import AgentImage, validate_image_batch
from app.schemas.agent_actions import AgentConversationState


ShortText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
MemoryCategory = Literal["UNIT_RELATIONSHIP", "USAGE_PREFERENCE", "ENTITY_ALIAS"]


class PublicChatMessage(BaseModel):
    model_config = ConfigDict(from_attributes=True, extra="forbid")
    id: UUID
    conversation_id: UUID
    role: Literal["USER", "ASSISTANT"]
    content: str
    created_at: datetime


class PrimaryChatResponse(BaseModel):
    conversation_id: UUID
    state: AgentConversationState
    messages: list[PublicChatMessage]
    next_before: UUID | None = None
    history_complete: bool


class AgentChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    message: Annotated[str, StringConstraints(strip_whitespace=True, max_length=8000)] = ""
    images: list[AgentImage] = Field(default_factory=list, max_length=4)
    conversation_id: UUID | None = None
    as_of: CalendarDate | None = None
    request_id: UUID | None = None

    @model_validator(mode="after")
    def require_content(self):
        validate_image_batch(self.images)
        if not self.message and not self.images:
            raise ValueError("Provide text or images")
        return self


class AgentStreamEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["start", "text_delta", "done", "error", "operation_preview", "action_required", "operation_result"]
    conversation_id: UUID | None = None
    delta: str | None = None
    code: str | None = None
    message: str | None = None
    request_id: UUID | None = None
    status: str | None = None
    data: dict | None = None


class AgentErrorResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "detail": {
                    "code": "AGENT_CONVERSATION_BUSY",
                    "message": "Conversation is running",
                }
            }
        }
    )

    detail: dict


class ListStorageSpacesToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ACTIVE", "ARCHIVED", "ALL"] = "ACTIVE"
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)


class ListInventoryToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: InventoryStatus | Literal["ALL"] = "IN_STOCK"
    q: Annotated[str, StringConstraints(strip_whitespace=True, max_length=100)] = ""
    storage_space_id: UUID | None = None
    category_id: UUID | None = None
    purchase_from: CalendarDate | None = None
    purchase_to: CalendarDate | None = None
    expiry_from: CalendarDate | None = None
    expiry_to: CalendarDate | None = None
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)

    @model_validator(mode="after")
    def validate_ranges(self):
        for prefix in ("purchase", "expiry"):
            start = getattr(self, f"{prefix}_from")
            end = getattr(self, f"{prefix}_to")
            if start is not None and end is not None and start > end:
                raise ValueError("Date range start must not follow its end")
        return self


class InventoryDetailToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    inventory_item_id: UUID


class ExpirySummaryToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    days_before: int = Field(default=3, ge=0, le=365)
    storage_space_id: UUID | None = None
    category_id: UUID | None = None
    bucket: ExpiryBucket | None = None
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)


class MemoryConditions(BaseModel):
    """Conditions under which a user-provided memory may be applied."""

    model_config = ConfigDict(extra="forbid")

    item_definition_id: UUID | None = None
    item_name: ShortText | None = None
    storage_space_id: UUID | None = None
    source_unit: ShortText | None = None
    target_unit: ShortText | None = None
    utensil: ShortText | None = None
    package_description: ShortText | None = None
    valid_from: CalendarDate | None = None
    valid_until: CalendarDate | None = None

    @model_validator(mode="after")
    def valid_time_window(self):
        if self.valid_from and self.valid_until and self.valid_from > self.valid_until:
            raise ValueError("Memory time range is reversed")
        return self


class SearchUserMemoriesToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: MemoryCategory | None = None
    conditions: MemoryConditions | None = None
    limit: int = Field(default=10, ge=1, le=50)


class SaveUserMemoryToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    memory_id: UUID | None = None
    structured_value: dict | None = None
    authorization_quote: ShortText | None = None
    category: MemoryCategory
    content: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1000)]
    conditions: MemoryConditions
    approximate: bool = True

    @model_validator(mode="after")
    def validate_unit_relationship_scope(self):
        if self.category == "UNIT_RELATIONSHIP" and (
            self.conditions.source_unit is None or self.conditions.target_unit is None
        ):
            raise ValueError("Unit relationships require source_unit and target_unit conditions")
        return self


class DeleteUserMemoryToolInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    memory_id: UUID
    authorization_quote: ShortText | None = None
