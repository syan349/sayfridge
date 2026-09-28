"""Authenticated global inventory-operation history reads."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.business import BusinessErrorResponse
from app.schemas.auth import AuthErrorResponse
from app.schemas.inventory_operations import (
    InventoryOperationListQuery,
    InventoryOperationPage,
    InventoryOperationRead,
)
from app.services import inventory as service


router = APIRouter(
    prefix="/api/v1/inventory-operations",
    tags=["inventory"],
    responses={
        401: {"model": AuthErrorResponse, "description": "Missing, invalid, expired, or unavailable identity"},
        422: {"model": BusinessErrorResponse, "description": "Invalid query parameters"},
    },
)


@router.get("", response_model=InventoryOperationPage, summary="List owned inventory operations")
async def list_inventory_operations(
    query: Annotated[InventoryOperationListQuery, Query()],
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
) -> InventoryOperationPage:
    """List a filtered, deterministic page of the current user's operation history."""
    items, total = await service.list_owned_inventory_operations(
        session, user.id, **query.model_dump()
    )
    return InventoryOperationPage(
        items=items,
        total=total,
        page=query.page,
        page_size=query.page_size,
    )


@router.get(
    "/{operation_id}",
    response_model=InventoryOperationRead,
    summary="Read an owned inventory operation",
    responses={
        404: {"model": BusinessErrorResponse, "description": "Missing or inaccessible operation"}
    },
)
async def get_inventory_operation(
    operation_id: UUID,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """Read one operation without exposing its internal idempotency key."""
    return await service.get_inventory_operation(session, operation_id, user.id)
