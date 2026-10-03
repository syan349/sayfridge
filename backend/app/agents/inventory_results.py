"""Cards contain authenticated read-tool data, never inventory invented in prose."""
import json

from app.schemas.agent_actions import AgentInventoryQuery
from app.schemas.inventory import InventoryItemRead


def capture_inventory_read(call, messages):
    name = call["name"]
    if name not in {"list_inventory", "get_inventory_detail", "get_expiry_summary"}:
        return None
    try:
        result = json.loads(messages[-1].content)
        if result.get("ok") is not True:
            return None
        detail = name == "get_inventory_detail"
        rows = [result["item"]] if detail else result["items"]
        items = [InventoryItemRead.model_validate(row).model_dump(mode="json") for row in rows]
        args = {k: v for k, v in call["args"].items() if k not in {"page", "page_size"} and v is not None}
        # Explicit defaults and omitted defaults identify the same paged query.
        if name == "list_inventory":
            args.setdefault("status", "IN_STOCK")
        if name == "get_expiry_summary":
            args.setdefault("days_before", 3)
        return {"items": items, "total": 1 if detail else int(result["total"]),
                "selector": json.dumps([name, args], sort_keys=True)}
    except (ValueError, TypeError, KeyError, AttributeError, IndexError):
        # A failed/malformed read must not turn into plausible-looking stock cards.
        return None


def select_inventory_results(reads, source_ids, as_of):
    groups = {}
    for source_id in dict.fromkeys(source_ids):
        if source_id not in reads:
            raise ValueError("Select only successful inventory read call IDs from this turn")
        read = reads[source_id]
        group = groups.setdefault(read["selector"], {"items": {}, "total": read["total"]})
        group["total"] = read["total"]
        group["items"].update({row["id"]: row for row in read["items"]})
    items = {}
    for group in groups.values():
        items.update(group["items"])
    # Overlapping filters cannot be summed into a reliable total.
    total = next(iter(groups.values()))["total"] if len(groups) == 1 else None
    return AgentInventoryQuery(items=list(items.values()), total=total, as_of=as_of,
        has_more=any(len(g["items"]) < g["total"] for g in groups.values())).model_dump(mode="json")
