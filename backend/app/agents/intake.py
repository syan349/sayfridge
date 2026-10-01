"""Record intent and phrase questions from server-validated missing facts."""
import json
import re
from pydantic import BaseModel, Field, ConfigDict
from langchain_core.messages import SystemMessage, ToolMessage

from app.agents.prompts import INTENT_PROMPT
from app.schemas.agent_actions import TurnIntent
from app.agents.facts import missing_fields


async def identify_turn(model, messages, *, known_completed_ids=(), known_image_ids=None):
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
            parsed = TurnIntent.model_validate(calls[0]["args"])
            if known_image_ids is not None and any(not {str(i) for i in item.source_image_ids}.issubset(set(known_image_ids)) for item in parsed.items):
                raise ValueError("Use image references only from this request's available image metadata; unrelated historical images are not task sources")
            if parsed.kind == "REPLAY" and not {str(i) for i in parsed.replay_item_ids}.issubset(set(known_completed_ids)):
                raise ValueError("Replay must use completed item_id values from the supplied data, not proposal, inventory or invented IDs")
            return parsed
        except ValueError as exc:
            if attempt == 2:
                raise ValueError("Unable to identify the request; no inventory changes made") from None
            inputs.append(response)
            inputs.extend(ToolMessage(content="Invalid intent schema. " + str(exc)[:300] + ". Record every item, or a non-inventory intent with no items.",
                                      tool_call_id=call["id"]) for call in [*calls, *response.invalid_tool_calls])
            inputs.append(SystemMessage(content="Return one valid record_turn_intent call. No actions have been executed."))


def waiting_question(item, language):
    """Stable questions are checkpointed and replayed, never generated on reconnect."""
    zh = language.lower().startswith(("zh", "chinese", "中文"))
    draft = item.get("draft", {})
    name = (draft.get("new_definition") or {}).get("name") or draft.get("item_query") or ("这件物品" if zh else "this item")
    code = item.get("error", {}).get("code")
    missing = missing_fields(item)
    if code in {"INITIAL_QUANTITY_REQUIRED", "QUANTITY_REQUIRED"}:
        if missing == ["quantity_unit"]:
            amount = draft.get("quantity_value", "")
            return f"{name}的{amount}是什么单位？" if zh else f"What unit is the {amount} of {name} in?"
        if missing == ["quantity_value"]:
            unit = draft.get("quantity_unit", "")
            return f"{name}有多少{unit}？" if zh else f"How many {unit} of {name}?"
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
        "IMAGE_QUANTITY_UNCLEAR": (f"{name}的数量看不清或异常，请说明实际购买数量。", f"The printed quantity for {name} is unclear or unusual. What quantity did you buy?"),
    }
    if code in questions:
        return questions[code][0 if zh else 1]
    if item["status"] == "NEEDS_CONFIRMATION":
        image = "IMAGE_REVIEW" in item.get("preview", {}).get("confirmation_reasons", [])
        quantity = " ".join(str(draft.get(f) or "") for f in ("quantity_value", "quantity_unit")).strip()
        package = draft.get("package_description")
        details = f"{name} {quantity}" + (f"（{package}）" if package else "")
        return ((f"请核对并确认：{details}。" if image else f"请确认{details}的操作。") if zh
                else (f"Please review and confirm: {details}." if image else f"Please confirm the change to {details}."))
    return f"{name}暂未处理完成，请检查信息后重试。" if zh else f"{name} has not been processed. Please check the details and retry."


class Question(BaseModel):
    model_config = ConfigDict(extra="forbid")
    item_key: str
    question: str = Field(min_length=1, max_length=250)
    fields: list[str] = Field(default_factory=list, max_length=8)


class Questions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    questions: list[Question] = Field(default_factory=list, max_length=20)


async def phrase_questions(model, items, messages, language):
    """One bounded call per changed group; failure keeps field-specific fallbacks."""
    candidates = [i for i in items if i["status"] == "NEEDS_INPUT" and not i.get("question")
                  and i.get("error", {}).get("code") not in {"CATEGORY_REQUIRED", "MEMORY_SAVE_UNAVAILABLE", "PROPOSAL_REQUIRED"}]
    if not candidates:
        return
    data = [{"item_key": i["item_key"], "known": i["draft"], "error": i.get("error"),
             "missing_fields": missing_fields(i), "fallback": waiting_question(i, language),
             "user_words": i.get("source_texts", [])[-2:]} for i in candidates]
    tool = {"type": "function", "function": {"name": "phrase_inventory_questions",
        "description": "Phrase short questions for server-validated gaps without changing any operation.",
        "parameters": Questions.model_json_schema()}}
    try:
        response = await model.bind_tools([tool], tool_choice="phrase_inventory_questions").ainvoke([
            SystemMessage(content="Write one short, natural question in the user's language for each item. "
                "Ask ONLY its actual missing_fields or the specific validation doubt. Do not ask for known quantity/unit/location. "
                "The fields array must equal missing_fields; for a semantic doubt with no missing_fields use []. "
                "Use the user's words and known facts. No internal field names, technical details, success claims or extra questions. "
                f"Language: {language}. Server DATA: " + json.dumps(data, ensure_ascii=False, default=str)),
            *[m for m in messages[-4:] if m.type in {"human", "ai"} and isinstance(m.content, str) and not getattr(m, "tool_calls", [])]
        ], config={"tags": ["agent_questions"]})
        if len(response.tool_calls) != 1 or response.tool_calls[0]["name"] != "phrase_inventory_questions":
            return
        parsed = Questions.model_validate(response.tool_calls[0]["args"])
        known = {i["item_key"]: i for i in candidates}
        if len({q.item_key for q in parsed.questions}) != len(parsed.questions):
            return
        for q in parsed.questions:
            item = known.get(q.item_key)
            if item and set(q.fields) == set(missing_fields(item)) and not re.search(
                    r"quantity_|storage_space|inventory_item|item_definition|proposal_id|NEEDS_|CREATE_STOCK", q.question):
                item["question"] = q.question.strip()
    except Exception:
        # Question wording must never change whether the backend can write.
        return


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
        elif item["status"] == "SUCCEEDED" and item.get("result"):
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
