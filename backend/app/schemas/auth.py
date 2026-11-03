from datetime import datetime
from typing import Literal
import uuid

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class CredentialsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip().lower()
        return value


class RegisterRequest(CredentialsRequest):
    pass


class LoginRequest(CredentialsRequest):
    pass


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    role: Literal["USER", "ADMIN"]
    status: Literal["ACTIVE", "SUSPENDED", "DISABLED"]
    created_at: datetime


class LoginResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: UserPublic
    refresh_token: str
    refresh_expires_in: int


class RefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    refresh_token: str = Field(min_length=40, max_length=128)


class AuthErrorResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={"example": {"detail": "Invalid email or password"}}
    )

    detail: str


class AuthValidationIssue(BaseModel):
    type: str
    loc: list[str | int]
    msg: str


class AuthValidationErrorResponse(BaseModel):
    detail: list[AuthValidationIssue]


class PasswordChangeErrorBody(BaseModel):
    code: str
    message: str


class PasswordChangeErrorResponse(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={"example": {"detail": {"code": "CURRENT_PASSWORD_INCORRECT", "message": "Current password is incorrect."}}}
    )

    detail: PasswordChangeErrorBody


class ChangePasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)
