"""Authenticated inventory reads, stock entry, and metadata maintenance."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Header, Response
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.business import BusinessErrorResponse
from app.schemas.inventory import InventoryCreate, InventoryUpdate, InventoryListQuery, InventoryItemRead, InventoryPage
from app.services import inventory as service
from app.schemas.inventory_operations import InventoryOperationCreate, OperationResult, IdempotencyKey


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

    return JSONResponse(status_code=status_code, content={"detail": {"code": exc.code, "message": str(exc)}})


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
