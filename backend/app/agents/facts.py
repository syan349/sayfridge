"""Merge task facts without erasing extraction evidence or unrelated work."""
import re
from decimal import Decimal
from app.schemas.agent_actions import ActionDraft


def retain_receipt_quantity(draft):
    """Cross-check the model's structured facts against its verbatim sale line."""
    line = draft.receipt_quantity_text
    if not line or not draft.source_image_ids:
        return draft
    match = re.match(r"^\s*([0-9]+(?:\.[0-9]+)?)\s*([^@]*?)\s*@", line)
    if not match:
        return draft
    value, printed_unit = match.groups()
    printed_unit = printed_unit.strip()
    updates = {"quantity_value": value}
    if printed_unit:
        # A price or explanation cannot be silently introduced as a weight unit.
        if re.fullmatch(r"kg|g|ml|l|公斤|千克|克|毫升|升", printed_unit, re.I):
            updates["quantity_unit"] = printed_unit.casefold()
    elif Decimal(value) != Decimal(value).to_integral_value():
        updates.update(quantity_unit=None, quantity_issue="The printed decimal purchase quantity has no explicit unit.")
    elif not draft.quantity_unit and not draft.quantity_issue:
        # In a normal integer quantity × price sale line, the quantity is a
        # count of purchase units. A missing model label is not a user-data gap.
        updates["quantity_unit"] = "each"
    if Decimal(value).as_tuple().exponent < -3:
        updates["quantity_issue"] = "The printed purchase quantity is unusual and exceeds the supported precision; ask for the actual quantity."
    return draft.model_copy(update=updates)


def merge_draft(item, proposed):
    old = item["draft"]
    if not item.get("revision_requested") and proposed.action != old["action"]:
        raise ValueError("The proposal must preserve the recorded operation intention")
    if proposed.clear_fields:
        quote = proposed.clear_fields_evidence
        latest = item.get("source_texts", [])[-1:]
        if not item.get("revision_requested") or not quote or not any(quote in text for text in latest) or not re.search(
                r"撤回|清除|删除|去掉|不确定|不知道|忘了|不要.*(?:记录|保存)|\b(?:withdraw|clear|remove|forget|unknown|unsure|not sure|don't know)\b", quote, re.I):
            raise ValueError("Clearing facts requires the user's explicit current withdrawal")
    supplied = {k: v for k, v in proposed.model_dump(mode="json", exclude_unset=True).items()
                if v is not None and v != "" and v != [] and k != "clear_fields"}
    # Initial image proposals resolve associations, rather than silently replacing
    # the purchase facts recorded by extraction.
    image_facts = bool(old.get("source_image_ids") or item.get("image_policy", {}).get("requires_review"))
    if not item.get("revision_requested"):
        for field in ("quantity_value", "quantity_unit", "quantity_kind", "purchase_date", "expiry_date", "shelf_life"):
            supplied.pop(field, None)
        if image_facts:
            for field in ("quantity_issue", "receipt_quantity_text"):
                supplied.pop(field, None)
    merged = {**old, **supplied, "original_text": item["original_text"]}
    if item.get("confirmation_required") or old.get("confirmation_requested"):
        merged["confirmation_requested"] = True
    merged["source_image_ids"] = list(dict.fromkeys([*old.get("source_image_ids", []),
                                                    *supplied.get("source_image_ids", [])]))
    merged["review_notes"] = list(dict.fromkeys([*old.get("review_notes", []),
                                               *supplied.get("review_notes", [])]))[:10]
    # User corrections resolve the old doubt; immutable extraction remains on item.
    if item.get("revision_requested") and any(
            field in supplied and supplied[field] != old.get(field)
            for field in ("quantity_value", "quantity_unit")):
        current = item.get("revision_text", "\n".join(item.get("source_texts", [])[-1:]))
        explicit_correction = bool(re.search(r"实际|更正|确实|就是|\b(?:actually|actual|correct|really)\b", current, re.I))
        merged["quantity_issue"] = (None if explicit_correction or proposed.quantity_issue == old.get("quantity_issue")
                                    else proposed.quantity_issue)
        if old.get("quantity_unit") is None and supplied.get("quantity_unit"):
            try:
                number = Decimal(str(merged.get("quantity_value")))
                if number.is_finite() and number > 0 and number.as_tuple().exponent >= -3:
                    merged["quantity_issue"] = None
            except ArithmeticError:
                pass
        if current:
            merged["quantity_basis"] = "User supplement: " + current[:1900]
    for field in proposed.clear_fields:
        merged[field] = None
    merged["clear_fields"] = []
    merged["clear_fields_evidence"] = None
    merged["clarification_question"] = proposed.clarification_question
    if supplied.get("new_space"):
        merged["storage_space_id"] = None
    elif merged.get("storage_space_id"):
        merged["new_space"] = None
        merged["new_space_source_text"] = None
    if supplied.get("new_definition"):
        merged["item_definition_id"] = None
    elif merged.get("item_definition_id"):
        merged["new_definition"] = None
    return ActionDraft.model_validate(merged)


def missing_fields(item):
    """Describe actual holes, including unit-only and proportion cases."""
    draft = item.get("draft", {})
    error = item.get("error") or {}
    if error.get("code") == "TARGET_REQUIRED":
        # Existing clients render these names literally. The question explains
        # target resolution; users never need to supply an internal record ID.
        return []
    if "missing_fields" in error.get("details", {}):
        return error["details"]["missing_fields"]
    code = error.get("code")
    if code in {"INITIAL_QUANTITY_REQUIRED", "QUANTITY_REQUIRED"}:
        fields = []
        if draft.get("quantity_value") is None:
            fields.append("quantity_value")
        if not draft.get("quantity_unit") and draft.get("quantity_kind", "AMOUNT") == "AMOUNT":
            fields.append("quantity_unit")
        return fields
    return {"WHOLE_COUNT_REQUIRED": ["quantity_value"], "IMAGE_QUANTITY_UNCLEAR": ["quantity_value"],
            "QUANTITY_PRECISION_UNSUPPORTED": ["quantity_value"], "SPACE_REQUIRED": ["storage_space_id"],
            "DEFINITION_REQUIRED": ["item_definition_id"],
            "CATEGORY_REQUIRED": ["category_id"]}.get(code, [])
