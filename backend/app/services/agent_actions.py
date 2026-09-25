"""Validated Agent previews and atomic, independently replayable business writes."""
from __future__ import annotations

from dataclasses import asdict
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select, func, text

from app.agents.memory import fingerprint, MemoryService
from app.core.catalog import normalize_catalog_name
from app.db.models import AgentInventoryAction, StorageSpace, ItemDefinition, ItemCategory
from app.schemas.agent_actions import ActionDraft
from app.schemas.inventory import InventoryCreate
from app.schemas.inventory_operations import InventoryOperationCreate
from app.services import inventory, catalog, storage_spaces
from app.services.inventory_quantities import (
    calculate_addition, calculate_consumption, calculate_estimated_change,
    prepare_reconciliation, get_addition_base,
)


class PreparationError(ValueError):
    def __init__(self, code, message, details=None):
        super().__init__(message)
        self.code, self.details = code, details or {}


def json_value(value):
    import json
    return json.loads(json.dumps(value, default=str, ensure_ascii=False))


async def resolve_targets(session, user_id, queries, storage_space_id=None, memory=None, space_query=None):
    """Return all matching candidates, never silently choose the first page."""
    aliases = await memory.search_memories("ENTITY_ALIAS", limit=100000) if memory else []
    preferences = await memory.search_memories("USAGE_PREFERENCE", limit=100000) if memory else []
    space_candidates = []
    if space_query and not storage_space_id:
        owned = list(await session.scalars(select(StorageSpace).where(StorageSpace.user_id == user_id)))
        alias_ids = {(r.get("structured_value") or {}).get("target_id") for r in aliases
            if (r.get("structured_value") or {}).get("target_type") == "SPACE"
            and normalize_catalog_name((r.get("structured_value") or {}).get("alias", "")) == normalize_catalog_name(space_query)}
        exact = [s for s in owned if normalize_catalog_name(s.name) == normalize_catalog_name(space_query) or str(s.id) in alias_ids]
        matches = exact or [s for s in owned if normalize_catalog_name(space_query) in normalize_catalog_name(s.name)]
        space_candidates = [{"id": str(s.id), "name": s.name, "type": s.type, "status": s.status} for s in matches]
        if len(matches) != 1:
            return {"candidates": [], "total": 0, "truncated": False, "preferred_id": None,
                    "spaces": space_candidates, "status": "SPACE_REQUIRED"}
        storage_space_id = matches[0].id
    matched = {}
    for query in queries:
        terms = [query]
        alias_ids = set()
        for record in aliases:
            value = record.get("structured_value") or {}
            if normalize_catalog_name(str(value.get("alias", ""))) == normalize_catalog_name(query):
                if value.get("target_type") == "ITEM_DEFINITION":
                    alias_ids.add(value.get("target_id"))
        # Query across pages. Alias matches use stable IDs, including renamed objects.
        for term in ([""] if alias_ids else terms):
            page = 1
            while True:
                rows, total = await inventory.list_inventory(session, user_id, status="IN_STOCK",
                    q=term, storage_space_id=storage_space_id, category_id=None,
                    purchase_from=None, purchase_to=None, expiry_from=None, expiry_to=None,
                    page=page, page_size=100)
                for row in rows:
                    if not alias_ids or str(row.item_definition_id) in alias_ids:
                        matched[str(row.id)] = row.model_dump(mode="json")
                if page * 100 >= total:
                    break
                page += 1
    candidates = list(matched.values())
    exact = [r for r in candidates if any(normalize_catalog_name(r["item_definition_name"]) == normalize_catalog_name(q) for q in queries)]
    if exact:
        candidates = exact
    preferred = None
    if len({r["item_definition_id"] for r in candidates}) == 1 and len(candidates) > 1:
        if any((r.get("structured_value") or {}).get("batch_selection") == "EARLIEST_EXPIRY" and not any(r.get("conditions", {}).values()) for r in preferences):
            dated = sorted((r for r in candidates if r["expiry_date"]), key=lambda r: r["expiry_date"])
            if dated and (len(dated) == 1 or dated[0]["expiry_date"] != dated[1]["expiry_date"]):
                preferred = dated[0]["id"]
    return {"candidates": candidates[:100], "total": len(candidates),
            "truncated": len(candidates) > 100, "preferred_id": preferred, "spaces": space_candidates}


