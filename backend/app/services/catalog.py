"""B05/B06 catalog visibility, normalized names, state rules, and transactions."""
from uuid import UUID

from sqlalchemy import case, func, or_, select, true
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.catalog import normalize_catalog_name
from app.db.models import ItemCategory, ItemDefinition


class CatalogError(Exception):
    """A business error; the route layer owns its HTTP representation."""
    code = "STATE_CONFLICT"


class CatalogNotFoundError(CatalogError):
    code = "NOT_FOUND"


class CatalogNameConflictError(CatalogError):
    code = "NAME_CONFLICT"


class CatalogResourceChangedError(CatalogError):
    code = "RESOURCE_CHANGED"


async def _read_page(session, statement, model, order_fields, page, page_size):
    filtered = statement.cte("filtered_catalog")
    total = select(func.count().label("total")).select_from(filtered).subquery()
    paged = (select(filtered).order_by(*(filtered.c[name] for name in order_fields))
             .offset(min((page - 1) * page_size, 2**63 - 1)).limit(page_size).subquery())
    rows = (await session.execute(
        select(aliased(model, paged), total.c.total).select_from(total)
        .outerjoin(paged, true()).order_by(*(paged.c[name] for name in order_fields))
    )).all()
    # One statement preserves a shared snapshot, including totals for an empty page.
    return [row for row, _ in rows if row is not None], rows[0].total


async def list_categories(session: AsyncSession, *, status: str, page: int, page_size: int):
    statement = select(ItemCategory)
    if status != "ALL":
        statement = statement.where(ItemCategory.status == status)
    return await _read_page(session, statement, ItemCategory, ("sort_order", "name", "id"), page, page_size)


async def list_definitions(
    session: AsyncSession, user_id: UUID, *, status: str, scope: str,
    q: str, category_id: UUID | None, page: int, page_size: int,
):
    scope_column = case((ItemDefinition.owner_user_id.is_(None), "PUBLIC"), else_="PRIVATE").label("scope")
    statement = select(ItemDefinition, scope_column).join(ItemCategory).where(
        or_(ItemDefinition.owner_user_id.is_(None), ItemDefinition.owner_user_id == user_id),
    )
    if status != "ALL":
        statement = statement.where(ItemDefinition.status == status)
    if status == "ACTIVE":
        statement = statement.where(ItemCategory.status == "ACTIVE")
    if scope == "PUBLIC":
        statement = statement.where(ItemDefinition.owner_user_id.is_(None))
    elif scope == "PRIVATE":
        statement = statement.where(ItemDefinition.owner_user_id == user_id)
    if category_id is not None:
        statement = statement.where(ItemDefinition.category_id == category_id)
    if q:
        statement = statement.where(ItemDefinition.name.icontains(q, autoescape=True))
    return await _read_page(session, statement, ItemDefinition, ("name", "scope", "id"), page, page_size)


async def get_definition(
    session: AsyncSession, definition_id: UUID, user_id: UUID, *, own_only: bool = False, lock: bool = False,
) -> ItemDefinition:
    ownership = (ItemDefinition.owner_user_id == user_id) if own_only else or_(
        ItemDefinition.owner_user_id.is_(None), ItemDefinition.owner_user_id == user_id,
    )
    statement = select(ItemDefinition).where(ItemDefinition.id == definition_id, ownership)
    if lock:
        statement = statement.with_for_update().execution_options(populate_existing=True)
    definition = (await session.execute(statement)).scalar_one_or_none()
    if definition is None:
        raise CatalogNotFoundError("Item definition not found")
    return definition


