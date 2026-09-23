"""Administrator-only account reads and state management."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_admin
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.admin import (
    AdminUserListQuery,
    AdminUserPage,
    AdminUserRead,
    AdminUserStatusUpdate,
)
from app.schemas.business import BusinessErrorResponse
from app.services import admin as service


router = APIRouter(
    prefix="/api/v1/admin",
    tags=["admin"],
    responses={
        401: {"description": "Missing, invalid, or unavailable identity"},
        403: {"model": BusinessErrorResponse},
        404: {"model": BusinessErrorResponse},
        422: {"model": BusinessErrorResponse},
    },
)


async def admin_error_handler(request: Request, exc: service.AdminError):
    status_code = 404 if exc.code == "NOT_FOUND" else 403
    return JSONResponse(
        status_code=status_code,
        content={"detail": {"code": exc.code, "message": str(exc)}},
    )


@router.get("/users", response_model=AdminUserPage, summary="List user accounts")
async def list_users(
    query: Annotated[AdminUserListQuery, Query()],
    session: AsyncSession = Depends(get_db_session),
    admin: User = Depends(get_current_admin),
):
    """List filtered accounts without exposing credentials or private inventory."""
    items, total = await service.list_users(session, **query.model_dump())
    return AdminUserPage(
        items=items,
        total=total,
        page=query.page,
        page_size=query.page_size,
    )


@router.get("/users/{user_id}", response_model=AdminUserRead, summary="Read a user account")
async def get_user(
    user_id: UUID,
    session: AsyncSession = Depends(get_db_session),
    admin: User = Depends(get_current_admin),
):
    """Read one account without credentials, quota internals, or inventory."""
    return await service.get_user(session, user_id)


@router.patch(
    "/users/{user_id}/status",
    response_model=AdminUserRead,
    summary="Change an ordinary user's account status",
)
async def update_user_status(
    user_id: UUID,
    payload: AdminUserStatusUpdate,
    session: AsyncSession = Depends(get_db_session),
    admin: User = Depends(get_current_admin),
):
    """Apply an allowed USER status transition without role or password changes."""
    return await service.update_user_status(
        session,
        user_id,
        target_status=payload.status,
    )
