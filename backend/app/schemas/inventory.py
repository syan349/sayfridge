"""Inventory query, stock entry, metadata, state-action, and response contracts."""
import re
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID
from app.core.quantity import MAX_QUANTITY

from pydantic import BaseModel, BeforeValidator, ConfigDict, Field, StringConstraints, field_validator, model_validator

InventoryStatus = Literal["IN_STOCK", "EMPTY", "DISCARDED", "ARCHIVED"]
ExpiryBucket = Literal["overdue", "today", "upcoming"]
Notes = Annotated[str, StringConstraints(max_length=1000)]


def _calendar_date(value):
    if type(value) is date or (isinstance(value, str) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value)):
        return value
    raise ValueError("Date must use YYYY-MM-DD")


CalendarDate = Annotated[date, BeforeValidator(_calendar_date)]


class InventoryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    storage_space_id: UUID
    item_definition_id: UUID
    amount: str
    unit: str
    purchase_date: CalendarDate | None = None
    expiry_date: CalendarDate | None = None
    notes: Notes | None = None

    @field_validator("amount")
    @classmethod
    def validate_amount(cls, value: str) -> str:
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]{1,3})?", value):
            raise ValueError("Amount must be a decimal string with at most three decimal places")
        if not Decimal("0") < Decimal(value) <= MAX_QUANTITY:
            raise ValueError(f"Amount must be positive and at most {MAX_QUANTITY}")
        return value

    @field_validator("unit")
    @classmethod
    def normalize_unit(cls, value: str) -> str:
        value = value.strip()
        if not 1 <= len(value) <= 16:
            raise ValueError("Unit must contain 1 to 16 characters after trimming")
        # Normalize symbol casing without guessing aliases or count-unit equivalence.
        value = value.casefold()
        if len(value) > 16:
            raise ValueError("Normalized unit must contain at most 16 characters")
        return value


class InventoryBatchCreate(BaseModel):
    """One atomic request containing independently validated stock entries."""

    model_config = ConfigDict(extra="forbid")
    items: list[InventoryCreate] = Field(min_length=1, max_length=100)


class InventoryBatchItem(BaseModel):
    """One version-guarded inventory reference inside a batch write."""

    model_config = ConfigDict(extra="forbid")
    id: UUID
    expected_version: int = Field(ge=1, le=2147483647, strict=True)


class InventoryBatchMove(BaseModel):
    model_config = ConfigDict(extra="forbid")
    target_storage_space_id: UUID
    items: list[InventoryBatchItem] = Field(min_length=1, max_length=100)


class InventoryBatchArchive(BaseModel):
    model_config = ConfigDict(extra="forbid")
    items: list[InventoryBatchItem] = Field(min_length=1, max_length=100)


class InventoryUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    expected_version: int = Field(ge=1, le=2147483647, strict=True)
    storage_space_id: UUID | None = None
    purchase_date: CalendarDate | None = None
    expiry_date: CalendarDate | None = None
    notes: Notes | None = None

    @model_validator(mode="after")
    def validate_changes(self):
        if not self.model_fields_set - {"expected_version"}:
            raise ValueError("Provide at least one metadata or location field")
        if "storage_space_id" in self.model_fields_set and self.storage_space_id is None:
            raise ValueError("Storage space must not be null")
        return self


class InventoryStateAction(BaseModel):
    """Version guard for an explicit inventory state transition."""

    model_config = ConfigDict(extra="forbid")
    expected_version: int = Field(ge=1, le=2147483647, strict=True)


class InventoryListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["IN_STOCK", "EMPTY", "DISCARDED", "ARCHIVED", "ALL"] = "IN_STOCK"
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
            start, end = getattr(self, prefix + "_from"), getattr(self, prefix + "_to")
            if start is not None and end is not None and start > end:
                raise ValueError("Date range start must not follow its end")
        return self


class ExpirySummaryQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")
    as_of: CalendarDate
    days_before: int = Field(default=3, ge=0, le=365)
    storage_space_id: UUID | None = None
    category_id: UUID | None = None
    bucket: ExpiryBucket | None = None
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)

    @model_validator(mode="after")
    def validate_window(self):
        try:
            self.as_of + timedelta(days=self.days_before)
        except OverflowError as exc:
            raise ValueError("Expiry window exceeds the legal date range") from exc
        return self


class InventoryItemRead(BaseModel):
    id: UUID
    storage_space_id: UUID
    storage_space_name: str
    item_definition_id: UUID
    item_definition_name: str
    category_id: UUID
    category_name: str
    purchase_date: date | None
    expiry_date: date | None
    notes: str | None
    status: InventoryStatus
    initial_amount: Decimal
    initial_unit: str
    confirmed_current_amount: Decimal
    confirmed_current_unit: str
    confirmed_at: datetime
    estimated_current_amount: Decimal | None
    estimated_current_unit: str | None
    estimated_at: datetime | None
    display_amount: Decimal
    display_unit: str
    is_estimated: bool
    version: int
    created_at: datetime
    updated_at: datetime


class InventoryPage(BaseModel):
    items: list[InventoryItemRead]
    total: int
    page: int
    page_size: int


class ExpiryCounts(BaseModel):
    overdue: int
    today: int
    upcoming: int


class ExpirySummaryItem(InventoryItemRead):
    bucket: ExpiryBucket


class ExpirySummary(BaseModel):
    counts: ExpiryCounts
    items: list[ExpirySummaryItem]
    total: int
    page: int
    page_size: int


class InventoryBatchResult(BaseModel):
    items: list[InventoryItemRead]
    count: int
