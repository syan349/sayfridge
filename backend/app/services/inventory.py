"""Inventory ownership, reads, creation, quantity operations, and versioned writes."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID, uuid4

from sqlalchemy import case, func, literal, or_, select, true
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import aliased
from sqlalchemy.dialects.postgresql import insert

from app.db.models import InventoryItem, InventoryOperation, ItemCategory, ItemDefinition, StorageSpace
from app.schemas.inventory import ExpirySummaryItem, InventoryItemRead
from app.schemas.inventory_operations import InventoryOperationRead, OperationResult
from app.services.inventory_quantities import calculate_addition, calculate_consumption, prepare_reconciliation
from app.core.quantity import QuantityError
from app.core.catalog import normalize_catalog_name
from app.services.catalog import category_visibility


class InventoryError(Exception):
    def __init__(self, code: str, message: str, *, item_index: int | None = None):
        super().__init__(message)
        self.code = code
        self.item_index = item_index


def _select_inventory(user_id):
    return select(
        *InventoryItem.__table__.c,
        StorageSpace.name.label("storage_space_name"),
        ItemDefinition.name.label("item_definition_name"),
        ItemCategory.id.label("category_id"), ItemCategory.name.label("category_name"),
    ).select_from(InventoryItem).join(StorageSpace).join(ItemDefinition).join(
        ItemCategory, ItemCategory.id == func.coalesce(InventoryItem.category_override_id, ItemDefinition.category_id)
    ).where(
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


async def get_expiry_summary(session: AsyncSession, user_id: UUID, **query):
    """Return expiry counts and one detail page from the same database statement."""
    window_end = query["as_of"] + timedelta(days=query["days_before"])
    bucket = case(
        (InventoryItem.expiry_date < query["as_of"], literal("overdue")),
        (InventoryItem.expiry_date == query["as_of"], literal("today")),
        else_=literal("upcoming"),
    ).label("bucket")
    statement = _select_inventory(user_id).add_columns(bucket).where(
        InventoryItem.status == "IN_STOCK",
        InventoryItem.expiry_date.is_not(None),
        InventoryItem.expiry_date <= window_end,
    )
    for key, column in (
        ("storage_space_id", InventoryItem.storage_space_id),
        ("category_id", ItemCategory.id),
    ):
        if query[key] is not None:
            statement = statement.where(column == query[key])

    all_buckets = statement.cte("expiry_inventory")
    counts = select(
        func.count().filter(all_buckets.c.bucket == "overdue").label("overdue"),
        func.count().filter(all_buckets.c.bucket == "today").label("today"),
        func.count().filter(all_buckets.c.bucket == "upcoming").label("upcoming"),
    ).select_from(all_buckets).subquery()

    filtered = select(all_buckets)
    if query["bucket"] is not None:
        filtered = filtered.where(all_buckets.c.bucket == query["bucket"])
    filtered = filtered.cte("filtered_expiry_inventory")
    total = select(func.count()).select_from(filtered).scalar_subquery().label("total")
    page = (
        select(filtered)
        .order_by(filtered.c.expiry_date, filtered.c.id)
        .offset(min((query["page"] - 1) * query["page_size"], 2**63 - 1))
        .limit(query["page_size"])
        .subquery()
    )
    rows = (await session.execute(
        select(page, counts.c.overdue, counts.c.today, counts.c.upcoming, total)
        .select_from(counts)
        .outerjoin(page, true())
        .order_by(page.c.expiry_date, page.c.id)
    )).mappings().all()
    items = [
        ExpirySummaryItem(
            **_read_model(row).model_dump(),
            bucket=row["bucket"],
        )
        for row in rows
        if row["id"] is not None
    ]
    first = rows[0]
    return items, {
        "overdue": first["overdue"],
        "today": first["today"],
        "upcoming": first["upcoming"],
    }, first["total"]


async def list_inventory_operations(
    session: AsyncSession,
    item_id: UUID,
    user_id: UUID,
) -> list[InventoryOperation]:
    """Read every operation for one owned inventory item in deterministic newest-first order."""
    await get_inventory(session, item_id, user_id)
    result = await session.scalars(
        select(InventoryOperation)
        .where(InventoryOperation.inventory_item_id == item_id)
        .order_by(InventoryOperation.created_at.desc(), InventoryOperation.id.desc())
    )
    return list(result.all())


def _select_owned_operations(user_id: UUID):
    return (
        select(InventoryOperation)
        .join(InventoryItem, InventoryOperation.inventory_item_id == InventoryItem.id)
        .join(StorageSpace, InventoryItem.storage_space_id == StorageSpace.id)
        .where(StorageSpace.user_id == user_id)
    )


async def list_owned_inventory_operations(session: AsyncSession, user_id: UUID, **query):
    """Read one deterministic page of operation history visible to the current user."""
    statement = _select_owned_operations(user_id)
    for key, column in (
        ("inventory_item_id", InventoryOperation.inventory_item_id),
        ("operation_type", InventoryOperation.operation_type),
        ("status", InventoryOperation.status),
    ):
        if query[key] is not None:
            statement = statement.where(column == query[key])
    if query["created_from"] is not None:
        statement = statement.where(InventoryOperation.created_at >= query["created_from"])
    if query["created_to"] is not None:
        statement = statement.where(InventoryOperation.created_at < query["created_to"])

    filtered = statement.cte("filtered_inventory_operations")
    total = select(func.count().label("total")).select_from(filtered).subquery()
    page = (
        select(filtered)
        .order_by(filtered.c.created_at.desc(), filtered.c.id.desc())
        .offset(min((query["page"] - 1) * query["page_size"], 2**63 - 1))
        .limit(query["page_size"])
        .subquery()
    )
    operation_model = aliased(InventoryOperation, page)
    rows = (await session.execute(
        select(operation_model, total.c.total)
        .select_from(total)
        .outerjoin(page, true())
        .order_by(page.c.created_at.desc(), page.c.id.desc())
    )).all()
    return [operation for operation, _ in rows if operation is not None], rows[0].total


async def get_inventory_operation(
    session: AsyncSession,
    operation_id: UUID,
    user_id: UUID,
) -> InventoryOperation:
    """Read one operation through its inventory ownership chain."""
    operation = (await session.execute(
        _select_owned_operations(user_id).where(InventoryOperation.id == operation_id)
    )).scalar_one_or_none()
    if operation is None:
        raise InventoryError("NOT_FOUND", "Inventory operation not found")
    return operation


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


async def create_inventory(session: AsyncSession, user_id: UUID, *, commit: bool = True, **values) -> InventoryItemRead:
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
        category = (await session.execute(select(ItemCategory).where(ItemCategory.id == category_id, category_visibility(user_id))
                    .with_for_update().execution_options(populate_existing=True))).scalar_one_or_none()
        if category is None:
            raise InventoryError("NOT_FOUND", "Item category not found")
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
        if commit:
            await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


def _batch_error(error: InventoryError, item_index: int) -> InventoryError:
    """Attach the first failing request position without changing its business code."""
    if error.item_index is None:
        error.item_index = item_index
    return error


async def create_inventory_batch(
    session: AsyncSession,
    user_id: UUID,
    items: list[dict],
) -> list[InventoryItemRead]:
    """Create 1–100 stock rows in one transaction and preserve request order."""
    try:
        definition_ids = {values["item_definition_id"] for values in items}
        space_ids = {values["storage_space_id"] for values in items}
        planned_definitions = {
            definition.id: definition
            for definition in (await session.scalars(
                select(ItemDefinition).where(
                    ItemDefinition.id.in_(definition_ids),
                    or_(
                        ItemDefinition.owner_user_id.is_(None),
                        ItemDefinition.owner_user_id == user_id,
                    ),
                )
            )).all()
        }
        planned_spaces = {
            space.id: space
            for space in (await session.scalars(
                select(StorageSpace).where(
                    StorageSpace.id.in_(space_ids),
                    StorageSpace.user_id == user_id,
                )
            )).all()
        }
        category_ids = {definition.category_id for definition in planned_definitions.values()}
        planned_categories = {
            category.id: category
            for category in (await session.scalars(
                select(ItemCategory).where(ItemCategory.id.in_(category_ids), category_visibility(user_id))
            )).all()
        }

        planned_category_ids: list[UUID] = []
        for item_index, values in enumerate(items):
            space = planned_spaces.get(values["storage_space_id"])
            if space is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Storage space not found",
                    item_index=item_index,
                )
            definition = planned_definitions.get(values["item_definition_id"])
            if definition is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Item definition not found",
                    item_index=item_index,
                )
            category = planned_categories.get(definition.category_id)
            if category is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Item category not found",
                    item_index=item_index,
                )
            for resource, description in (
                (space, "Storage space"),
                (category, "Item category"),
                (definition, "Item definition"),
            ):
                try:
                    _active(resource, description)
                except InventoryError as error:
                    raise _batch_error(error, item_index)
            planned_category_ids.append(definition.category_id)

        # Acquire every row in the same resource/id order used by other inventory writes.
        spaces: dict[UUID, StorageSpace] = {}
        for space_id in sorted(space_ids):
            space = (await session.execute(
                select(StorageSpace)
                .where(StorageSpace.id == space_id, StorageSpace.user_id == user_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if space is not None:
                spaces[space_id] = space

        categories: dict[UUID, ItemCategory] = {}
        for category_id in sorted(set(planned_category_ids)):
            category = (await session.execute(
                select(ItemCategory)
                .where(ItemCategory.id == category_id, category_visibility(user_id))
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if category is not None:
                categories[category_id] = category

        definitions: dict[UUID, ItemDefinition] = {}
        for definition_id in sorted(definition_ids):
            definition = (await session.execute(
                select(ItemDefinition)
                .where(ItemDefinition.id == definition_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if definition is not None:
                definitions[definition_id] = definition

        now = datetime.now(timezone.utc)
        created: list[InventoryItem] = []
        for item_index, (submitted, category_id) in enumerate(zip(items, planned_category_ids)):
            values = dict(submitted)
            space = spaces.get(values["storage_space_id"])
            if space is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Storage space not found",
                    item_index=item_index,
                )
            definition = definitions.get(values["item_definition_id"])
            if definition is None or (
                definition.owner_user_id is not None and definition.owner_user_id != user_id
            ):
                raise InventoryError(
                    "NOT_FOUND",
                    "Item definition not found",
                    item_index=item_index,
                )
            if definition.category_id != category_id:
                raise InventoryError(
                    "RESOURCE_CHANGED",
                    "Item category changed; refresh and retry",
                    item_index=item_index,
                )
            category = categories.get(category_id)
            if category is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Item category not found",
                    item_index=item_index,
                )
            for resource, description in (
                (space, "Storage space"),
                (category, "Item category"),
                (definition, "Item definition"),
            ):
                try:
                    _active(resource, description)
                except InventoryError as error:
                    raise _batch_error(error, item_index)
            amount = Decimal(values.pop("amount"))
            unit = values.pop("unit")
            created.append(InventoryItem(
                **values,
                initial_amount=amount,
                initial_unit=unit,
                confirmed_current_amount=amount,
                confirmed_current_unit=unit,
                confirmed_at=now,
                status="IN_STOCK",
                version=1,
            ))

        session.add_all(created)
        await session.flush()
        rows = (await session.execute(
            _select_inventory(user_id).where(
                InventoryItem.id.in_([item.id for item in created])
            )
        )).mappings().all()
        by_id = {row["id"]: _read_model(row) for row in rows}
        result = [by_id[item.id] for item in created]
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


async def move_inventory_batch(
    session: AsyncSession,
    user_id: UUID,
    *,
    target_storage_space_id: UUID,
    items: list[dict],
) -> list[InventoryItemRead]:
    """Move versioned inventory references to one space in a single transaction."""
    try:
        seen: set[UUID] = set()
        for item_index, reference in enumerate(items):
            if reference["id"] in seen:
                raise InventoryError(
                    "VALIDATION_ERROR",
                    "Duplicate inventory item ID",
                    item_index=item_index,
                )
            seen.add(reference["id"])

        planned_target = (await session.execute(
            select(StorageSpace).where(
                StorageSpace.id == target_storage_space_id,
                StorageSpace.user_id == user_id,
            )
        )).scalar_one_or_none()
        if planned_target is None:
            raise InventoryError("NOT_FOUND", "Target storage space not found")
        _active(planned_target, "Target storage space")

        item_ids = {reference["id"] for reference in items}
        planned_items = {
            item.id: item
            for item in (await session.scalars(
                select(InventoryItem)
                .join(StorageSpace)
                .where(
                    InventoryItem.id.in_(item_ids),
                    StorageSpace.user_id == user_id,
                )
            )).all()
        }
        planned_source_ids: list[UUID] = []
        for item_index, reference in enumerate(items):
            item = planned_items.get(reference["id"])
            if item is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Inventory item not found",
                    item_index=item_index,
                )
            if item.version != reference["expected_version"]:
                raise InventoryError(
                    "VERSION_CONFLICT",
                    "Inventory has changed; refresh and retry",
                    item_index=item_index,
                )
            if item.status not in {"IN_STOCK", "EMPTY"}:
                raise InventoryError(
                    "STATE_CONFLICT",
                    "Terminal inventory cannot be moved",
                    item_index=item_index,
                )
            planned_source_ids.append(item.storage_space_id)

        space_ids = set(planned_source_ids) | {target_storage_space_id}
        locked_spaces: dict[UUID, StorageSpace] = {}
        for space_id in sorted(space_ids):
            space = (await session.execute(
                select(StorageSpace)
                .where(StorageSpace.id == space_id, StorageSpace.user_id == user_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if space is not None:
                locked_spaces[space_id] = space

        locked_items: dict[UUID, InventoryItem] = {}
        for item_id in sorted(item_ids):
            item = (await session.execute(
                select(InventoryItem)
                .where(InventoryItem.id == item_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if item is not None:
                locked_items[item_id] = item

        target = locked_spaces.get(target_storage_space_id)
        if target is None:
            raise InventoryError("NOT_FOUND", "Target storage space not found")
        _active(target, "Target storage space")

        ordered_items: list[InventoryItem] = []
        for item_index, (reference, planned_source_id) in enumerate(
            zip(items, planned_source_ids)
        ):
            item = locked_items.get(reference["id"])
            if item is None or planned_source_id not in locked_spaces:
                raise InventoryError(
                    "NOT_FOUND",
                    "Inventory item not found",
                    item_index=item_index,
                )
            if item.storage_space_id != planned_source_id:
                raise InventoryError(
                    "RESOURCE_CHANGED",
                    "Inventory location changed; refresh and retry",
                    item_index=item_index,
                )
            if item.version != reference["expected_version"]:
                raise InventoryError(
                    "VERSION_CONFLICT",
                    "Inventory has changed; refresh and retry",
                    item_index=item_index,
                )
            if item.status not in {"IN_STOCK", "EMPTY"}:
                raise InventoryError(
                    "STATE_CONFLICT",
                    "Terminal inventory cannot be moved",
                    item_index=item_index,
                )
            if item.storage_space_id != target_storage_space_id:
                if item.version == 2147483647:
                    raise InventoryError(
                        "VERSION_LIMIT_REACHED",
                        "Inventory version limit reached",
                        item_index=item_index,
                    )
                item.storage_space_id = target_storage_space_id
                item.version += 1
            ordered_items.append(item)

        await session.flush()
        rows = (await session.execute(
            _select_inventory(user_id).where(
                InventoryItem.id.in_([item.id for item in ordered_items])
            )
        )).mappings().all()
        by_id = {row["id"]: _read_model(row) for row in rows}
        result = [by_id[item.id] for item in ordered_items]
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


async def archive_inventory_batch(
    session: AsyncSession,
    user_id: UUID,
    *,
    items: list[dict],
) -> list[InventoryItemRead]:
    """Archive versioned inventory references in one all-or-nothing transaction."""
    try:
        item_ids: set[UUID] = set()
        for item_index, reference in enumerate(items):
            if reference["id"] in item_ids:
                raise InventoryError(
                    "VALIDATION_ERROR",
                    "Duplicate inventory item ID",
                    item_index=item_index,
                )
            item_ids.add(reference["id"])

        planned_items = {
            item.id: item
            for item in (await session.scalars(
                select(InventoryItem)
                .join(StorageSpace)
                .where(
                    InventoryItem.id.in_(item_ids),
                    StorageSpace.user_id == user_id,
                )
            )).all()
        }
        planned_source_ids: list[UUID] = []
        for item_index, reference in enumerate(items):
            item = planned_items.get(reference["id"])
            if item is None:
                raise InventoryError(
                    "NOT_FOUND",
                    "Inventory item not found",
                    item_index=item_index,
                )
            if item.version != reference["expected_version"]:
                raise InventoryError(
                    "VERSION_CONFLICT",
                    "Inventory has changed; refresh and retry",
                    item_index=item_index,
                )
            if item.status not in {"IN_STOCK", "EMPTY"}:
                raise InventoryError(
                    "STATE_CONFLICT",
                    "Only in-stock or empty inventory can be archived",
                    item_index=item_index,
                )
            planned_source_ids.append(item.storage_space_id)

        locked_spaces: dict[UUID, StorageSpace] = {}
        for space_id in sorted(set(planned_source_ids)):
            space = (await session.execute(
                select(StorageSpace)
                .where(StorageSpace.id == space_id, StorageSpace.user_id == user_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if space is not None:
                locked_spaces[space_id] = space

        locked_items: dict[UUID, InventoryItem] = {}
        for item_id in sorted(item_ids):
            item = (await session.execute(
                select(InventoryItem)
                .where(InventoryItem.id == item_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )).scalar_one_or_none()
            if item is not None:
                locked_items[item_id] = item

        ordered_items: list[InventoryItem] = []
        for item_index, (reference, planned_source_id) in enumerate(
            zip(items, planned_source_ids)
        ):
            item = locked_items.get(reference["id"])
            if item is None or planned_source_id not in locked_spaces:
                raise InventoryError(
                    "NOT_FOUND",
                    "Inventory item not found",
                    item_index=item_index,
                )
            if item.storage_space_id != planned_source_id:
                raise InventoryError(
                    "RESOURCE_CHANGED",
                    "Inventory location changed; refresh and retry",
                    item_index=item_index,
                )
            if item.version != reference["expected_version"]:
                raise InventoryError(
                    "VERSION_CONFLICT",
                    "Inventory has changed; refresh and retry",
                    item_index=item_index,
                )
            if item.status not in {"IN_STOCK", "EMPTY"}:
                raise InventoryError(
                    "STATE_CONFLICT",
                    "Only in-stock or empty inventory can be archived",
                    item_index=item_index,
                )
            if item.version == 2147483647:
                raise InventoryError(
                    "VERSION_LIMIT_REACHED",
                    "Inventory version limit reached",
                    item_index=item_index,
                )
            item.status = "ARCHIVED"
            item.version += 1
            ordered_items.append(item)

        await session.flush()
        rows = (await session.execute(
            _select_inventory(user_id).where(
                InventoryItem.id.in_([item.id for item in ordered_items])
            )
        )).mappings().all()
        by_id = {row["id"]: _read_model(row) for row in rows}
        result = [by_id[item.id] for item in ordered_items]
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


async def _item_name_definition(session, user_id, category_id, name):
    """Associate this batch with a private name, leaving other batches unchanged."""
    category = (await session.execute(select(ItemCategory).where(
        ItemCategory.id == category_id, category_visibility(user_id)).with_for_update())).scalar_one_or_none()
    if category is None or category.status != "ACTIVE":
        raise InventoryError("STATE_CONFLICT", "The item category must be active to rename this batch")
    normalized = normalize_catalog_name(name)
    if not 1 <= len(normalized) <= 100:
        raise InventoryError("VALIDATION_ERROR", "Item name is too long")
    await session.execute(insert(ItemDefinition).values(
        id=uuid4(), owner_user_id=user_id, category_id=category_id,
        name=name, normalized_name=normalized, status="ACTIVE",
    ).on_conflict_do_nothing(
        index_elements=[ItemDefinition.owner_user_id, ItemDefinition.normalized_name],
        index_where=ItemDefinition.owner_user_id.is_not(None),
    ))
    definition = (await session.execute(select(ItemDefinition).where(
        ItemDefinition.owner_user_id == user_id,
        ItemDefinition.normalized_name == normalized,
    ).with_for_update())).scalar_one()
    if definition.status != "ACTIVE" or definition.category_id != category_id:
        raise InventoryError("NAME_CONFLICT", "This name is already used by another category or archived item")
    return definition.id


def _edit_quantity(item, quantity, space):
    """Apply a measured reconciliation or freeze the existing displayed estimate."""
    now = datetime.now(timezone.utc)
    if quantity["mode"] == "ESTIMATED":
        if item.estimated_current_amount is not None:
            return None
        if item.status == "EMPTY":
            raise InventoryError("STATE_CONFLICT", "An empty batch requires a measured quantity")
        item.estimated_current_amount = item.confirmed_current_amount
        item.estimated_current_unit = item.confirmed_current_unit
        item.estimated_at = now
        return None
    amount, unit = prepare_reconciliation(Decimal(quantity["amount"]), quantity["unit"])
    if item.status == "EMPTY" and amount > 0:
        _active(space, "Storage space")
    item.confirmed_current_amount, item.confirmed_current_unit = amount, unit
    item.confirmed_at = now
    item.estimated_current_amount = item.estimated_current_unit = item.estimated_at = None
    item.status = "EMPTY" if amount == 0 else "IN_STOCK"
    return InventoryOperation(
        inventory_item_id=item.id, operation_type="RECONCILE", quantity_kind="AMOUNT",
        quantity_value=quantity["amount"], quantity_unit=unit, input_method="MANUAL",
        calculation_method="EXACT", affects_state="CONFIRMED", status="SUCCESS",
        idempotency_key=f"detail-edit:{uuid4().hex}",
    )


async def update_inventory(session: AsyncSession, item_id: UUID, user_id: UUID,
                           *, expected_version: int, changes: dict) -> InventoryItemRead:
    try:
        changes = dict(changes)
        item_name = changes.pop("item_name", None)
        quantity = changes.pop("quantity", None)
        category_id = changes.pop("category_id", None)
        planned = await get_inventory(session, item_id, user_id)
        source_id = planned.storage_space_id
        target_id = changes.get("storage_space_id", source_id)
        spaces = {}
        for space_id in sorted({source_id, target_id}):
            spaces[space_id] = await _space(session, space_id, user_id)
        category_changed = category_id is not None and category_id != planned.category_id
        effective_category_id = category_id or planned.category_id
        if category_changed or (item_name is not None and item_name != planned.item_definition_name):
            category_ids = {planned.category_id}
            if category_changed:
                category_ids.add(category_id)
            for target_category in sorted(category_ids):
                category = await session.scalar(select(ItemCategory).where(
                    ItemCategory.id == target_category, category_visibility(user_id),
                ).with_for_update())
                if category is None:
                    raise InventoryError("NOT_FOUND", "Item category not found")
                if target_category == effective_category_id:
                    _active(category, "Item category")
            if category_changed:
                changes["category_override_id"] = category_id
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
        if item_name is not None and item_name != planned.item_definition_name:
            changes["item_definition_id"] = await _item_name_definition(
                session, user_id, effective_category_id, item_name)
        changed = {key: value for key, value in changes.items() if getattr(item, key) != value}
        quantity_changed = quantity is not None and (
            quantity["mode"] == "EXACT" or item.estimated_current_amount is None)
        if changed or quantity_changed:
            if item.version == 2147483647:
                raise InventoryError("VERSION_LIMIT_REACHED", "Inventory version limit reached")
            for key, value in changed.items():
                setattr(item, key, value)
            if quantity_changed:
                operation = _edit_quantity(item, quantity, spaces[target_id])
                if operation is not None:
                    session.add(operation)
            item.version += 1
        await session.flush()
        result = await get_inventory(session, item.id, user_id)
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


async def _transition_inventory_state(
    session: AsyncSession,
    item_id: UUID,
    user_id: UUID,
    *,
    expected_version: int,
    target_status: str,
    allowed_statuses: set[str],
    conflict_message: str,
) -> InventoryItemRead:
    """Apply one locked, version-checked terminal inventory transition."""
    try:
        planned = await get_inventory(session, item_id, user_id)
        space = await _space(session, planned.storage_space_id, user_id)
        item = (await session.execute(
            select(InventoryItem)
            .where(InventoryItem.id == item_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if item is None:
            raise InventoryError("NOT_FOUND", "Inventory item not found")
        if item.storage_space_id != space.id:
            raise InventoryError("RESOURCE_CHANGED", "Inventory location changed; refresh and retry")
        if item.version != expected_version:
            raise InventoryError("VERSION_CONFLICT", "Inventory has changed; refresh and retry")
        if item.status not in allowed_statuses:
            raise InventoryError("STATE_CONFLICT", conflict_message)
        if item.version == 2147483647:
            raise InventoryError("VERSION_LIMIT_REACHED", "Inventory version limit reached")
        item.status = target_status
        item.version += 1
        await session.flush()
        result = await get_inventory(session, item.id, user_id)
        await session.commit()
        return result
    except Exception:
        await session.rollback()
        raise


async def discard_inventory(
    session: AsyncSession,
    item_id: UUID,
    user_id: UUID,
    *,
    expected_version: int,
) -> InventoryItemRead:
    """Move owned IN_STOCK inventory to the terminal DISCARDED state."""
    return await _transition_inventory_state(
        session,
        item_id,
        user_id,
        expected_version=expected_version,
        target_status="DISCARDED",
        allowed_statuses={"IN_STOCK"},
        conflict_message="Only in-stock inventory can be discarded",
    )


async def archive_inventory(
    session: AsyncSession,
    item_id: UUID,
    user_id: UUID,
    *,
    expected_version: int,
) -> InventoryItemRead:
    """Move owned IN_STOCK or EMPTY inventory to the terminal ARCHIVED state."""
    return await _transition_inventory_state(
        session,
        item_id,
        user_id,
        expected_version=expected_version,
        target_status="ARCHIVED",
        allowed_statuses={"IN_STOCK", "EMPTY"},
        conflict_message="Only in-stock or empty inventory can be archived",
    )

async def _load_inventory_for_operation(session:AsyncSession, item_id:UUID, user_id:UUID) -> tuple[InventoryItem, StorageSpace]:
    inventory = await get_inventory(session, item_id, user_id)
    space = await _space(session, inventory.storage_space_id, user_id)

    locked_item = (await session.execute(select(InventoryItem).where(InventoryItem.id == item_id)
        .with_for_update().execution_options(populate_existing=True))).scalar_one_or_none()

    if locked_item is None:
        raise InventoryError("NOT_FOUND", "Inventory item not found")
    if locked_item.storage_space_id != space.id:
        raise InventoryError("RESOURCE_CHANGED", "Inventory location changed; refresh and retry")

    return (locked_item, space)


def _validate_new_operation(item: InventoryItem, space: StorageSpace, expected_version: int, operation_type: str) -> None:
    if item.version != expected_version:
        raise InventoryError("VERSION_CONFLICT", "Inventory has changed; refresh and retry")
    if operation_type in {"ADD", "RECONCILE"}:
        allowed = {"IN_STOCK", "EMPTY"}
    else:
        allowed = {"IN_STOCK"}
    if item.status not in allowed:
        raise InventoryError("STATE_CONFLICT", "Inventory state does not allow this operation")
    if operation_type == "ADD" and item.status == "EMPTY":
        _active(space, "Storage space")
    if item.version == 2147483647:
        raise InventoryError("VERSION_LIMIT_REACHED", "Inventory version limit reached")


async def _operation_by_key(session: AsyncSession, key: str) -> InventoryOperation | None:
    return (await session.execute(select(InventoryOperation).where(
        InventoryOperation.idempotency_key == key
    ).execution_options(populate_existing=True))).scalar_one_or_none()


async def _operation_replay(session, operation, item_id, user_id, operation_type, quantity_kind, quantity_value, quantity_unit):
    # Compare literal business input, excluding expected_version. Never reapply a
    # failed or undone historical record, and never expose its internal key.
    if operation.status != "SUCCESS" or (
        operation.inventory_item_id, operation.operation_type, operation.quantity_kind,
        operation.quantity_value, operation.quantity_unit,
    ) != (item_id, operation_type, quantity_kind, quantity_value, quantity_unit):
        raise InventoryError("IDEMPOTENCY_CONFLICT", "Key is already associated with a different request")
    inventory = await get_inventory(session, item_id, user_id)
    return OperationResult(operation=InventoryOperationRead.model_validate(operation),
                           inventory=inventory, replayed=True)


async def submit_inventory_operation(session: AsyncSession, item_id: UUID, user_id: UUID, *,
                        expected_version: int, operation_type: str, quantity_kind: str,
                        quantity_value: str, quantity_unit: str, idempotency_key: str,
                        commit: bool = True, input_method: str = "MANUAL",
                        unit_relationship: dict | None = None,
                        estimated_change: tuple[Decimal, str] | None = None) -> OperationResult:
    """Apply one ADD/CONSUME/RECONCILE atomically, or return its prior record and current inventory.

    The route passes schema-validated input. Only this outer service commits or
    rolls back. Database uniqueness also protects a key reused across spaces.
    """
    if operation_type not in {"ADD", "CONSUME", "RECONCILE"} or quantity_kind not in ({"AMOUNT", "FRACTION", "QUALITATIVE"} if estimated_change else {"AMOUNT", "FRACTION"}):
        raise InventoryError("VALIDATION_ERROR", "Unsupported operation or quantity kind")
    if operation_type == "ADD" and quantity_kind != "AMOUNT" and estimated_change is None:
        raise InventoryError("VALIDATION_ERROR", "ADD requires AMOUNT")
    if operation_type == "RECONCILE" and quantity_kind != "AMOUNT":
        raise InventoryError("VALIDATION_ERROR", "RECONCILE requires AMOUNT")
    key = f"{user_id}:{idempotency_key}"
    try:
        try:
            await get_inventory(session, item_id, user_id)
            operation = await _operation_by_key(session, key)
            if operation is not None:
                result = await _operation_replay(session, operation, item_id, user_id, operation_type, quantity_kind,
                                                quantity_value, quantity_unit)
            else:
                item, space = await _load_inventory_for_operation(session, item_id, user_id)
                # A matching request may have committed while this request waited.
                operation = await _operation_by_key(session, key)
                if operation is not None:
                    result = await _operation_replay(session, operation, item_id, user_id, operation_type, quantity_kind,
                                                    quantity_value, quantity_unit)
                else:
                    _validate_new_operation(item, space, expected_version, operation_type)
                    now = datetime.now(timezone.utc)

                    if unit_relationship is not None and operation_type != "RECONCILE":
                        from app.services.inventory_quantities import calculate_change
                        calculation = calculate_change(item, operation_type, quantity_kind, quantity_value,
                                                       quantity_unit, relationship=unit_relationship)
                    elif estimated_change is not None:
                        from app.services.inventory_quantities import calculate_estimated_change
                        calculation = calculate_estimated_change(item, operation_type, *estimated_change)
                    elif operation_type == "ADD":
                        calculation = calculate_addition(item, Decimal(quantity_value), quantity_unit)
                    elif operation_type == "CONSUME":
                        calculation = calculate_consumption(item, quantity_kind, quantity_value, quantity_unit)
                    elif operation_type == "RECONCILE":
                        reconciled_amount, reconciled_unit = prepare_reconciliation(
                            Decimal(quantity_value), quantity_unit
                        )

                    if operation_type == "RECONCILE":
                        if item.status == "EMPTY" and reconciled_amount > 0:
                            _active(space, "Storage space")
                        item.confirmed_current_amount = reconciled_amount
                        item.confirmed_current_unit = reconciled_unit
                        item.confirmed_at = now
                        item.estimated_current_amount = None
                        item.estimated_current_unit = None
                        item.estimated_at = None
                        item.status = "EMPTY" if reconciled_amount == 0 else "IN_STOCK"
                        operation_calculation_method = "EXACT"
                        operation_affects_state = "CONFIRMED"
                        operation_applied_change_amount = None
                        operation_applied_change_unit = None
                    else:
                        if calculation.affects_state == "ESTIMATED":
                            # Exact arithmetic does not turn an existing estimate into a confirmation.
                            item.estimated_current_amount = calculation.amount
                            item.estimated_current_unit = calculation.unit
                            item.estimated_at = now
                        else:
                            item.confirmed_current_amount = calculation.amount
                            item.confirmed_current_unit = calculation.unit
                            item.confirmed_at = now
                        item.status = ("EMPTY" if calculation.affects_state == "CONFIRMED"
                                       and calculation.is_empty else "IN_STOCK")
                        operation_calculation_method = calculation.calculation_method
                        operation_affects_state = calculation.affects_state
                        operation_applied_change_amount = calculation.applied_change_amount
                        operation_applied_change_unit = calculation.unit
                    item.version += 1
                    await session.flush()
                    operation = InventoryOperation(
                        inventory_item_id=item.id, operation_type=operation_type, quantity_kind=quantity_kind,
                        quantity_value=quantity_value, quantity_unit=quantity_unit,
                        input_method=input_method, calculation_method=operation_calculation_method,
                        affects_state=operation_affects_state,
                        applied_change_amount=operation_applied_change_amount,
                        applied_change_unit=operation_applied_change_unit,
                        status="SUCCESS", idempotency_key=key,
                    )
                    session.add(operation)
                    await session.flush()
                    result = OperationResult(operation=InventoryOperationRead.model_validate(operation),
                                             inventory=await get_inventory(session, item.id, user_id),
                                             replayed=False)
            if commit:
                await session.commit()
            return result
        except IntegrityError as exc:
            await session.rollback()
            if not commit:
                # The outer Agent transaction owns associations and the receipt too.
                raise
            if not (getattr(exc.orig, "sqlstate", None) == "23505" and
                    getattr(getattr(exc.orig, "diag", None), "constraint_name", None)
                    == "uq_inventory_operation_idempotency_key"):
                raise
            # A different inventory/space may have claimed the same user-scoped key.
            await get_inventory(session, item_id, user_id)
            operation = await _operation_by_key(session, key)
            if operation is None:
                raise
            result = await _operation_replay(session, operation, item_id, user_id, operation_type, quantity_kind,
                                            quantity_value, quantity_unit)
            await session.commit()
            return result
    except QuantityError as exc:
        await session.rollback()
        raise InventoryError(exc.code, str(exc)) from exc
    except Exception:
        await session.rollback()
        raise


async def add_inventory(session: AsyncSession, item_id: UUID, user_id: UUID, *,
                        expected_version: int, quantity_value: str, quantity_unit: str,
                        idempotency_key: str) -> OperationResult:
    """Retain the B10 service entry point while sharing the transaction machinery."""
    return await submit_inventory_operation(
        session, item_id, user_id, expected_version=expected_version,
        operation_type="ADD", quantity_kind="AMOUNT", quantity_value=quantity_value,
        quantity_unit=quantity_unit, idempotency_key=idempotency_key,
    )