async def _lock_categories(session: AsyncSession, category_ids: set[UUID]) -> dict[UUID, ItemCategory]:
    categories = {}
    for category_id in sorted(category_ids):
        category = (await session.execute(
            select(ItemCategory).where(ItemCategory.id == category_id).with_for_update()
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if category is None:
            raise CatalogNotFoundError("Item category not found")
        categories[category_id] = category
    return categories


def _require_active(category: ItemCategory) -> None:
    if category.status != "ACTIVE":
        raise CatalogError("Item category is archived")


async def _check_name(session: AsyncSession, user_id: UUID, name: str, exclude_id: UUID | None = None) -> str:
    normalized = normalize_catalog_name(name)
    statement = select(ItemDefinition.id, ItemDefinition.name, ItemDefinition.normalized_name).where(
        ItemDefinition.owner_user_id == user_id,
    )
    if exclude_id is not None:
        statement = statement.where(ItemDefinition.id != exclude_id)
    # Archived definitions retain their names. Compare original names as well as
    # stored keys so older normalization formats cannot bypass uniqueness.
    for row in (await session.execute(statement)).all():
        if normalize_catalog_name(row.name) == normalized or row.normalized_name == normalized:
            raise CatalogNameConflictError("A private item definition already uses this name")
    return normalized


async def _commit_definition(session: AsyncSession, definition: ItemDefinition) -> ItemDefinition:
    await session.flush()
    await session.refresh(definition)
    await session.commit()
    return definition


async def _rollback_write(session: AsyncSession, error: Exception) -> None:
    await session.rollback()
    if (isinstance(error, IntegrityError)
            and getattr(error.orig, "sqlstate", None) == "23505"
            and getattr(getattr(error.orig, "diag", None), "constraint_name", None)
            == "uq_item_definition_private_owner_name"):
        raise CatalogNameConflictError("A private item definition already uses this name") from error


async def create_definition(session: AsyncSession, user_id: UUID, *, name: str, category_id: UUID) -> ItemDefinition:
    try:
        categories = await _lock_categories(session, {category_id})
        _require_active(categories[category_id])
        normalized = await _check_name(session, user_id, name)
        definition = ItemDefinition(name=name, normalized_name=normalized, category_id=category_id,
                                    owner_user_id=user_id, status="ACTIVE")
        session.add(definition)
        return await _commit_definition(session, definition)
    except Exception as error:
        await _rollback_write(session, error)
        raise


async def update_definition(session: AsyncSession, definition_id: UUID, user_id: UUID, *, changes: dict) -> ItemDefinition:
    try:
        planned = await get_definition(session, definition_id, user_id, own_only=True)
        original_category = planned.category_id
        target_category = changes.get("category_id", original_category)
        categories = await _lock_categories(session, {original_category, target_category})
        definition = await get_definition(session, definition_id, user_id, own_only=True, lock=True)
        if definition.category_id != original_category:
            raise CatalogResourceChangedError("Item category changed; refresh and retry")
        if definition.status != "ACTIVE":
            raise CatalogError("Restore the item definition before editing it")
        if "category_id" in changes:
            _require_active(categories[target_category])
        if "name" in changes:
            normalized = await _check_name(session, user_id, changes["name"], definition.id)
            # Do not rewrite legacy normalized keys on an unchanged request.
            if definition.name != changes["name"]:
                definition.name = changes["name"]
                definition.normalized_name = normalized
        if definition.category_id != target_category:
            definition.category_id = target_category
        return await _commit_definition(session, definition)
    except Exception as error:
        await _rollback_write(session, error)
        raise


async def set_definition_status(
    session: AsyncSession, definition_id: UUID, user_id: UUID, *, target_status: str,
) -> ItemDefinition:
    try:
        planned = await get_definition(session, definition_id, user_id, own_only=True)
        original_category = planned.category_id
        categories = await _lock_categories(session, {original_category})
        definition = await get_definition(session, definition_id, user_id, own_only=True, lock=True)
        if definition.category_id != original_category:
            raise CatalogResourceChangedError("Item category changed; refresh and retry")
        if target_status == "ACTIVE":
            _require_active(categories[original_category])
        if definition.status != target_status:
            definition.status = target_status
        return await _commit_definition(session, definition)
    except Exception as error:
        await _rollback_write(session, error)
        raise
