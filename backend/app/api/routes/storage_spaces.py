"""B04 REST endpoints; storage-space business rules live in the service layer."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, require_empty_body
from app.db.models import StorageSpace, User
from app.db.session import get_db_session
from app.schemas.business import (
    BusinessErrorResponse, StorageSpaceCreate, StorageSpaceListQuery, StorageSpacePage,
    StorageSpaceRead, StorageSpaceUpdate,
)
from app.services import storage_spaces as service

router = APIRouter(
    prefix="/api/v1/storage-spaces",
    tags=["storage-spaces"],
    responses={
        401: {"description": "Missing, invalid, or unavailable identity"},
        422: {"model": BusinessErrorResponse, "description": "Invalid request parameters"},
    },
)
NOT_FOUND_RESPONSE = {404: {"model": BusinessErrorResponse, "description": "Missing or inaccessible space"}}
CONFLICT_RESPONSE = {409: {"model": BusinessErrorResponse, "description": "Name or state conflict"}}
WRITE_RESPONSES = {**NOT_FOUND_RESPONSE, **CONFLICT_RESPONSE}


async def storage_space_error_handler(request: Request, exc: service.StorageSpaceError) -> JSONResponse:
    if isinstance(exc, service.SpaceNotFoundError):
        code, http_status = "NOT_FOUND", status.HTTP_404_NOT_FOUND
    elif isinstance(exc, service.SpaceNameConflictError):
        code, http_status = "NAME_CONFLICT", status.HTTP_409_CONFLICT
    else:
        code, http_status = "STATE_CONFLICT", status.HTTP_409_CONFLICT
    return JSONResponse(status_code=http_status, content={"detail": {"code": code, "message": str(exc)}})


@router.get("", response_model=StorageSpacePage, status_code=status.HTTP_200_OK)
async def list_storage_spaces(
    query: Annotated[StorageSpaceListQuery, Query()],
    session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> StorageSpacePage:
    spaces, total = await service.list_storage_spaces(
        session, current_user.id, status=query.status, page=query.page, page_size=query.page_size,
    )
    return StorageSpacePage(items=spaces, total=total, page=query.page, page_size=query.page_size)


@router.get("/{space_id}", response_model=StorageSpaceRead, status_code=status.HTTP_200_OK,
            responses=NOT_FOUND_RESPONSE)
async def get_storage_space(
    space_id: UUID,
    session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> StorageSpace:
    return await service.get_storage_space_by_id(session, space_id, current_user.id)


@router.post("", response_model=StorageSpaceRead, status_code=status.HTTP_201_CREATED,
             responses=CONFLICT_RESPONSE)
async def create_storage_space(
    payload: StorageSpaceCreate,
    session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> StorageSpace:
    return await service.create_storage_space(session, current_user.id, **payload.model_dump())


@router.patch("/{space_id}", response_model=StorageSpaceRead, status_code=status.HTTP_200_OK,
              responses=WRITE_RESPONSES)
async def update_storage_space(
    space_id: UUID,
    payload: StorageSpaceUpdate,
    session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> StorageSpace:
    return await service.update_storage_space(
        session, space_id, current_user.id, changes=payload.model_dump(exclude_unset=True),
    )


@router.post("/{space_id}/archive", response_model=StorageSpaceRead,
             status_code=status.HTTP_200_OK, dependencies=[Depends(require_empty_body)],
             responses=WRITE_RESPONSES)
async def archive_storage_space(
    space_id: UUID,
    session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> StorageSpace:
    return await service.set_storage_space_status(session, space_id, current_user.id, target_status="ARCHIVED")


@router.post("/{space_id}/restore", response_model=StorageSpaceRead,
             status_code=status.HTTP_200_OK, dependencies=[Depends(require_empty_body)],
             responses=WRITE_RESPONSES)
async def restore_storage_space(
    space_id: UUID,
    session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> StorageSpace:
    return await service.set_storage_space_status(session, space_id, current_user.id, target_status="ACTIVE")
