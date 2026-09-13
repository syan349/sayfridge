"""Authenticated inventory reads, stock entry, and metadata maintenance."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.business import BusinessErrorResponse
from app.schemas.inventory import InventoryCreate, InventoryUpdate, InventoryListQuery, InventoryItemRead, InventoryPage
from app.services import inventory as service

router = APIRouter(prefix="/api/v1/inventory-items", tags=["inventory"], responses={
    401: {"description": "Missing, invalid, or unavailable identity"},
    404: {"model": BusinessErrorResponse},
    409: {"model": BusinessErrorResponse},
    422: {"model": BusinessErrorResponse},
})


async def inventory_error_handler(request: Request, exc: service.InventoryError):
    return JSONResponse(status_code=404 if exc.code == "NOT_FOUND" else 409,
                        content={"detail": {"code": exc.code, "message": str(exc)}})


@router.get("", response_model=InventoryPage, summary="List owned inventory")
async def list_inventory(query: Annotated[InventoryListQuery, Query()],
                         session: AsyncSession = Depends(get_db_session),
                         user: User = Depends(get_current_user)):
    """Read a filtered page using current names and estimate-first display quantities."""
    items, total = await service.list_inventory(session, user.id, **query.model_dump())
    return InventoryPage(items=items, total=total, page=query.page, page_size=query.page_size)


@router.get("/{item_id}", response_model=InventoryItemRead, summary="Read owned inventory")
async def get_inventory(item_id: UUID, session: AsyncSession = Depends(get_db_session),
                        user: User = Depends(get_current_user)):
    """Read inventory in any state without hiding archived associations."""
    return await service.get_inventory(session, item_id, user.id)


@router.post("", response_model=InventoryItemRead, status_code=201, summary="Create stock")
async def create_inventory(payload: InventoryCreate, session: AsyncSession = Depends(get_db_session),
                           user: User = Depends(get_current_user)):
    """Create a confirmed stock batch in active associations without an ADD event."""
    return await service.create_inventory(session, user.id, **payload.model_dump())


@router.patch("/{item_id}", response_model=InventoryItemRead, summary="Edit inventory metadata or location")
async def update_inventory(item_id: UUID, payload: InventoryUpdate,
                           session: AsyncSession = Depends(get_db_session), user: User = Depends(get_current_user)):
    """Apply version-checked metadata changes without altering stock quantities or history."""
    values = payload.model_dump(exclude_unset=True)
    version = values.pop("expected_version")
    return await service.update_inventory(session, item_id, user.id, expected_version=version, changes=values)
