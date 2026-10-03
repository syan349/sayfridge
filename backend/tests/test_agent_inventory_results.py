import json
from datetime import date
from uuid import UUID, uuid4

import pytest
from langchain_core.messages import ToolMessage

from app.agents.inventory_results import capture_inventory_read, select_inventory_results
from app.schemas.agent_actions import AgentConversationState


def stock(*, estimated=False):
    return {"id": str(uuid4()), "storage_space_id": str(uuid4()), "storage_space_name": "Fridge",
        "item_definition_id": str(uuid4()), "item_definition_name": "Milk", "category_id": str(uuid4()),
        "category_name": "Dairy", "purchase_date": None, "expiry_date": "2026-10-05", "notes": None,
        "status": "IN_STOCK", "initial_amount": "2", "initial_unit": "L",
        "confirmed_current_amount": "2", "confirmed_current_unit": "L", "confirmed_at": "2026-10-01T01:00:00Z",
        "estimated_current_amount": "1.5" if estimated else None, "estimated_current_unit": "L" if estimated else None,
        "estimated_at": "2026-10-02T01:00:00Z" if estimated else None,
        "display_amount": "1.5" if estimated else "2", "display_unit": "L", "is_estimated": estimated,
        "version": 1, "created_at": "2026-10-01T01:00:00Z", "updated_at": "2026-10-02T01:00:00Z"}


def read(rows, *, args=None, total=None, name="list_inventory"):
    call = {"name": name, "args": args or {}}
    data = {"ok": True, "items": rows, "total": len(rows) if total is None else total}
    return capture_inventory_read(call, [ToolMessage(content=json.dumps(data), tool_call_id="read")])


def test_selected_owned_results_keep_batches_estimates_and_pagination():
    first, second = stock(), stock(estimated=True)
    reads = {"page1": read([first], args={"page": 1}, total=2),
             "page2": read([second], args={"status": "IN_STOCK", "page": 2, "page_size": 1}, total=2),
             "preliminary": read([stock()], args={"q": "different"})}
    result = select_inventory_results(reads, ["page1", "page2", "page1"], date(2026, 10, 3))
    assert [row["id"] for row in result["items"]] == [first["id"], second["id"]]
    assert result["items"][1]["display_amount"] == "1.5"
    assert result["items"][1]["is_estimated"] is True
    assert result["total"] == 2 and result["has_more"] is False
    assert result["as_of"] == "2026-10-03"
    state = AgentConversationState.model_validate({"status": "COMPLETED", "items": [], "inventory_query": result})
    assert state.inventory_query.items[1].id == UUID(second["id"])
    partial = select_inventory_results(reads, ["page2"], None)
    assert partial["total"] == 2 and partial["has_more"] is True


def test_filtered_empty_results_do_not_show_preliminary_matches():
    reads = {"broad": read([stock()]), "empty": read([], args={"q": "rice"})}
    result = select_inventory_results(reads, ["empty"], None)
    assert result["items"] == [] and result["total"] == 0 and result["has_more"] is False
    with pytest.raises(ValueError, match="successful inventory read"):
        select_inventory_results(reads, ["invented-id"], None)


def test_failed_and_non_inventory_tools_cannot_supply_cards():
    for content in ["Tool failed", '{"ok":false}', '{"ok":true,"items":[{"id":"invented"}],"total":1}']:
        assert capture_inventory_read({"name": "list_inventory", "args": {}},
            [ToolMessage(content=content, tool_call_id="read")]) is None
    assert read([stock()], name="list_categories") is None


def test_overlapping_filters_do_not_double_count_batches():
    item = stock()
    result = select_inventory_results({"a": read([item]), "b": read([item], args={"q": "milk"})}, ["a", "b"], None)
    assert len(result["items"]) == 1
    assert result["total"] is None and result["has_more"] is False
