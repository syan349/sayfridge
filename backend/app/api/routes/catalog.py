"""Authenticated category and private item-definition REST endpoints."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user, require_empty_body
from app.db.models import ItemDefinition, User
from app.db.session import get_db_session
from app.schemas.business import (
    BusinessErrorResponse, CatalogListQuery, ItemCategoryPage, ItemCategoryCreate, ItemCategoryRead, ItemDefinitionCreate,
    ItemDefinitionListQuery, ItemDefinitionPage, ItemDefinitionRead, ItemDefinitionUpdate,
)
from app.schemas.auth import AuthErrorResponse
from app.services import catalog as service

router = APIRouter(prefix="/api/v1", tags=["catalog"], responses={
    401: {"model": AuthErrorResponse, "description": "Missing, invalid, expired, or unavailable identity"},
    422: {"model": BusinessErrorResponse, "description": "Invalid request parameters"},
})
NOT_FOUND = {404: {"model": BusinessErrorResponse, "description": "Missing or inaccessible resource"}}
WRITE_ERRORS = {**NOT_FOUND, 409: {"model": BusinessErrorResponse, "description": "Name, state, or relationship conflict"}}


async def catalog_error_handler(request: Request, exc: service.CatalogError) -> JSONResponse:
    return JSONResponse(status_code=404 if exc.code == "NOT_FOUND" else 409,
                        content={"detail": {"code": exc.code, "message": str(exc)}})


def _read_definition(definition: ItemDefinition) -> ItemDefinitionRead:
    return ItemDefinitionRead(id=definition.id, name=definition.name, category_id=definition.category_id,
                              status=definition.status,
                              scope="PUBLIC" if definition.owner_user_id is None else "PRIVATE")


@router.get("/item-categories", response_model=ItemCategoryPage, status_code=status.HTTP_200_OK,
            summary="List visible item categories")
async def list_categories(
    query: Annotated[CatalogListQuery, Query()],
    session: AsyncSession = Depends(get_db_session), current_user: User = Depends(get_current_user),
) -> ItemCategoryPage:
    """List public and owned categories alphabetically with state filtering and pagination."""
    items, total = await service.list_categories(session, current_user.id, **query.model_dump())
    return ItemCategoryPage(items=items, total=total, page=query.page, page_size=query.page_size)


@router.post("/item-categories", response_model=ItemCategoryRead, status_code=status.HTTP_201_CREATED,
             responses=WRITE_ERRORS, summary="Create or reuse a visible item category")
async def create_category(
    payload: ItemCategoryCreate, session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ItemCategoryRead:
    """Reuse a visible normalized name, or create a category owned by the current user."""
    return await service.create_category(session, current_user.id, name=payload.name)


@router.get("/item-definitions", response_model=ItemDefinitionPage, status_code=status.HTTP_200_OK,
            summary="List visible item definitions")
async def list_definitions(
    query: Annotated[ItemDefinitionListQuery, Query()],
    session: AsyncSession = Depends(get_db_session), current_user: User = Depends(get_current_user),
) -> ItemDefinitionPage:
    """List public and owned definitions; active lists also require active categories."""
    items, total = await service.list_definitions(session, current_user.id, **query.model_dump())
    return ItemDefinitionPage(items=[_read_definition(item) for item in items], total=total,
                              page=query.page, page_size=query.page_size)


@router.get("/item-definitions/{definition_id}", response_model=ItemDefinitionRead,
            status_code=status.HTTP_200_OK, responses=NOT_FOUND, summary="Read an item definition")
async def get_definition(
    definition_id: UUID, session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ItemDefinitionRead:
    """Read a visible definition without hiding archived definitions or categories."""
    return _read_definition(await service.get_definition(session, definition_id, current_user.id))


@router.post("/item-definitions", response_model=ItemDefinitionRead, status_code=status.HTTP_201_CREATED,
             responses=WRITE_ERRORS, summary="Create a private item definition")
async def create_definition(
    payload: ItemDefinitionCreate, session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ItemDefinitionRead:
    """Create an owned definition in an active category; names remain reserved after archival."""
    return _read_definition(await service.create_definition(session, current_user.id, **payload.model_dump()))


@router.patch("/item-definitions/{definition_id}", response_model=ItemDefinitionRead,
              status_code=status.HTTP_200_OK, responses=WRITE_ERRORS, summary="Edit a private item definition")
async def update_definition(
    definition_id: UUID, payload: ItemDefinitionUpdate, session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ItemDefinitionRead:
    """Edit submitted fields on an owned active definition without rewriting inventory."""
    return _read_definition(await service.update_definition(
        session, definition_id, current_user.id, changes=payload.model_dump(exclude_unset=True)))


@router.post("/item-definitions/{definition_id}/archive", response_model=ItemDefinitionRead,
             status_code=status.HTTP_200_OK, responses=WRITE_ERRORS, dependencies=[Depends(require_empty_body)],
             summary="Archive a private item definition")
async def archive_definition(
    definition_id: UUID, session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ItemDefinitionRead:
    """Archive an owned definition without modifying existing inventory references."""
    return _read_definition(await service.set_definition_status(session, definition_id, current_user.id, target_status="ARCHIVED"))


@router.post("/item-definitions/{definition_id}/restore", response_model=ItemDefinitionRead,
             status_code=status.HTTP_200_OK, responses=WRITE_ERRORS, dependencies=[Depends(require_empty_body)],
             summary="Restore a private item definition")
async def restore_definition(
    definition_id: UUID, session: AsyncSession = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
) -> ItemDefinitionRead:
    """Restore an owned definition only while its category is active, including retries."""
    return _read_definition(await service.set_definition_status(session, definition_id, current_user.id, target_status="ACTIVE"))