async def _creation_values(session, user_id, draft, *, create=False):
    space_id, definition_id = draft.storage_space_id, draft.item_definition_id
    if draft.new_space:
        found = await session.scalar(select(StorageSpace).where(StorageSpace.user_id == user_id,
            func.lower(StorageSpace.name) == draft.new_space.name.lower(), StorageSpace.status == "ACTIVE"))
        if found and found.type != draft.new_space.type:
            raise PreparationError("ASSOCIATION_CONFLICT", "Existing space has a different type")
        if found:
            space_id = found.id
        elif create:
            space = await storage_spaces.create_storage_space(session, user_id,
                **draft.new_space.model_dump(), commit=False)
            space_id = space.id
    if space_id:
        space = await storage_spaces.get_storage_space_by_id(session, space_id, user_id, lock=create)
        if space.status != "ACTIVE":
            raise PreparationError("STATE_CONFLICT", "Creation requires an active space")
    if draft.new_definition:
        category = (await catalog._lock_categories(session, {draft.new_definition.category_id}))[draft.new_definition.category_id] if create else await session.get(ItemCategory, draft.new_definition.category_id)
        if category is None or category.status != "ACTIVE":
            raise PreparationError("CATEGORY_REQUIRED", "Choose an active existing category")
        found = await session.scalar(select(ItemDefinition).where(ItemDefinition.owner_user_id == user_id,
            ItemDefinition.normalized_name == normalize_catalog_name(draft.new_definition.name)))
        if found and (found.category_id != category.id or found.status != "ACTIVE"):
            raise PreparationError("ASSOCIATION_CONFLICT", "Existing item definition differs from this proposal")
        if found:
            definition_id = found.id
        elif create:
            definition = await catalog.create_definition(session, user_id,
                **draft.new_definition.model_dump(), commit=False)
            definition_id = definition.id
    if not space_id and not draft.new_space:
        raise PreparationError("SPACE_REQUIRED", "Select a storage space")
    if not definition_id and not draft.new_definition:
        raise PreparationError("DEFINITION_REQUIRED", "Select an item definition")
    if definition_id:
        definition = await catalog.get_definition(session, definition_id, user_id)
        category = await session.get(ItemCategory, definition.category_id)
        if definition.status != "ACTIVE" or category.status != "ACTIVE":
            raise PreparationError("STATE_CONFLICT", "Creation requires an active definition/category")
    return space_id, definition_id


