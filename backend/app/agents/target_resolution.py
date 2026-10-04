"""Bounded target lookup evidence inside the existing model/tool loop."""
import json
from copy import deepcopy

MAX_TARGET_REVISIONS = 2
MAX_TARGET_READS = 6
INVENTORY_READ_TOOLS = {"list_inventory", "resolve_inventory_targets", "get_inventory_detail", "get_expiry_summary"}


def target_reason(error):
    error = error or {}
    if error.get("code") != "TARGET_REQUIRED":
        return None
    details = error.get("details") or {}
    if details.get("reason"):
        return details["reason"]
    # Old checkpoints distinguish a real empty search from a missing query.
    if details.get("total") == 0 and details.get("candidates") == []:
        return "NO_MATCH"
    return "AMBIGUOUS" if details.get("candidates") else "MISSING_QUERY"


def lookup_active(item):
    return (item.get("status") == "DRAFT" and bool(item.get("target_lookup"))
            and not item.get("draft", {}).get("inventory_item_id")
            and not item["target_lookup"].get("exhausted"))


def retry_target(item):
    lookup = deepcopy(item.get("target_lookup") or {})
    if (lookup.get("revisions", 0) >= MAX_TARGET_REVISIONS
            or lookup.get("reads", 0) >= MAX_TARGET_READS or lookup.get("exhausted")):
        return False
    lookup["revisions"] = lookup.get("revisions", 0) + 1
    item["target_lookup"] = lookup
    item.pop("question", None)
    return True


def exhaust_target(item):
    item["target_lookup"] = {**item.get("target_lookup", {}), "exhausted": True}
    item["status"] = "NEEDS_INPUT"
    item["error"] = {"code": "TARGET_REQUIRED", "message": "Unable to resolve this inventory target; please clarify its name or location.",
                     "details": {"reason": "NO_MATCH", "candidates": [], "total": 0}}
    item.pop("question", None)


def record_target_read(item, call, replies):
    """Store bounded metadata, not another copy of inventory or chat history."""
    lookup = deepcopy(item.get("target_lookup") or {})
    lookup["reads"] = lookup.get("reads", 0) + 1
    try:
        reply = next(r for r in replies if r.tool_call_id == call["id"])
        data = json.loads(reply.content)
        successful = isinstance(data, dict) and data.get("ok") is not False and getattr(reply, "status", None) != "error"
        if call["name"] == "resolve_inventory_targets":
            successful = successful and isinstance(data.get("candidates"), list) and isinstance(data.get("total"), int)
        elif call["name"] == "list_inventory":
            successful = (successful and data.get("ok") is True and isinstance(data.get("items"), list)
                          and type(data.get("total")) is int and data["total"] >= 0
                          and type(data.get("page")) is int and data["page"] > 0
                          and type(data.get("page_size")) is int and data["page_size"] > 0)
    except (StopIteration, ValueError, TypeError, AttributeError):
        data, successful = {}, False
    lookup["last_read_failed"] = not successful
    if successful and (data.get("items") or data.get("candidates")) and (lookup.get("scan") or {}).get("total") == 0:
        # A newer read with stock invalidates an older empty snapshot, even if
        # the newer read used a filter and cannot establish the full inventory.
        lookup.pop("scan", None)
    if successful and call["name"] == "list_inventory":
        args = call["args"]
        # Only global, unfiltered IN_STOCK observations can prove global emptiness.
        broad = args.get("status", "IN_STOCK") == "IN_STOCK" and not any(args.get(k) for k in (
            "q", "storage_space_id", "category_id", "purchase_from", "purchase_to", "expiry_from", "expiry_to"))
        if broad:
            page, size, total = data.get("page"), data.get("page_size"), data.get("total")
            if (type(page) is int and page > 0 and type(size) is int and size > 0
                    and type(total) is int and total >= 0):
                scan = lookup.get("scan", {})
                if scan.get("total") != total or scan.get("page_size") != size or page == 1:
                    scan = {"total": total, "page_size": size, "pages": {}}
                scan["pages"][str(page)] = len(data["items"])
                lookup["scan"] = scan
    item["target_lookup"] = lookup


def lookup_observation(item):
    lookup = item.get("target_lookup") or {}
    if lookup.get("last_read_failed"):
        return "FAILED"
    scan = lookup.get("scan") or {}
    total, size, pages = scan.get("total"), scan.get("page_size"), scan.get("pages", {})
    if total is not None and size:
        count = max(1, (total + size - 1) // size)
        complete = all(pages.get(str(p)) == min(size, max(0, total - (p - 1) * size)) for p in range(1, count + 1))
        if complete:
            return "EMPTY" if total == 0 else "COMPLETE"
        return "INCOMPLETE"
    return "UNRESOLVED"
