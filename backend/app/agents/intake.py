"""Record operation intent before optional conversational replies can end a turn."""
from langchain_core.messages import SystemMessage, ToolMessage

from app.agents.prompts import INTENT_PROMPT
from app.schemas.agent_actions import TurnIntent


async def identify_turn(model, messages):
    tool = {"type": "function", "function": {"name": "record_turn_intent",
        "description": "Record current intent and all initial stock items without executing anything.",
        "parameters": TurnIntent.model_json_schema()}}
    bound = model.bind_tools([tool], tool_choice="record_turn_intent")
    inputs = [SystemMessage(content=INTENT_PROMPT), *messages]
    for attempt in range(3):
        response = await bound.ainvoke(inputs, config={"tags": ["agent_intake"]})
        calls = response.tool_calls
        try:
            if len(calls) != 1 or calls[0]["name"] != "record_turn_intent":
                raise ValueError("Expected one intent call")
            return TurnIntent.model_validate(calls[0]["args"])
        except ValueError:
            if attempt == 2:
                raise ValueError("Unable to identify the request; no inventory changes made") from None
            inputs.append(response)
            inputs.extend(ToolMessage(content="Invalid intent schema. Record every item, or a non-inventory intent with no items.",
                                      tool_call_id=call["id"]) for call in [*calls, *response.invalid_tool_calls])
            inputs.append(SystemMessage(content="Return one valid record_turn_intent call. No actions have been executed."))


def waiting_question(item, language):
    """Stable questions are checkpointed and replayed, never generated on reconnect."""
    zh = language.lower().startswith(("zh", "chinese", "中文"))
    draft = item.get("draft", {})
    name = (draft.get("new_definition") or {}).get("name") or draft.get("item_query") or ("这件物品" if zh else "this item")
    code = item.get("error", {}).get("code")
    if code == "CLARIFICATION_REQUIRED":
        return draft.get("clarification_question") or item["error"]["message"]
    questions = {
        "MEMORY_SAVE_UNAVAILABLE": ("换算依据暂时未能保存，库存尚未修改，请稍后重试。", "The conversion could not be saved; inventory is unchanged. Please retry."),
        "QUANTITY_PRECISION_UNSUPPORTED": ("这个数量超出了当前支持的精度，请明确本次实际用量或盘点剩余数量。", "Please specify a supported amount or the actual remaining total."),
        "QUANTITY_TOO_SMALL": ("本次用量小于当前支持的精度，请调整用量后重试。", "The change is below the supported precision; please adjust the amount."),
        "QUANTITY_OUT_OF_RANGE": ("换算后的数量超出当前单位的保存范围，请使用更大的单位或确认实际数量。", "The quantity exceeds the supported range in this unit; use a larger unit or confirm the actual amount."),
        "WHOLE_COUNT_REQUIRED": (f"你实际消耗了几个{name}？如果有半个，请直接说明。", f"How many {name} did you consume? Include any partial item."),
        "SPACE_REQUIRED": (f"{name}放在哪里？", f"Where would you like to store {name}?"),
        "INITIAL_QUANTITY_REQUIRED": (f"{name}有多少？请带上单位。", f"How much {name} do you have, and in what unit?"),
        "DEFINITION_REQUIRED": (f"请具体说明{name}是什么物品。", f"Which product do you mean by {name}?"),
        "CATEGORY_REQUIRED": (f"暂时无法为{name}找到可用分类，请稍后重试。", f"A category for {name} is unavailable. Please try again later."),
        "TARGET_REQUIRED": (f"要修改哪一批{name}？", f"Which batch of {name} do you mean?"),
        "IMAGE_ACTION_NOT_SUPPORTED": ("图片目前只能用于新增库存，请用文字说明要修改的库存。", "Images can only create stock. Please describe the existing stock change in text."),
        "EXECUTION_UNCERTAIN": ("尚未确认是否保存成功，请核对后重试此操作。", "The save is not yet confirmed. Retry this operation to check its result."),
    }
    if code in questions:
        return questions[code][0 if zh else 1]
    if item["status"] == "NEEDS_CONFIRMATION":
        image = "IMAGE_REVIEW" in item.get("preview", {}).get("confirmation_reasons", [])
        return ((f"请核对并确认{name}的图片识别结果。" if image else f"请核对并确认{name}的操作。") if zh
                else (f"Please review and confirm the image details for {name}." if image else f"Please review and confirm the change to {name}."))
    return f"{name}暂未处理完成，请检查信息后重试。" if zh else f"{name} has not been processed. Please check the details and retry."


def outcome_text(items, language):
    """Summarize committed receipts, never ask for approval after a successful write."""
    from decimal import Decimal
    zh = language.lower().startswith(("zh", "chinese", "中文"))
    lines = []
    for item in items:
        draft = item.get("draft", {})
        saved = item.get("result", {}).get("inventory", {})
        name = saved.get("item_definition_name") or (draft.get("new_definition") or {}).get("name") or draft.get("item_query") or ("物品" if zh else "Item")
        if item["status"] == "CANCELLED":
            lines.append(f"已取消{name}的操作。" if zh else f"Cancelled the change to {name}.")
        elif item["status"] == "FAILED":
            lines.append(f"{name}未修改成功。" if zh else f"Could not update {name}.")
        else:
            amount = saved.get("display_amount", saved.get("confirmed_current_amount"))
            unit = saved.get("display_unit", saved.get("confirmed_current_unit", ""))
            if amount is None:
                lines.append(f"已更新{name}。" if zh else f"Updated {name}.")
                continue
            amount = format(Decimal(str(amount)), "f")
            if "." in amount:
                amount = amount.rstrip("0").rstrip(".")
            quantity = f"{amount} {unit}".strip()
            if draft.get("action") == "CREATE_STOCK":
                space = saved.get("storage_space_name") or item.get("preview", {}).get("display", {}).get("space_name")
                lines.append((f"已将{quantity} {name}加入{space}。" if space else f"已添加{quantity} {name}。") if zh
                             else (f"Added {quantity} of {name} to {space}." if space else f"Added {quantity} of {name}."))
            else:
                estimated = saved.get("is_estimated", saved.get("estimated_current_amount") is not None)
                relation = item.get("preview", {}).get("unit_relationship")
                operation = item.get("result", {}).get("operation") or {}
                input_amount = operation.get("quantity_value", draft.get("quantity_value"))
                input_unit = operation.get("quantity_unit", draft.get("quantity_unit"))
                if relation:
                    action = "消耗" if draft.get("action") == "CONSUME" else "添加"
                    lines.append(f"已{action}{input_amount} {input_unit} {name}，按换算关系估算，剩余约{quantity}。" if zh
                        else f"Updated {name} by {input_amount} {input_unit} using an estimated conversion. Remaining: about {quantity}.")
                else:
                    lines.append(f"已更新{name}，剩余{'约' if estimated else ''}{quantity}。" if zh
                                 else f"Updated {name}. Remaining: {'about ' if estimated else ''}{quantity}.")
    return "\n".join(lines)
