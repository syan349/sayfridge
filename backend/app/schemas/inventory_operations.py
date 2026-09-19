"""Request and response contracts for inventory quantity operations."""
import re
from datetime import datetime
from decimal import Decimal
from uuid import UUID
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from app.core.quantity import validate_addition_amount
from app.schemas.inventory import InventoryItemRead


# The route will bind this type to the Idempotency-Key header, not the JSON body.
IdempotencyKey = Annotated[
    str, StringConstraints(strict=True, min_length=1, max_length=64, pattern=r"^[!-~]+$")
]


class InventoryOperationCreate(BaseModel):
    """B10 request body. Database ownership/state/version checks belong to services.

    Only ADD/AMOUNT is currently supported. Require both fields
    explicitly so a client cannot accidentally request a different operation.
    """

    model_config = ConfigDict(extra="forbid")

    expected_version: int = Field(strict=True, ge=1, le=2147483647)
    operation_type: Literal["ADD"]
    quantity_kind: Literal["AMOUNT"]
    quantity_value: str = Field(strict=True, max_length=32)
    quantity_unit: str = Field(strict=True)

    @field_validator("quantity_value")
    @classmethod
    def validate_quantity_value(cls, value: str) -> str:
        """Check raw syntax before Decimal conversion; keep the original expression."""
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]{1,3})?", value):
            raise ValueError("Quantity must be a decimal string with at most three decimal places")
        validate_addition_amount(Decimal(value))
        # Preserve 2 versus 2.0 for the later idempotency comparison and history.
        return value

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
    New B10 writes will use ADD, AMOUNT, MANUAL, and SUCCESS; historical records
    may contain other values already supported by the database.
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


class OperationResult(BaseModel):
    """A submitted/replayed operation and inventory as currently read by the service."""

    operation: InventoryOperationRead
    inventory: InventoryItemRead
    replayed: bool
