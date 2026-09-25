"""Storage-space queries, ownership checks, state transitions, and transactions."""
from uuid import UUID

from sqlalchemy import exists, func, select, true
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.db.models import InventoryItem, StorageSpace


class StorageSpaceError(Exception):
    """Business failure translated into an HTTP response by the route layer."""


class SpaceNotFoundError(StorageSpaceError):
    pass


class SpaceNameConflictError(StorageSpaceError):
    pass


class SpaceStateConflictError(StorageSpaceError):
    pass


async def get_storage_space_by_id(
    session: AsyncSession, space_id: UUID, user_id: UUID, *, lock: bool = False,
) -> StorageSpace:
    statement = select(StorageSpace).where(
        StorageSpace.id == space_id, StorageSpace.user_id == user_id,
    )
    if lock:
        # Refresh cached values after waiting for another transaction's row lock.
        statement = statement.with_for_update().execution_options(populate_existing=True)
    space = (await session.execute(statement)).scalar_one_or_none()
    if space is None:
        raise SpaceNotFoundError("Storage space not found")
    return space


async def list_storage_spaces(
    session: AsyncSession, user_id: UUID, *, status: str, page: int, page_size: int,
) -> tuple[list[StorageSpace], int]:
    statement = select(StorageSpace).where(StorageSpace.user_id == user_id)
    if status != "ALL":
        statement = statement.where(StorageSpace.status == status)
    filtered = statement.cte("filtered_spaces")
    total = select(func.count().label("total")).select_from(filtered).subquery()
    # A left join keeps the count even when the requested page is empty.
    # One SQL statement gives the count and rows the same READ COMMITTED snapshot.
    paged = (
        select(filtered).order_by(filtered.c.name, filtered.c.id)
        .offset(min((page - 1) * page_size, 2**63 - 1)).limit(page_size).subquery()
    )
    space_model = aliased(StorageSpace, paged)
    rows = (await session.execute(
        select(space_model, total.c.total).select_from(total)
        .outerjoin(paged, true()).order_by(paged.c.name, paged.c.id)
    )).all()
    return [space for space, _ in rows if space is not None], rows[0].total


async def _commit_space(session: AsyncSession, space: StorageSpace, *, commit: bool = True) -> StorageSpace:
    await session.flush()
    # Read server timestamps while the write's locks are still held.
    await session.refresh(space)
    if commit:
        await session.commit()
    return space


async def _rollback_write(session: AsyncSession, error: Exception) -> None:
    await session.rollback()
    if (
        isinstance(error, IntegrityError)
        and getattr(error.orig, "sqlstate", None) == "23505"
        and getattr(getattr(error.orig, "diag", None), "constraint_name", None)
        == "uq_storage_space_active_user_name"
    ):
        # PostgreSQL's unique index also arbitrates concurrent creates/restores/renames.
        raise SpaceNameConflictError("An active storage space already uses this name") from error


async def create_storage_space(
    session: AsyncSession, user_id: UUID, *, name: str, type: str, commit: bool = True,
) -> StorageSpace:
    try:
        space = StorageSpace(user_id=user_id, name=name, type=type, status="ACTIVE")
        session.add(space)
        return await _commit_space(session, space, commit=commit)
    except Exception as error:
        await _rollback_write(session, error)
        raise


async def update_storage_space(
    session: AsyncSession, space_id: UUID, user_id: UUID, *, changes: dict[str, str],
) -> StorageSpace:
    try:
        space = await get_storage_space_by_id(session, space_id, user_id, lock=True)
        if space.status != "ACTIVE":
            raise SpaceStateConflictError("Restore the storage space before editing it")
        for field, value in changes.items():
            if getattr(space, field) != value:
                setattr(space, field, value)
        # SQLAlchemy emits no UPDATE for unchanged values, preserving updated_at.
        return await _commit_space(session, space)
    except Exception as error:
        await _rollback_write(session, error)
        raise


async def set_storage_space_status(
    session: AsyncSession, space_id: UUID, user_id: UUID, *, target_status: str,
) -> StorageSpace:
    try:
        space = await get_storage_space_by_id(session, space_id, user_id, lock=True)
        if space.status != target_status:
            if target_status == "ARCHIVED":
                # Inventory writers must lock this same space row before changing stock.
                has_stock = await session.scalar(select(exists().where(
                    InventoryItem.storage_space_id == space.id,
                    InventoryItem.status == "IN_STOCK",
                )))
                if has_stock:
                    raise SpaceStateConflictError("Storage space still contains in-stock inventory")
            space.status = target_status
        return await _commit_space(session, space)
    except Exception as error:
        await _rollback_write(session, error)
        raise
