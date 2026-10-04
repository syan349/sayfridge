"""Read-only model views. Never replace canonical messages or business results."""
import json

from langchain_core.messages import AIMessage, HumanMessage, ToolMessage


READ_TOOLS = frozenset({"list_inventory", "get_inventory_detail", "get_expiry_summary",
    "list_storage_spaces", "list_item_definitions", "list_item_categories"})


def message_groups(messages):
    """Atomic messages or a complete AI tool call + all matching results.

    Incomplete/malformed call groups are protected, not silently repaired.
    """
    groups, i = [], 0
    while i < len(messages):
        message = messages[i]
        group = [message]
        calls = getattr(message, "tool_calls", [])
        pending = {c["id"] for c in calls}
        i += 1
        while pending and i < len(messages) and isinstance(messages[i], ToolMessage):
            reply = messages[i]
            if reply.tool_call_id not in pending:
                break
            pending.remove(reply.tool_call_id)
            group.append(reply)
            i += 1
        groups.append((group, bool(pending) or isinstance(message, ToolMessage)))
    return groups


def protected_message_ids(messages, turn_ids=()):
    protected, active = set(turn_ids), False
    for message in messages:
        if isinstance(message, HumanMessage):
            # Item-specific supplements have request_id:item_id message IDs.
            active = str(message.id).split(":", 1)[0] in turn_ids
        if active or message.additional_kwargs.get("context_required"):
            protected.add(message.id)
    return protected


def clean_tool_results(messages, measure_text, *, limit=2000, protected_ids=(), priority_ids=()):
    """Shorten successful read lists only; preserve facts, complete rows and errors."""
    result = []
    for group, incomplete in message_groups(messages):
        if incomplete or any(m.id in protected_ids for m in group) or not isinstance(group[0], AIMessage):
            result.extend(group)
            continue
        calls = {c["id"]: c for c in group[0].tool_calls}
        result.append(group[0])
        for reply in group[1:]:
            call = calls[reply.tool_call_id]
            if call["name"] not in READ_TOOLS or not isinstance(reply.content, str) or measure_text(reply.content) <= limit:
                result.append(reply)
                continue
            try:
                data = json.loads(reply.content)
            except (ValueError, TypeError):
                result.append(reply)
                continue
            # Never truncate failures, confirmation evidence or candidate choices.
            if not isinstance(data, dict) or data.get("ok") is not True or "candidates" in data:
                result.append(reply)
                continue
            key = next((k for k in ("items", "spaces", "definitions", "categories") if isinstance(data.get(k), list)), None)
            if key is None:
                result.append(reply)
                continue
            rows = data[key]
            required = [n for n, row in enumerate(rows) if isinstance(row, dict)
                        and any(str(v) in priority_ids for k, v in row.items() if k == "id" or k.endswith("_id"))]
            selected = set(required)

            def render():
                return json.dumps({**data, key: [r for n, r in enumerate(rows) if n in selected],
                    "context_excerpt": {"incomplete": True, "omitted_rows": len(rows) - len(selected),
                        "query": call.get("args", {}), "instruction": "Partial historical read; query again for current or complete results."}},
                    ensure_ascii=False, separators=(",", ":"))

            text = render()
            if measure_text(text) > limit:
                # Required evidence (or large metadata) cannot safely be dropped.
                result.append(reply)
                continue
            for n in range(len(rows)):
                if n in selected:
                    continue
                selected.add(n)
                candidate = render()
                if measure_text(candidate) > limit:
                    selected.remove(n)
                    break
                text = candidate
            result.append(reply.model_copy(update={"content": text}))
    return result
