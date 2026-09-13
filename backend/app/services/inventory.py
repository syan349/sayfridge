"""Inventory ownership, snapshot reads, stock creation, and versioned metadata writes."""
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, or_, select, true
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import InventoryItem, ItemCategory, ItemDefinition, StorageSpace
from app.schemas.inventory import InventoryItemRead


class InventoryError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def _select_inventory(user_id):
    return select(
        *InventoryItem.__table__.c,
        StorageSpace.name.label("storage_space_name"),
        ItemDefinition.name.label("item_definition_name"),
        ItemCategory.id.label("category_id"), ItemCategory.name.label("category_name"),
    ).select_from(InventoryItem).join(StorageSpace).join(ItemDefinition).join(ItemCategory).where(
        StorageSpace.user_id == user_id)


def _read_model(row) -> InventoryItemRead:
    values = dict(row)
    estimated = values["estimated_current_amount"] is not None
    values.update(is_estimated=estimated,
                  display_amount=values["estimated_current_amount"] if estimated else values["confirmed_current_amount"],
                  display_unit=values["estimated_current_unit"] if estimated else values["confirmed_current_unit"])
    return InventoryItemRead(**values)


async def get_inventory(session: AsyncSession, item_id: UUID, user_id: UUID) -> InventoryItemRead:
    row = (await session.execute(_select_inventory(user_id).where(InventoryItem.id == item_id))).mappings().one_or_none()
    if row is None:
        raise InventoryError("NOT_FOUND", "Inventory item not found")
    return _read_model(row)


async def list_inventory(session: AsyncSession, user_id: UUID, **query):
    statement = _select_inventory(user_id)
    if query["status"] != "ALL":
        statement = statement.where(InventoryItem.status == query["status"])
    if query["q"]:
        statement = statement.where(ItemDefinition.name.icontains(query["q"], autoescape=True))
    for key, column in (("storage_space_id", InventoryItem.storage_space_id), ("category_id", ItemCategory.id)):
        if query[key] is not None:
            statement = statement.where(column == query[key])
    for prefix, column in (("purchase", InventoryItem.purchase_date), ("expiry", InventoryItem.expiry_date)):
        if query[prefix + "_from"] is not None:
            statement = statement.where(column >= query[prefix + "_from"])
        if query[prefix + "_to"] is not None:
            statement = statement.where(column <= query[prefix + "_to"])
    filtered = statement.cte("filtered_inventory")
    total = select(func.count().label("total")).select_from(filtered).subquery()
    page = (select(filtered).order_by(filtered.c.expiry_date.asc().nulls_last(), filtered.c.id)
            .offset(min((query["page"] - 1) * query["page_size"], 2**63 - 1)).limit(query["page_size"]).subquery())
    rows = (await session.execute(select(page, total.c.total).select_from(total).outerjoin(page, true())
            .order_by(page.c.expiry_date.asc().nulls_last(), page.c.id))).mappings().all()
    return [_read_model(row) for row in rows if row["id"] is not None], rows[0]["total"]


async def _space(session, space_id, user_id):
    space = (await session.execute(select(StorageSpace).where(
        StorageSpace.id == space_id, StorageSpace.user_id == user_id).with_for_update()
        .execution_options(populate_existing=True))).scalar_one_or_none()
    if space is None:
        raise InventoryError("NOT_FOUND", "Storage space not found")
    return space


def _active(row, description):
    if row.status != "ACTIVE":
        raise InventoryError("STATE_CONFLICT", description + " is archived")


async def create_inventory(session: AsyncSession, user_id: UUID, **values) -> InventoryItemRead:
    try:
        planned = (await session.execute(select(ItemDefinition).where(
            ItemDefinition.id == values["item_definition_id"],
            or_(ItemDefinition.owner_user_id.is_(None), ItemDefinition.owner_user_id == user_id),
        ))).scalar_one_or_none()
        if planned is None:
            raise InventoryError("NOT_FOUND", "Item definition not found")
        category_id = planned.category_id
        # Shared lock order: space, category, definition, inventory.
        space = await _space(session, values["storage_space_id"], user_id)
        _active(space, "Storage space")
        category = (await session.execute(select(ItemCategory).where(ItemCategory.id == category_id)
                    .with_for_update().execution_options(populate_existing=True))).scalar_one()
        definition = (await session.execute(select(ItemDefinition).where(ItemDefinition.id == planned.id)
                      .with_for_update().execution_options(populate_existing=True))).scalar_one_or_none()
        if definition is None:
            raise InventoryError("NOT_FOUND", "Item definition not found")
        if definition.category_id != category_id:
            raise InventoryError("RESOURCE_CHANGED", "Item category changed; refresh and retry")
        _active(category, "Item category")
        _active(definition, "Item definition")
        amount, unit = Decimal(values.pop("amount")), values.pop("unit")
        item = InventoryItem(**values, initial_amount=amount, initial_unit=unit,
                             confirmed_current_amount=amount, confirmed_current_unit=unit,
                             confirmed_at=datetime.now(timezone.utc), status="IN_STOCK", version=1)
        session.add(item)
        await session.flush()
        result = await get_inventory(session, item.id, user_id)
        # Stock entry deliberately creates no ADD event in this phase.
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


async def update_inventory(session: AsyncSession, item_id: UUID, user_id: UUID,
                           *, expected_version: int, changes: dict) -> InventoryItemRead:
    try:
        planned = await get_inventory(session, item_id, user_id)
        source_id = planned.storage_space_id
        target_id = changes.get("storage_space_id", source_id)
        spaces = {}
        for space_id in sorted({source_id, target_id}):
            spaces[space_id] = await _space(session, space_id, user_id)
        item = (await session.execute(select(InventoryItem).where(InventoryItem.id == item_id)
                .with_for_update().execution_options(populate_existing=True))).scalar_one_or_none()
        if item is None:
            raise InventoryError("NOT_FOUND", "Inventory item not found")
        if item.storage_space_id != source_id:
            raise InventoryError("RESOURCE_CHANGED", "Inventory location changed; refresh and retry")
        if item.version != expected_version:
            raise InventoryError("VERSION_CONFLICT", "Inventory has changed; refresh and retry")
        if item.status not in {"IN_STOCK", "EMPTY"}:
            raise InventoryError("STATE_CONFLICT", "Terminal inventory cannot be edited")
        if target_id != source_id:
            _active(spaces[target_id], "Target storage space")
        changed = {key: value for key, value in changes.items() if getattr(item, key) != value}
        if changed:
            if item.version == 2147483647:
                raise InventoryError("VERSION_LIMIT_REACHED", "Inventory version limit reached")
            for key, value in changed.items():
                setattr(item, key, value)
            item.version += 1
        await session.flush()
        result = await get_inventory(session, item.id, user_id)
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise
