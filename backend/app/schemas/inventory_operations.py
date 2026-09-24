"""Request and response contracts for inventory quantity operations."""
import re
from datetime import datetime
from decimal import Decimal
from uuid import UUID
from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

from app.core.quantity import validate_quantity_amount, parse_consumption_fraction
from app.schemas.inventory import InventoryItemRead


# The route will bind this type to the Idempotency-Key header, not the JSON body.
IdempotencyKey = Annotated[
    str, StringConstraints(strict=True, min_length=1, max_length=64, pattern=r"^[!-~]+$")
]


class InventoryOperationCreate(BaseModel):
    """ADD, CONSUME, or RECONCILE request body.

    Amounts support every operation; fractions support only CONSUME. Database
    ownership, state, and version checks belong to services.
    """

    model_config = ConfigDict(extra="forbid")

    expected_version: int = Field(strict=True, ge=1, le=2147483647)
    operation_type: Literal["ADD", "CONSUME", "RECONCILE"]
    quantity_kind: Literal["AMOUNT", "FRACTION"]
    quantity_value: str = Field(strict=True, max_length=32)
    quantity_unit: str = Field(strict=True)

    @model_validator(mode="after")
    def validate_quantity(self):
        """Validate the selected input form while preserving its literal expression."""
        if self.quantity_kind == "FRACTION":
            if self.operation_type != "CONSUME":
                raise ValueError("Fractions are supported only for CONSUME")
            if self.quantity_unit != "remaining":
                raise ValueError("Fraction quantity_unit must be remaining")
            parse_consumption_fraction(self.quantity_value)
        elif self.quantity_kind == "AMOUNT":
            if not re.fullmatch(r"[0-9]+(?:\.[0-9]{1,3})?", self.quantity_value):
                raise ValueError("Quantity must be a decimal string with at most three decimal places")
            allow_zero = self.operation_type == "RECONCILE"
            validate_quantity_amount(Decimal(self.quantity_value), allow_zero=allow_zero)
        # Preserve 2 versus 2.0 and 1/2 versus 2/4 for idempotency and history.
        return self

    @field_validator("quantity_unit")
    @classmethod
    def validate_quantity_unit(cls, value: str) -> str:
        """Trim surrounding whitespace for storage; preserve literal case for history."""
        value = value.strip()
        if not 1 <= len(value) <= 16:
            raise ValueError("Unit must contain 1 to 16 characters after trimming")
        if len(value.casefold()) > 16:
            raise ValueError("Normalized unit must contain at most 16 characters")
        return value


class InventoryOperationRead(BaseModel):
    """Public operation fields, including existing historical states.

    Read declared fields from an ORM object and omit the internal idempotency key.
    New writes use ADD/CONSUME/RECONCILE, AMOUNT/FRACTION, MANUAL, and SUCCESS;
    historical records may contain other values already supported by the database.
    """

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    inventory_item_id: UUID
    operation_type: Literal["ADD", "CONSUME", "RECONCILE"]
    quantity_kind: Literal["AMOUNT", "FRACTION", "QUALITATIVE"]
    quantity_value: str
    quantity_unit: str | None
    input_method: Literal["TEXT", "VOICE", "PHOTO", "RECEIPT", "MANUAL"]
    calculation_method: Literal["EXACT", "CONVERTED", "AI_ESTIMATED"]
    affects_state: Literal["CONFIRMED", "ESTIMATED"]
    applied_change_amount: Decimal | None
    applied_change_unit: str | None
    status: Literal["PENDING_CONFIRMATION", "SUCCESS", "FAILED", "UNDONE"]
    created_at: datetime
    updated_at: datetime
    undone_at: datetime | None


class InventoryOperationListQuery(BaseModel):
    """Filters and pagination for the current user's operation history."""

    model_config = ConfigDict(extra="forbid")

    inventory_item_id: UUID | None = None
    operation_type: Literal["ADD", "CONSUME", "RECONCILE"] | None = None
    status: Literal["PENDING_CONFIRMATION", "SUCCESS", "FAILED", "UNDONE"] | None = None
    created_from: AwareDatetime | None = None
    created_to: AwareDatetime | None = None
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)

    @model_validator(mode="after")
    def validate_time_range(self):
        if self.created_from is not None and self.created_to is not None:
            if self.created_from >= self.created_to:
                raise ValueError("created_from must be earlier than created_to")
        return self


class InventoryOperationPage(BaseModel):
    items: list[InventoryOperationRead]
    total: int
    page: int
    page_size: int


class OperationResult(BaseModel):
    """A submitted/replayed operation and inventory as currently read by the service."""

    operation: InventoryOperationRead
    inventory: InventoryItemRead
    replayed: bool
