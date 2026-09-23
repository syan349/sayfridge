"""Administrator account-management request and response contracts."""
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, StringConstraints

UserRole = Literal["USER", "ADMIN"]
UserStatus = Literal["ACTIVE", "SUSPENDED", "DISABLED"]


class AdminUserListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    q: Annotated[str, StringConstraints(strip_whitespace=True, max_length=100)] = ""
    role: Literal["USER", "ADMIN", "ALL"] = "ALL"
    status: Literal["ACTIVE", "SUSPENDED", "DISABLED", "ALL"] = "ALL"
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)


class AdminUserStatusUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: UserStatus


class AdminUserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    role: UserRole
    status: UserStatus
    created_at: datetime
    updated_at: datetime


class AdminUserPage(BaseModel):
    items: list[AdminUserRead]
    total: int
    page: int
    page_size: int
