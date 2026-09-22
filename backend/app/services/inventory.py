"""Inventory ownership, reads, creation, quantity operations, and versioned writes."""
from datetime import datetime, timezone
from decimal import Decimal
from uuid import UUID

from sqlalchemy import func, or_, select, true
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.db.models import InventoryItem, InventoryOperation, ItemCategory, ItemDefinition, StorageSpace
from app.schemas.inventory import InventoryItemRead
from app.schemas.inventory_operations import InventoryOperationRead, OperationResult
from app.services.inventory_quantities import calculate_addition, calculate_consumption, prepare_reconciliation
from app.core.quantity import QuantityError


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
                        quantity_value: str, quantity_unit: str, idempotency_key: str) -> OperationResult:
    """Apply one ADD/CONSUME/RECONCILE atomically, or return its prior record and current inventory.

    The route passes schema-validated input. Only this outer service commits or
    rolls back. Database uniqueness also protects a key reused across spaces.
    """
    if operation_type not in {"ADD", "CONSUME", "RECONCILE"} or quantity_kind not in {"AMOUNT", "FRACTION"}:
        raise InventoryError("VALIDATION_ERROR", "Unsupported operation or quantity kind")
    if operation_type == "ADD" and quantity_kind != "AMOUNT":
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

                    if operation_type == "ADD":
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
                                       and calculation.amount == 0 else "IN_STOCK")
                        operation_calculation_method = calculation.calculation_method
                        operation_affects_state = calculation.affects_state
                        operation_applied_change_amount = calculation.applied_change_amount
                        operation_applied_change_unit = calculation.unit
                    item.version += 1
                    await session.flush()
                    operation = InventoryOperation(
                        inventory_item_id=item.id, operation_type=operation_type, quantity_kind=quantity_kind,
                        quantity_value=quantity_value, quantity_unit=quantity_unit,
                        input_method="MANUAL", calculation_method=operation_calculation_method,
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
            await session.commit()
            return result
        except IntegrityError as exc:
            await session.rollback()
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
