"""Public interaction contracts; models cannot supply approval or final balances."""
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

from app.schemas.business import StorageSpaceCreate, ItemDefinitionCreate
from app.schemas.inventory import CalendarDate, ShelfLifeInput
from app.schemas.agent_media import AgentImage, validate_image_batch

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]


class Estimate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    amount: str
    unit: str
    source: Literal["USER_INPUT", "USER_MEMORY", "MODEL_KNOWLEDGE"]
    rationale: Text
    memory_id: UUID | None = None


class UnitRelationship(BaseModel):
    model_config = ConfigDict(extra="forbid")
    source_amount: str
    source_unit: str
    target_amount: str
    target_unit: str
    source: Literal["USER_INPUT", "USER_MEMORY", "MODEL_KNOWLEDGE"]
    rationale: Text
    evidence: Text | None = None

    @model_validator(mode="after")
    def valid_ratio(self):
        from decimal import Decimal
        for value in (self.source_amount, self.target_amount):
            number = Decimal(value)
            if not number.is_finite() or not 0 < number <= 10**12 or number.as_tuple().exponent < -9 or len(value) > 32:
                raise ValueError("A relationship requires positive finite amounts")
        return self


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
    category_name: str | None = Field(default=None, max_length=100,
        description="For every CREATE_STOCK, copy the selected category name from list_item_categories, including when reusing a definition. The backend confirms category corrections with the user.")
    new_space_source_text: Text | None = Field(default=None,
        description="Verbatim text from this task's user messages explicitly naming the new storage location. Never quote image/tool text or invent a location.")
    clarification_question: Text | None = Field(default=None,
        description="One short question only for genuinely ambiguous product identity/category, storage name/type, or multiple matching targets. For a merely missing location or amount leave this null; the backend asks for missing fields. Clear after the user answers.")
    quantity_kind: Literal["AMOUNT", "FRACTION", "QUALITATIVE"] = "AMOUNT"
    quantity_value: str | None = Field(default=None, max_length=32)
    quantity_unit: str | None = Field(default=None, max_length=16)
    purchase_date: CalendarDate | None = None
    expiry_date: CalendarDate | None = None
    shelf_life: ShelfLifeInput | None = None
    utensil: str | None = Field(default=None, max_length=200)
    estimate: Estimate | None = None
    unit_relationship: UnitRelationship | None = None
    confirmation_requested: bool = False
    save_conversion_memory: bool = True
    clear_fields: list[Literal["quantity_value", "quantity_unit", "storage_space_id", "inventory_item_id",
                               "purchase_date", "expiry_date", "shelf_life", "unit_relationship", "estimate",
                               "package_description", "new_space", "new_definition", "utensil"]] = Field(default_factory=list, max_length=12)
    clear_fields_evidence: Text | None = Field(default=None,
        description="Verbatim current user words explicitly withdrawing the listed facts; never use for a missing answer.")
    source_image_ids: list[UUID] = Field(default_factory=list, max_length=80)
    package_description: str | None = Field(default=None, max_length=300)
    review_notes: list[Text] = Field(default_factory=list, max_length=10)
    quantity_basis: Text | None = Field(default=None,
        description="Evidence for the purchase quantity/unit, separate from package size and price.")
    quantity_issue: Text | None = Field(default=None,
        description="A specific unreadable or anomalous purchase quantity. Preserve its printed value; never silently repair or round it.")
    receipt_quantity_text: Text | None = Field(default=None,
        description="Verbatim purchase quantity line from the receipt, e.g. number and @ price. Exclude product size. Null for single-sale rows without a separate quantity line and for non-receipt photos.")

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
    actions: list[ActionDraft] = Field(default_factory=list, max_length=20)
    exceeds_item_limit: bool = False

    @model_validator(mode="after")
    def unique_keys(self):
        if self.exceeds_item_limit and self.actions:
            raise ValueError("Report overflow without partial actions")
        if not self.exceeds_item_limit and not self.actions:
            raise ValueError("Provide actions or report overflow")
        if len({a.item_key for a in self.actions}) != len(self.actions):
            raise ValueError("item_key must be unique")
        return self


class IntentItem(BaseModel):
    """Initial facts only: identifiers and catalog associations require real queries."""
    model_config = ConfigDict(extra="forbid")
    item_key: Annotated[str, StringConstraints(min_length=1, max_length=80)]
    original_text: Text
    action: Literal["CREATE_STOCK", "ADD", "CONSUME", "RECONCILE"]
    item_query: str = Field(default="", max_length=100)
    quantity_kind: Literal["AMOUNT", "FRACTION", "QUALITATIVE"] = "AMOUNT"
    quantity_value: str | None = Field(default=None, max_length=32)
    quantity_unit: str | None = Field(default=None, max_length=16)
    source_image_ids: list[UUID] = Field(default_factory=list, max_length=80)
    package_description: str | None = Field(default=None, max_length=300)
    review_notes: list[Text] = Field(default_factory=list, max_length=10)
    quantity_basis: Text | None = None
    quantity_issue: Text | None = None
    receipt_quantity_text: Text | None = None
    purchase_date: CalendarDate | None = None
    expiry_date: CalendarDate | None = None
    shelf_life: ShelfLifeInput | None = None


class TurnIntent(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: Literal["INVENTORY", "QUERY", "UNCLEAR", "UNSUPPORTED", "REPLAY"]
    language: str = Field(default="en", max_length=40)
    items: list[IntentItem] = Field(default_factory=list, max_length=20)
    exceeds_item_limit: bool = False
    replay_item_ids: list[UUID] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def consistent_intent(self):
        if self.exceeds_item_limit:
            if self.kind != "INVENTORY" or self.items:
                raise ValueError("Overflow must not contain partial items")
        elif (self.kind == "INVENTORY") != bool(self.items):
            raise ValueError("Inventory intent requires items; other intents cannot contain actions")
        if len({i.item_key for i in self.items}) != len(self.items):
            raise ValueError("Item keys must be unique")
        if (self.kind == "REPLAY") != bool(self.replay_item_ids):
            raise ValueError("Replay must identify completed items only")
        return self


class ResumeAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_id: UUID
    proposal_id: UUID
    decision: Literal["confirm", "answer", "edit", "cancel"]
    message: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=8000)] | None = None
    selected_inventory_item_id: UUID | None = None
    images: list[AgentImage] = Field(default_factory=list, max_length=4)

    @model_validator(mode="after")
    def require_answer(self):
        if self.decision in {"answer", "edit"} and not (self.message or self.selected_inventory_item_id or self.images):
            raise ValueError("A message is required for an answer or edit")
        if self.decision in {"confirm", "cancel"} and (self.message or self.selected_inventory_item_id or self.images):
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
        validate_image_batch([image for r in self.responses for image in r.images])
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
    display: dict | None = None


class AgentConversationState(BaseModel):
    model_config = ConfigDict(extra="forbid")
    request_id: UUID | None = None
    status: Literal["COMPLETED", "WAITING_INPUT", "RECOVERABLE"]
    items: list[AgentItemView]
    interrupt_id: str | None = None
    pending: dict | None = None