async def prepare_action(session, user_id, draft: ActionDraft, memory: MemoryService, as_of=None):
    snapshots = []
    if draft.action == "CREATE_STOCK":
        if draft.estimate or draft.quantity_kind != "AMOUNT" or draft.quantity_value is None or not draft.quantity_unit:
            raise PreparationError("INITIAL_QUANTITY_REQUIRED", "Provide the initial quantity and unit; counts such as two bags are sufficient")
        space_id, definition_id = await _creation_values(session, user_id, draft)
        # Use placeholders only for validating quantities; never submit these IDs.
        placeholder = UUID(int=0)
        values = InventoryCreate(storage_space_id=space_id or placeholder,
            item_definition_id=definition_id or placeholder, amount=draft.quantity_value,
            unit=draft.quantity_unit, purchase_date=draft.purchase_date, expiry_date=draft.expiry_date)
        return {"draft": draft.model_dump(mode="json"), "before": None,
            "after": {"confirmed_current_amount": values.amount, "confirmed_current_unit": values.unit,
                      "estimated_current_amount": None}, "calculation_method": "EXACT",
            "affects_state": "CONFIRMED", "memory_snapshots": [],
            "requires_confirmation": bool(draft.new_space or draft.new_definition), "expected_version": None}
    if not draft.inventory_item_id:
        if not draft.item_query:
            raise PreparationError("TARGET_REQUIRED", "Identify the inventory item")
        targets = await resolve_targets(session, user_id, [draft.item_query], draft.storage_space_id, memory)
        chosen = targets["preferred_id"] or (targets["candidates"][0]["id"] if targets["total"] == 1 else None)
        if not chosen:
            raise PreparationError("TARGET_REQUIRED", "Select a specific inventory batch", targets)
        draft = draft.model_copy(update={"inventory_item_id": UUID(chosen)})
    item = await inventory.get_inventory(session, draft.inventory_item_id, user_id)
    if draft.storage_space_id and item.storage_space_id != draft.storage_space_id:
        raise PreparationError("TARGET_CONFLICT", "The selected batch is in a different space")
    if draft.quantity_value is None or (not draft.quantity_unit and draft.quantity_kind != "QUALITATIVE"):
        raise PreparationError("QUANTITY_REQUIRED", "Provide a quantity expression and unit")
    context = {"item_definition_id": str(item.item_definition_id), "item_name": item.item_definition_name,
        "storage_space_id": str(item.storage_space_id), "source_unit": draft.quantity_unit,
        "target_unit": get_addition_base(item)[1], "utensil": draft.utensil, "as_of": str(as_of) if as_of else None}
    matching = await memory.find_applicable_memories(context)
    estimated_change = None
    if draft.action == "RECONCILE":
        if draft.estimate:
            raise PreparationError("STOCKTAKE_REQUIRED", "A stocktake requires the user's actual remaining total")
        payload = InventoryOperationCreate(expected_version=item.version, operation_type=draft.action,
            quantity_kind=draft.quantity_kind, quantity_value=draft.quantity_value, quantity_unit=draft.quantity_unit)
        amount, unit = prepare_reconciliation(Decimal(payload.quantity_value), payload.quantity_unit)
        calc = {"amount": str(amount), "unit": unit, "affects_state": "CONFIRMED", "calculation_method": "EXACT"}
    else:
        needs_estimate = draft.estimate is not None or draft.quantity_kind == "QUALITATIVE"
        calculation = None
        if not needs_estimate:
            payload = InventoryOperationCreate(expected_version=item.version, operation_type=draft.action,
                quantity_kind=draft.quantity_kind, quantity_value=draft.quantity_value, quantity_unit=draft.quantity_unit)
            try:
                calculation = calculate_addition(item, Decimal(payload.quantity_value), payload.quantity_unit) if draft.action == "ADD" else calculate_consumption(item, payload.quantity_kind, payload.quantity_value, payload.quantity_unit)
            except ValueError as exc:
                if getattr(exc, "code", None) != "UNIT_NOT_CONVERTIBLE":
                    raise
                needs_estimate = True
        if needs_estimate:
            if not draft.estimate or draft.estimate.source != "USER_INPUT":
                if matching["status"] in {"CONFLICT", "NEEDS_CONTEXT"}:
                    raise PreparationError("MEMORY_CONTEXT_REQUIRED", "Clarify the applicable unit relationship", matching)
                if matching["status"] == "MATCH":
                    snapshots = matching["items"]
                    if not draft.estimate or str(draft.estimate.memory_id) not in {r["memory_id"] for r in snapshots}:
                        raise PreparationError("REESTIMATE", "Use these applicable memories to propose an estimate", matching)
            if not draft.estimate:
                raise PreparationError("REESTIMATE", "No fixed conversion. Propose an estimate using model knowledge if no applicable memory exists", matching)
            if draft.estimate.source == "USER_MEMORY" and not snapshots:
                raise PreparationError("REESTIMATE", "The old memory no longer applies. Reconsider the estimate using current information or model knowledge")
            estimated_change = (draft.estimate.amount, draft.estimate.unit)
            # Structured ratios are calculated by the backend, not by model arithmetic.
            if snapshots:
                relation = snapshots[0].get("structured_value") or {}
                if all(k in relation for k in ("source_amount", "target_amount", "target_unit")) and draft.quantity_kind == "AMOUNT":
                    source = Decimal(str(relation["source_amount"]))
                    target = Decimal(str(relation["target_amount"]))
                    if not source.is_finite() or source <= 0 or not target.is_finite() or target <= 0:
                        raise PreparationError("MEMORY_CONTEXT_REQUIRED", "Invalid stored conversion ratio")
                    amount = Decimal(draft.quantity_value) / source * target
                    estimated_change = (str(amount), relation["target_unit"])
            calculation = calculate_estimated_change(item, draft.action, Decimal(estimated_change[0]), estimated_change[1])
        calc = json_value(asdict(calculation))
    after = {"amount": calc["amount"], "unit": calc["unit"], "is_estimated": calc["affects_state"] == "ESTIMATED"}
    return {"draft": draft.model_dump(mode="json"), "before": item.model_dump(mode="json"), "after": after,
        "calculation": calc, "calculation_method": calc["calculation_method"], "affects_state": calc["affects_state"],
        "estimated_change": estimated_change, "memory_snapshots": snapshots,
        "requires_confirmation": calc["calculation_method"] == "AI_ESTIMATED", "expected_version": item.version}


