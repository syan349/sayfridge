"""Public interaction contracts; models cannot supply approval or final balances."""
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.schemas.business import StorageSpaceCreate, ItemDefinitionCreate
from app.schemas.inventory import CalendarDate

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]


class Estimate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    amount: str
    unit: str
    source: Literal["USER_INPUT", "USER_MEMORY", "MODEL_KNOWLEDGE"]
    rationale: Text
    memory_id: UUID | None = None


class ActionDraft(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_key: Annotated[str, StringConstraints(min_length=1, max_length=80)]
    original_text: Text
    action: Literal["CREATE_STOCK", "ADD", "CONSUME", "RECONCILE"]
    inventory_item_id: UUID | None = None
    item_query: str = Field(default="", max_length=100)
    storage_space_id: UUID | None = None
    item_definition_id: UUID | None = None
    new_space: StorageSpaceCreate | None = None
    new_definition: ItemDefinitionCreate | None = None
    quantity_kind: Literal["AMOUNT", "FRACTION", "QUALITATIVE"] = "AMOUNT"
    quantity_value: str | None = Field(default=None, max_length=32)
    quantity_unit: str | None = Field(default=None, max_length=16)
    purchase_date: CalendarDate | None = None
    expiry_date: CalendarDate | None = None
    utensil: str | None = Field(default=None, max_length=200)
    estimate: Estimate | None = None

    @model_validator(mode="after")
    def no_conflicting_targets(self):
        if self.storage_space_id and self.new_space:
            raise ValueError("Choose an existing or new space")
        if self.item_definition_id and self.new_definition:
            raise ValueError("Choose an existing or new item definition")
        if self.action != "CREATE_STOCK" and (self.new_space or self.new_definition):
            raise ValueError("New associations belong to CREATE_STOCK only")
        return self


class ProposeActions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    actions: list[ActionDraft] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def unique_keys(self):
        if len({a.item_key for a in self.actions}) != len(self.actions):
            raise ValueError("item_key must be unique")
        return self


class ResumeAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_id: UUID
    proposal_id: UUID
    decision: Literal["confirm", "answer", "edit", "cancel"]
    message: Text | None = None
    selected_inventory_item_id: UUID | None = None

    @model_validator(mode="after")
    def require_answer(self):
        if self.decision in {"answer", "edit"} and not (self.message or self.selected_inventory_item_id):
            raise ValueError("A message is required for an answer or edit")
        if self.decision in {"confirm", "cancel"} and (self.message or self.selected_inventory_item_id):
            raise ValueError("Confirm/cancel accept identifiers only")
        return self


class AgentResumeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    conversation_id: UUID
    interrupt_id: str
    request_id: UUID
    responses: list[ResumeAnswer] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def unique_items(self):
        if len({r.item_id for r in self.responses}) != len(self.responses):
            raise ValueError("Each item may be answered only once")
        return self


class AgentItemView(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_id: UUID
    item_key: str
    proposal_id: UUID
    status: Literal["DRAFT", "READY", "NEEDS_INPUT", "NEEDS_CONFIRMATION", "SUCCEEDED", "FAILED", "CANCELLED"]
    original_text: str
    preview: dict | None = None
    error: dict | None = None
    result: dict | None = None


class AgentConversationState(BaseModel):
    model_config = ConfigDict(extra="forbid")
    request_id: UUID | None = None
    status: Literal["COMPLETED", "WAITING_INPUT", "RECOVERABLE"]
    items: list[AgentItemView]
    interrupt_id: str | None = None
    pending: dict | None = None
