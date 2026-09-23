"""Authenticated inventory reads, stock entry, quantity, metadata, and state actions."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Header, Response
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.business import BusinessErrorResponse
from app.schemas.inventory import (
    InventoryBatchArchive,
    InventoryBatchCreate,
    InventoryBatchMove,
    InventoryBatchResult,
    InventoryCreate,
    InventoryItemRead,
    InventoryListQuery,
    InventoryPage,
    InventoryStateAction,
    InventoryUpdate,
)
from app.services import inventory as service
from app.schemas.inventory_operations import (
    IdempotencyKey,
    InventoryOperationCreate,
    InventoryOperationRead,
    OperationResult,
)


router = APIRouter(prefix="/api/v1/inventory-items", tags=["inventory"], responses={
    401: {"description": "Missing, invalid, or unavailable identity"},
    404: {"model": BusinessErrorResponse},
    409: {"model": BusinessErrorResponse},
    422: {"model": BusinessErrorResponse},
})


async def inventory_error_handler(request: Request, exc: service.InventoryError):
    if exc.code == "NOT_FOUND":
        status_code = 404
    elif exc.code in ["VALIDATION_ERROR", "UNIT_NOT_CONVERTIBLE", "QUANTITY_TOO_SMALL", "QUANTITY_OUT_OF_RANGE",
                       "INSUFFICIENT_QUANTITY", "QUANTITY_PRECISION_UNSUPPORTED"]:
        status_code = 422
    else:
        status_code = 409

    detail = {"code": exc.code, "message": str(exc)}
    if exc.item_index is not None:
        detail["item_index"] = exc.item_index
    return JSONResponse(status_code=status_code, content={"detail": detail})


@router.get("", response_model=InventoryPage, summary="List owned inventory")
async def list_inventory(query: Annotated[InventoryListQuery, Query()],
                         session: AsyncSession = Depends(get_db_session),
                         user: User = Depends(get_current_user)):
    """Read a filtered page using current names and estimate-first display quantities."""
    items, total = await service.list_inventory(session, user.id, **query.model_dump())
    return InventoryPage(items=items, total=total, page=query.page, page_size=query.page_size)


@router.post(
    "/batch-create",
    response_model=InventoryBatchResult,
    status_code=201,
    summary="Create multiple stock batches atomically",
)
async def batch_create_inventory(
    payload: InventoryBatchCreate,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """Create every requested stock row, or roll back the complete batch."""
    items = await service.create_inventory_batch(
        session,
        user.id,
        [item.model_dump() for item in payload.items],
    )
    return InventoryBatchResult(items=items, count=len(items))


@router.post(
    "/batch-move",
    response_model=InventoryBatchResult,
    summary="Move multiple inventory items atomically",
)
async def batch_move_inventory(
    payload: InventoryBatchMove,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """Move every referenced item to one active owned space, or change none."""
    items = await service.move_inventory_batch(
        session,
        user.id,
        target_storage_space_id=payload.target_storage_space_id,
        items=[item.model_dump() for item in payload.items],
    )
    return InventoryBatchResult(items=items, count=len(items))


@router.post(
    "/batch-archive",
    response_model=InventoryBatchResult,
    summary="Archive multiple inventory items atomically",
)
async def batch_archive_inventory(
    payload: InventoryBatchArchive,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """Archive every referenced in-stock or empty item, or change none."""
    items = await service.archive_inventory_batch(
        session,
        user.id,
        items=[item.model_dump() for item in payload.items],
    )
    return InventoryBatchResult(items=items, count=len(items))


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


@router.get(
    "/{item_id}/operations",
    response_model=list[InventoryOperationRead],
    summary="List inventory operation history",
)
async def list_inventory_operations(
    item_id: UUID,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """List all operation records for one owned inventory item, newest first."""
    return await service.list_inventory_operations(session, item_id, user.id)


@router.post("/{item_id}/operations",
            responses={
                200: {
                    "model": OperationResult,
                    "description": "Successful request replay",
                }},
             response_model = OperationResult,
             status_code = 201,
             summary = "Add, consume, or reconcile inventory quantity",
            )
async def create_inventory_operation(item_id:UUID, payload:InventoryOperationCreate, 
                                     idempotency_key: Annotated[IdempotencyKey, Header(alias="Idempotency-Key")],
                                     response: Response, session:AsyncSession = Depends(get_db_session), 
                                     user:User = Depends(get_current_user)):
    result = await service.submit_inventory_operation(session, item_id, user.id,
                                operation_type=payload.operation_type, quantity_kind=payload.quantity_kind,
                                expected_version = payload.expected_version, quantity_value = payload.quantity_value, 
                                quantity_unit = payload.quantity_unit, idempotency_key = idempotency_key)
    if result.replayed:
        response.status_code = 200
    else:
        response.status_code = 201
    return result



@router.patch("/{item_id}", response_model=InventoryItemRead, summary="Edit inventory metadata or location")
async def update_inventory(item_id: UUID, payload: InventoryUpdate,
                           session: AsyncSession = Depends(get_db_session), user: User = Depends(get_current_user)):
    """Apply version-checked metadata changes without altering stock quantities or history."""
    values = payload.model_dump(exclude_unset=True)
    version = values.pop("expected_version")
    return await service.update_inventory(session, item_id, user.id, expected_version=version, changes=values)


@router.post("/{item_id}/discard", response_model=InventoryItemRead, summary="Discard inventory")
async def discard_inventory(
    item_id: UUID,
    payload: InventoryStateAction,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """Mark owned in-stock inventory as discarded without changing quantities or history."""
    return await service.discard_inventory(
        session, item_id, user.id, expected_version=payload.expected_version
    )


@router.post("/{item_id}/archive", response_model=InventoryItemRead, summary="Archive inventory")
async def archive_inventory(
    item_id: UUID,
    payload: InventoryStateAction,
    session: AsyncSession = Depends(get_db_session),
    user: User = Depends(get_current_user),
):
    """Archive owned in-stock or empty inventory without changing quantities or history."""
    return await service.archive_inventory(
        session, item_id, user.id, expected_version=payload.expected_version
    )