async def execute_action(session, user_id, conversation_id, turn_id, proposal_id, preview, memory, *, approved=False):
    digest = fingerprint(preview)
    try:
        # The transaction lock serializes identical receipts before any side effect.
        await session.execute(text("SELECT pg_advisory_xact_lock(:key)"),
            {"key": int.from_bytes(UUID(str(proposal_id)).bytes[:8], "big", signed=True)})
        prior = await session.get(AgentInventoryAction, UUID(str(proposal_id)))
        if prior:
            if prior.user_id != user_id or prior.request_fingerprint != digest:
                raise PreparationError("IDEMPOTENCY_CONFLICT", "Action identifier already used")
            return {**prior.result_snapshot, "replayed": True}
        if preview["requires_confirmation"] and not approved:
            raise PreparationError("CONFIRMATION_REQUIRED", "Confirm the current proposal")
        if not await memory.verify_snapshots(preview["memory_snapshots"]):
            raise PreparationError("MEMORY_CHANGED", "Memory changed; prepare a new proposal")
        draft = ActionDraft.model_validate(preview["draft"])
        if draft.action == "CREATE_STOCK":
            space_id, definition_id = await _creation_values(session, user_id, draft, create=True)
            values = InventoryCreate(storage_space_id=space_id, item_definition_id=definition_id,
                amount=draft.quantity_value, unit=draft.quantity_unit,
                purchase_date=draft.purchase_date, expiry_date=draft.expiry_date)
            result = await inventory.create_inventory(session, user_id, commit=False, **values.model_dump())
            output = {"inventory": result.model_dump(mode="json"), "operation": None, "replayed": False}
        else:
            delta = preview.get("estimated_change")
            result = await inventory.submit_inventory_operation(session, draft.inventory_item_id, user_id,
                expected_version=preview["expected_version"], operation_type=draft.action,
                quantity_kind=draft.quantity_kind, quantity_value=draft.quantity_value,
                quantity_unit=draft.quantity_unit, idempotency_key=f"agent:{proposal_id}",
                commit=False, input_method="TEXT",
                estimated_change=(Decimal(delta[0]), delta[1]) if delta else None)
            output = result.model_dump(mode="json")
        session.add(AgentInventoryAction(id=UUID(str(proposal_id)), user_id=user_id,
            conversation_id=conversation_id, turn_id=UUID(str(turn_id)), action=draft.action,
            request_fingerprint=digest, request_snapshot=preview, result_snapshot=output))
        await session.commit()
        return output
    except BaseException:
        await session.rollback()
        raise
