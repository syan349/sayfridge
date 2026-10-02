"""Validated Agent previews and atomic, independently replayable business writes."""
from __future__ import annotations

from dataclasses import asdict
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select, func, text

from app.agents.memory import fingerprint, MemoryService
from app.core.catalog import normalize_catalog_name, normalize_category_name
from app.core.quantity import validate_quantity_amount
from app.db.models import AgentInventoryAction, StorageSpace, ItemDefinition, ItemCategory
from app.schemas.agent_actions import ActionDraft
from app.schemas.inventory import InventoryCreate
from app.schemas.inventory_operations import InventoryOperationCreate
from app.services import inventory, catalog, storage_spaces
from app.services.inventory_quantities import (
    calculate_addition, calculate_consumption, calculate_estimated_change, calculate_change,
    prepare_reconciliation, get_addition_base, convert_addition_amount,
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
        try:
            explicit_id = UUID(query.strip())
        except ValueError:
            explicit_id = None
        if explicit_id:
            row = await inventory.get_inventory(session, explicit_id, user_id)
            if row.status == "IN_STOCK" and (not storage_space_id or str(row.storage_space_id) == str(storage_space_id)):
                matched[str(row.id)] = row.model_dump(mode="json")
            continue
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
    if create:
        await storage_spaces.lock_space_owner(session, user_id)
    if not space_id and not draft.new_space:
        space_id = await session.scalar(select(StorageSpace.id).where(
            StorageSpace.user_id == user_id, StorageSpace.status == "ACTIVE", StorageSpace.is_default.is_(True)))
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
        category = (await catalog._lock_categories(session, {draft.new_definition.category_id}, user_id))[draft.new_definition.category_id] if create else await session.scalar(select(ItemCategory).where(ItemCategory.id == draft.new_definition.category_id, catalog.category_visibility(user_id)))
        if category is None or category.status != "ACTIVE":
            available = list(await session.scalars(select(ItemCategory).where(ItemCategory.status == "ACTIVE", catalog.category_visibility(user_id))))
            raise PreparationError("CATEGORY_REQUIRED", "Choose an active existing category", {
                "categories": [{"id": str(c.id), "name": c.name} for c in available]})
        matches = list(await session.scalars(select(ItemDefinition).where(
            (ItemDefinition.owner_user_id == user_id) | ItemDefinition.owner_user_id.is_(None),
            ItemDefinition.normalized_name == normalize_catalog_name(draft.new_definition.name))))
        private = [row for row in matches if row.owner_user_id == user_id]
        candidates = private or [row for row in matches if row.status == "ACTIVE"]
        if len(candidates) > 1:
            raise PreparationError("DEFINITION_REQUIRED", "Which matching item do you mean?")
        found = candidates[0] if candidates else None
        if found and found.status != "ACTIVE":
            raise PreparationError("ASSOCIATION_CONFLICT", "Existing item definition is archived")
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
        category = await session.scalar(select(ItemCategory).where(ItemCategory.id == definition.category_id, catalog.category_visibility(user_id)))
        if definition.status != "ACTIVE" or category is None or category.status != "ACTIVE":
            raise PreparationError("STATE_CONFLICT", "Creation requires an active definition/category")
    return space_id, definition_id


def validate_image_policy(draft, image_policy, *, approved=None):
    """Policy is supplied by workflow state, never by model tool arguments."""
    policy = image_policy or {}
    if policy.get("create_only") or draft.source_image_ids:
        if draft.action != "CREATE_STOCK" or draft.inventory_item_id is not None:
            raise PreparationError("IMAGE_ACTION_NOT_SUPPORTED", "Images can only create a new stock batch")
    if approved is False and policy.get("requires_review"):
        raise PreparationError("CONFIRMATION_REQUIRED", "Review the current image-derived proposal first")


def validate_new_space_source(draft, source_texts):
    if not draft.new_space:
        return
    quote = draft.new_space_source_text
    if not quote or not any(quote in value for value in source_texts):
        raise PreparationError("SPACE_REQUIRED", "Where would you like to store this?")
    if normalize_catalog_name(draft.new_space.name) not in normalize_catalog_name(quote):
        raise PreparationError("SPACE_REQUIRED", "What is the name of the storage location?")


async def prepare_action(session, user_id, draft: ActionDraft, memory: MemoryService, as_of=None, *, image_policy=None, source_texts=(), target_context=None):
    validate_image_policy(draft, image_policy)
    validate_new_space_source(draft, source_texts)
    snapshots = []
    if draft.unit_relationship and draft.unit_relationship.source == "USER_INPUT":
        quote = draft.unit_relationship.evidence
        if not quote or not any(quote in value for value in source_texts):
            raise PreparationError("QUANTITY_REQUIRED", "The user-provided relationship needs original source evidence")
    if draft.action == "CREATE_STOCK":
        if draft.estimate or draft.quantity_kind != "AMOUNT" or draft.quantity_value is None or not draft.quantity_unit:
            missing = (["quantity_value"] if draft.quantity_value is None else []) + (["quantity_unit"] if not draft.quantity_unit else [])
            if draft.quantity_value is not None:
                try:
                    validate_quantity_amount(Decimal(draft.quantity_value))
                except (ValueError, ArithmeticError):
                    if "quantity_value" not in missing:
                        missing.insert(0, "quantity_value")
            raise PreparationError("INITIAL_QUANTITY_REQUIRED", "Provide the missing initial quantity information", {"missing_fields": missing})
        if draft.quantity_issue:
            raise PreparationError("IMAGE_QUANTITY_UNCLEAR", "Clarify the printed purchase quantity",
                                   {"missing_fields": ["quantity_value"], "reason": draft.quantity_issue})
        try:
            validate_quantity_amount(Decimal(draft.quantity_value))
        except ValueError as exc:
            if not getattr(exc, "code", None):
                raise PreparationError("QUANTITY_PRECISION_UNSUPPORTED", "Specify a positive amount with at most three decimal places",
                                       {"missing_fields": ["quantity_value"]}) from None
            raise
        if draft.clarification_question:
            raise PreparationError("CLARIFICATION_REQUIRED", draft.clarification_question)
        if draft.new_definition and draft.category_name:
            category = await session.scalar(select(ItemCategory).where(ItemCategory.status == "ACTIVE",
                catalog.category_visibility(user_id), ItemCategory.normalized_name == normalize_category_name(draft.category_name)))
            if category is None:
                available = list(await session.scalars(select(ItemCategory).where(ItemCategory.status == "ACTIVE", catalog.category_visibility(user_id))))
                raise PreparationError("CATEGORY_REQUIRED", "Choose an active existing category", {
                    "categories": [{"id": str(c.id), "name": c.name} for c in available]})
            draft = draft.model_copy(update={"new_definition": draft.new_definition.model_copy(update={"category_id": category.id})})
        space_id, definition_id = await _creation_values(session, user_id, draft)
        # Use placeholders only for validating quantities; never submit these IDs.
        placeholder = UUID(int=0)
        values = InventoryCreate(storage_space_id=space_id or placeholder,
            item_definition_id=definition_id or placeholder, amount=draft.quantity_value,
            unit=draft.quantity_unit, purchase_date=draft.purchase_date, expiry_date=draft.expiry_date)
        image_review = bool((image_policy or {}).get("requires_review") or draft.source_image_ids)
        definition = await catalog.get_definition(session, definition_id, user_id) if definition_id else None
        space = await storage_spaces.get_storage_space_by_id(session, space_id, user_id) if space_id else None
        category_id = definition.category_id if definition else draft.new_definition.category_id
        category = await session.get(ItemCategory, category_id)
        return {"draft": draft.model_dump(mode="json"), "before": None,
            "display": {"item_name": definition.name if definition else draft.new_definition.name,
                        "space_name": space.name if space else draft.new_space.name,
                        "category_id": str(category.id), "category_name": category.name},
            "image_policy": image_policy or {},
            "default_space_id": str(space_id) if not draft.storage_space_id and not draft.new_space and space_id else None,
            "confirmation_reasons": ["IMAGE_REVIEW"] if image_review else [],
            "creation_policy": {"version": 1, "new_space_authorized": bool(draft.new_space)},
            "after": {"confirmed_current_amount": values.amount, "confirmed_current_unit": values.unit,
                      "estimated_current_amount": None}, "calculation_method": "EXACT",
            "affects_state": "CONFIRMED", "memory_snapshots": [],
            "requires_confirmation": bool(image_review or draft.confirmation_requested), "expected_version": None}
    if not draft.inventory_item_id:
        if not draft.item_query:
            raise PreparationError("TARGET_REQUIRED", "Identify the inventory item")
        try:
            explicit_id = UUID(draft.item_query.strip())
        except ValueError:
            explicit_id = None
        targets = await resolve_targets(session, user_id, [draft.item_query], draft.storage_space_id, memory) if explicit_id is None else None
        chosen = str(explicit_id) if explicit_id else targets["preferred_id"] or (targets["candidates"][0]["id"] if targets["total"] == 1 else None)
        if not chosen:
            raise PreparationError("TARGET_REQUIRED", "Select a specific inventory batch", targets)
        draft = draft.model_copy(update={"inventory_item_id": UUID(chosen)})
    item = await inventory.get_inventory(session, draft.inventory_item_id, user_id)
    if target_context:
        selected = target_context.get("selected_inventory_item_id")
        actual_words = target_context.get("source_texts", [])
        if selected and str(draft.inventory_item_id) != str(selected):
            raise PreparationError("TARGET_CONFLICT", "Preserve the user's selected batch")
        if not selected and not any(str(draft.inventory_item_id) in text for text in actual_words):
            # Model-supplied IDs cannot silently select one of several batches or
            # narrow usage to the default space. Use the real candidates and the
            # user's task words; structured selections have already been checked.
            query = target_context.get("item_query") or draft.item_query
            queries = [item.item_definition_name]
            if query and query != str(draft.inventory_item_id):
                queries.append(query)
            targets = await resolve_targets(session, user_id, queries, memory=memory)
            if targets["total"] > 1 and targets["preferred_id"] != str(draft.inventory_item_id):
                qualified = []
                for text in reversed(actual_words):
                    qualified = [c for c in targets["candidates"] if c.get("storage_space_name")
                                 and c["storage_space_name"].casefold() in text.casefold()]
                    if qualified:
                        break
                if len(qualified) != 1 or qualified[0]["id"] != str(draft.inventory_item_id):
                    raise PreparationError("TARGET_REQUIRED", "Select a specific inventory batch", targets)
    if draft.storage_space_id and item.storage_space_id != draft.storage_space_id:
        raise PreparationError("TARGET_CONFLICT", "The selected batch is in a different space")
    if draft.quantity_kind == "FRACTION":
        draft = draft.model_copy(update={"quantity_unit": "remaining"})
    if draft.quantity_value is None or (not draft.quantity_unit and draft.quantity_kind != "QUALITATIVE"):
        raise PreparationError("QUANTITY_REQUIRED", "Provide a quantity expression and unit")
    context = {"item_definition_id": str(item.item_definition_id), "item_name": item.item_definition_name,
        "storage_space_id": str(item.storage_space_id), "source_unit": draft.quantity_unit,
        "target_unit": get_addition_base(item)[1], "utensil": draft.utensil, "as_of": str(as_of) if as_of else None}
    context["package_description"] = draft.package_description
    estimated_change = None
    relationship = None
    if draft.action == "RECONCILE":
        relationship = None
        if draft.estimate or draft.unit_relationship:
            raise PreparationError("STOCKTAKE_REQUIRED", "A stocktake requires the actual remaining quantity")
        amount, unit = prepare_reconciliation(Decimal(draft.quantity_value), draft.quantity_unit)
        calc = {"amount": str(amount), "unit": unit, "affects_state": "CONFIRMED", "calculation_method": "EXACT"}
    else:
        if not relationship and draft.unit_relationship and draft.unit_relationship.source == "USER_INPUT":
            relationship = draft.unit_relationship.model_dump()
        if not relationship:
            matching = await memory.find_conversion_relationship(context)
            if matching["status"] in {"CONFLICT", "NEEDS_CONTEXT"}:
                raise PreparationError("MEMORY_CONTEXT_REQUIRED", "Clarify the applicable unit relationship", matching)
            if matching["status"] == "MATCH":
                snapshots = matching["items"]
                relationship = {**snapshots[0]["structured_value"], "source": snapshots[0].get("source", "USER_MEMORY"),
                                "rationale": snapshots[0].get("content", "Saved unit relationship")}
        if not relationship and draft.unit_relationship:
            if draft.unit_relationship.source == "USER_MEMORY":
                raise PreparationError("REESTIMATE", "No applicable saved relationship exists")
            relationship = draft.unit_relationship.model_dump()
        try:
            if draft.quantity_kind == "QUALITATIVE":
                if not draft.estimate:
                    raise PreparationError("REESTIMATE", "Propose an estimated amount for this qualitative expression")
                unit = draft.quantity_unit or get_addition_base(item)[1]
                try:
                    amount = convert_addition_amount(Decimal(draft.estimate.amount), draft.estimate.unit, unit)
                except ValueError:
                    raise PreparationError("REESTIMATE", f"Provide the qualitative estimate directly in {unit}") from None
                relationship, snapshots = None, []
                calculation = calculate_estimated_change(item, draft.action, amount, unit)
                estimated_change = (str(calculation.applied_change_amount), calculation.unit)
            else:
                calculation = calculate_change(item, draft.action, draft.quantity_kind,
                    draft.quantity_value, draft.quantity_unit, relationship=relationship)
        except ValueError as exc:
            if getattr(exc, "code", None) != "UNIT_NOT_CONVERTIBLE":
                raise
            if not draft.estimate:
                raise PreparationError("REESTIMATE", "Provide unit_relationship with a ratio and its source; do not calculate final balances")
            # Compatibility for outstanding v2 proposals: derive a relation from their delta.
            relationship = {"source_amount": draft.quantity_value, "source_unit": draft.quantity_unit,
                "target_amount": draft.estimate.amount, "target_unit": draft.estimate.unit,
                "source": draft.estimate.source, "rationale": draft.estimate.rationale}
            calculation = calculate_change(item, draft.action, draft.quantity_kind,
                draft.quantity_value, draft.quantity_unit, relationship=relationship)
        calc = json_value(asdict(calculation))
        if calc["calculation_method"] != "AI_ESTIMATED":
            relationship, snapshots = None, []
    after = {"amount": calc["amount"], "unit": calc["unit"], "is_estimated": calc["affects_state"] == "ESTIMATED"}
    return {"draft": draft.model_dump(mode="json"), "before": item.model_dump(mode="json"), "after": after,
        "quantity_policy": "request_unit_v1", "calculation": calc, "calculation_method": calc["calculation_method"], "affects_state": calc["affects_state"],
        "estimated_change": estimated_change, "unit_relationship": relationship, "memory_snapshots": snapshots,
        "requires_confirmation": draft.confirmation_requested, "expected_version": item.version}


async def execute_action(session, user_id, conversation_id, turn_id, proposal_id, preview, memory, *, approved=False, image_policy=None):
    digest = fingerprint(preview)
    try:
        # The transaction lock serializes identical receipts before any side effect.
        await session.execute(text("SELECT pg_advisory_xact_lock(:key)"),
            {"key": int.from_bytes(UUID(str(proposal_id)).bytes[:8], "big", signed=True)})
        prior = await session.get(AgentInventoryAction, UUID(str(proposal_id)))
        if prior:
            if prior.user_id != user_id or prior.request_fingerprint != digest:
                raise PreparationError("IDEMPOTENCY_CONFLICT", "Action identifier already used")
            output = {**prior.result_snapshot, "replayed": True}
            await session.commit()
            return output
        draft = ActionDraft.model_validate(preview["draft"])
        validate_image_policy(draft, image_policy, approved=approved)
        validate_image_policy(draft, preview.get("image_policy"), approved=approved)
        if draft.source_image_ids and not approved:
            raise PreparationError("CONFIRMATION_REQUIRED", "Review the image-derived proposal first")
        if preview["requires_confirmation"] and not approved:
            raise PreparationError("CONFIRMATION_REQUIRED", "Confirm the current proposal")
        if draft.new_space and not approved and not preview.get("creation_policy", {}).get("new_space_authorized"):
            raise PreparationError("CONFIRMATION_REQUIRED", "Confirm the current proposal")
        if not await memory.verify_snapshots(preview["memory_snapshots"]):
            raise PreparationError("MEMORY_CHANGED", "Memory changed; prepare a new proposal")
        if draft.action != "CREATE_STOCK" and preview.get("quantity_policy") != "request_unit_v1":
            raise PreparationError("QUANTITY_POLICY_CHANGED", "Reprepare this pending operation using current quantity rules")
        relation = preview.get("unit_relationship")
        if relation and draft.save_conversion_memory:
            before = preview["before"]
            try:
                await memory.save_conversion({"relationship": relation,
                    "item_definition_id": before["item_definition_id"], "item_name": before["item_definition_name"],
                    "conditions": {k: v for k, v in {"utensil": draft.utensil,
                        "package_description": draft.package_description}.items() if v}})
            except Exception:
                raise PreparationError("MEMORY_SAVE_UNAVAILABLE", "Conversion memory could not be saved; inventory has not changed") from None
        if draft.action == "CREATE_STOCK":
            space_id, definition_id = await _creation_values(session, user_id, draft, create=True)
            if preview.get("default_space_id") and str(space_id) != preview["default_space_id"]:
                raise PreparationError("RESOURCE_CHANGED", "Default space changed; refresh the proposal")
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
                estimated_change=(Decimal(delta[0]), delta[1]) if delta else None,
                unit_relationship=preview.get("unit_relationship"))
            output = result.model_dump(mode="json")
        session.add(AgentInventoryAction(id=UUID(str(proposal_id)), user_id=user_id,
            conversation_id=conversation_id, turn_id=UUID(str(turn_id)), action=draft.action,
            request_fingerprint=digest, request_snapshot=preview, result_snapshot=output))
        await session.commit()
        return output
    except BaseException:
        await session.rollback()
        raise
