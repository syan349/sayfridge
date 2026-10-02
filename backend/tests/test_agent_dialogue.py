"""Business guards for incomplete facts, scoped answers and durable continuations."""
import asyncio
from copy import deepcopy
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command

from app.agents import workflow, continuation
from app.agents.continuation import Continuation, ContinuationAnswer, interpret_continuation
from app.agents.facts import missing_fields, merge_draft, retain_receipt_quantity
from app.agents.intake import waiting_question, phrase_questions, outcome_text
from app.agents.messages import human_message, image_catalog
from app.agents.state import AgentContext
from app.schemas.agent_actions import ActionDraft
from app.services.agent_actions import PreparationError, prepare_action
from agent_image_support import image_input
from test_agent_workflow import ScriptModel, call, intake, initial, fake_session, setup_services

pytestmark = pytest.mark.ci


def stock(key="tomato", **changes):
    return {"item_key": key, "original_text": f"Add {key}", "action": "CREATE_STOCK",
            "item_query": key, "quantity_value": "3", **changes}


def record(action):
    return {"item_id": str(uuid4()), "item_key": action["item_key"], "proposal_id": str(uuid4()),
            "original_text": action["original_text"], "status": "NEEDS_INPUT",
            "draft": ActionDraft.model_validate(action).model_dump(mode="json")}


@pytest.mark.parametrize("value,unit,fields", [("3", None, ["quantity_unit"]),
    (None, "袋", ["quantity_value"]), (None, None, ["quantity_value", "quantity_unit"])])
def test_preparation_and_display_report_only_actual_quantity_holes(value, unit, fields):
    item = record(stock(quantity_value=value, quantity_unit=unit))
    async def scenario():
        with pytest.raises(PreparationError) as exc:
            await prepare_action(object(), uuid4(), ActionDraft.model_validate(item["draft"]), object())
        item["error"] = {"code": exc.value.code, "details": exc.value.details}
        assert workflow.public_item(item)["display"]["missing_fields"] == fields
        question = waiting_question(item, "zh")
        if fields == ["quantity_unit"]:
            assert "3" in question and "多少" not in question
        elif fields == ["quantity_value"]:
            assert "袋" in question and "单位" not in question
    asyncio.run(scenario())


def test_fraction_never_requests_a_unit_and_success_requires_a_receipt():
    item = record(stock(action="CONSUME", quantity_kind="FRACTION", quantity_value="1/2"))
    item["error"] = {"code": "QUANTITY_REQUIRED"}
    assert missing_fields(item) == []
    assert outcome_text([item], "en") == ""
    item["status"] = "SUCCEEDED"
    assert outcome_text([item], "en") == ""


def test_empty_fields_preserve_facts_correction_replaces_and_withdrawal_requires_evidence():
    photo = str(uuid4())
    action = stock(quantity_unit="盒", package_description="500 g per box", source_image_ids=[photo],
                   purchase_date="2026-10-01", review_notes=["printed row"])
    item = record(action)
    item.update(revision_requested=True, source_texts=["Change the count to 4"])
    result = merge_draft(item, ActionDraft.model_validate(stock(quantity_value="4", quantity_unit=None,
        package_description=None, source_image_ids=[], purchase_date=None, review_notes=[])))
    assert (result.quantity_value, result.quantity_unit, result.package_description) == ("4", "盒", "500 g per box")
    assert str(result.source_image_ids[0]) == photo and result.purchase_date.isoformat() == "2026-10-01"
    assert result.review_notes == ["printed row"] and result.original_text == item["original_text"]
    with pytest.raises(ValueError, match="withdrawal"):
        merge_draft(item, ActionDraft.model_validate(stock(clear_fields=["quantity_value"])))
    item["source_texts"].append("I'm not sure about the count; clear it")
    result = merge_draft(item, ActionDraft.model_validate(stock(clear_fields=["quantity_value"],
        clear_fields_evidence="I'm not sure about the count; clear it")))
    assert result.quantity_value is None and result.quantity_unit == "盒"


def test_initial_image_proposal_cannot_round_extracted_quantity_or_invent_missing_unit():
    item = record(stock(quantity_value="1.0015", source_image_ids=[str(uuid4())], quantity_issue="Unusual printed count"))
    result = merge_draft(item, ActionDraft.model_validate(stock(quantity_value="1", quantity_unit="瓶")))
    assert result.quantity_value == "1.0015" and result.quantity_unit is None
    assert result.quantity_issue == "Unusual printed count"
    item.update(revision_requested=True, source_texts=["It was one bottle"])
    result = merge_draft(item, ActionDraft.model_validate(stock(quantity_value="1", quantity_unit="瓶")))
    assert result.quantity_value == "1" and result.quantity_issue is None


@pytest.mark.parametrize("line,value,unit,unclear", [
    ("0.835 Kg @ $5.49/Kg", "0.835", "kg", False),
    ("0.17 @ 3.99", "0.17", None, True),
    ("1.0015 @ 2.14", "1.0015", None, True),
    ("2 @ $5.19", "2", "each", False),
])
def test_receipt_raw_line_catches_weight_assumptions_and_silent_rounding(line, value, unit, unclear):
    draft = ActionDraft.model_validate(stock(quantity_value="1", quantity_unit="each" if unit else "kg",
        source_image_ids=[str(uuid4())], receipt_quantity_text=line))
    result = retain_receipt_quantity(draft)
    assert (result.quantity_value, result.quantity_unit, bool(result.quantity_issue)) == (value, unit, unclear)


@pytest.mark.parametrize("wrong", [False, True])
def test_natural_question_must_match_backend_fields_and_never_change_task(wrong):
    item = record(stock())
    item["error"] = {"code": "INITIAL_QUANTITY_REQUIRED"}
    untouched = deepcopy(item["draft"])
    fields = ["quantity_value", "quantity_unit"] if wrong else ["quantity_unit"]
    response = AIMessage(content="", tool_calls=[{"id": "q", "name": "phrase_inventory_questions", "type": "tool_call",
        "args": {"questions": [{"item_key": item["item_key"], "question": "这 3 是按什么单位算的？", "fields": fields}]}}])
    class Model:
        def bind_tools(self, *args, **kwargs):
            return self
        async def ainvoke(self, *args, **kwargs):
            return response
    asyncio.run(phrase_questions(Model(), [item], [HumanMessage(content="西红柿 3")], "zh"))
    assert item["draft"] == untouched and item["status"] == "NEEDS_INPUT"
    assert ("question" in item) == (not wrong)


def test_continuation_model_receives_actual_supplement_image_without_text_confirmation():
    photo = image_input("3 boxes")
    item = record(stock())
    class Model:
        def bind_tools(self, *args, **kwargs):
            return self
        async def ainvoke(self, messages, **kwargs):
            assert any(isinstance(m.content, list) and any(b["type"] == "image_url" for b in m.content) for m in messages)
            return AIMessage(content="", tool_calls=[{"id": "r", "type": "tool_call", "name": "route_pending_message",
                "args": {"mode": "CONTINUE", "responses": [{"item_id": item["item_id"], "decision": "answer",
                                                          "evidence": "", "image_ids": [str(photo.image_id)]}]}}])
    routed = asyncio.run(interpret_continuation(Model(), [item], "", images=[photo]))
    assert routed.responses[0].decision == "answer" and routed.responses[0].image_ids


def test_duplicate_photo_is_one_image_but_same_named_receipt_rows_remain_separate():
    first = image_input("BEEF\nBEEF")
    second = first.model_copy(update={"image_id": uuid4()})
    message = human_message("enter", [first, second], "1")
    assert len(image_catalog([message])) == 1
    assert sum(b["type"] == "image_url" for b in message.content) == 1
    repeat = human_message("enter those", [second], "2", known_messages=[message])
    assert not any(b["type"] == "image_url" for b in repeat.content)
    assert len(image_catalog([message, repeat])) == 1


@pytest.mark.parametrize("buffered", [False, True])
def test_local_answer_cannot_modify_other_task_and_ambiguous_answer_survives_restart(monkeypatch, buffered):
    setup_services(monkeypatch)
    actions = [stock("tomato"), stock("tofu", quantity_value="2")]
    malicious = [stock("tomato", quantity_unit="个"), stock("tofu", quantity_value="99", quantity_unit="盒")]
    writes = []
    async def prepare(session, user, draft, memory, as_of, **kwargs):
        if not draft.quantity_unit:
            raise PreparationError("INITIAL_QUANTITY_REQUIRED", "Unit needed")
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": False}
    async def execute(*args, **kwargs):
        writes.append(args[5]["draft"])
        return {"inventory": {"confirmed_current_amount": "3", "confirmed_current_unit": "个"}}
    async def route(model, items, message, **kwargs):
        if message == "个" and buffered:
            return Continuation(mode="UNCLEAR", question="是西红柿还是豆腐？")
        if buffered:
            assert kwargs["unresolved"]["message"] == "个"
        target = next(i for i in items if i["item_key"] == "tomato")
        return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(item_id=target["item_id"],
            decision="answer", message=message, evidence=message)])
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    monkeypatch.setattr(continuation, "interpret_continuation", route)
    async def scenario():
        model = ScriptModel([call(actions), call(malicious)], intents=[intake(actions)])
        saver, store = InMemorySaver(), InMemoryStore()
        def build():
            return workflow.build_agent_graph(model, checkpointer=saver, store=store, session_factory=fake_session, tools=[])
        graph, config = build(), {"configurable": {"thread_id": str(uuid4())}}
        context = AgentContext(uuid4(), None, uuid4())
        state = await graph.ainvoke(initial(), config, context=context)
        old = deepcopy(state["items"])
        async def supplement(text):
            snap = await graph.aget_state(config)
            return await build().ainvoke(Command(resume={snap.tasks[0].interrupts[0].id: {
                "chat_message": text, "request_id": str(uuid4()), "fingerprint": text}}), config, context=context)
        if buffered:
            state = await supplement("个")
            assert not writes and state["unresolved_reply"]["message"] == "个"
            assert workflow.public_item(state["items"][0])["display"]["question"] == "是西红柿还是豆腐？"
        state = await supplement("西红柿" if buffered else "西红柿的单位是个")
        assert len(writes) == 1 and writes[0]["quantity_value"] == "3"
        tofu = next(i for i in state["items"] if i["item_key"] == "tofu")
        assert tofu == old[1], "An unassociated task must retain its draft, proposal and question"
        assert state["unresolved_reply"] is None
        assert state["items"][0]["item_id"] == old[0]["item_id"]
    asyncio.run(scenario())


def test_old_image_does_not_require_review_for_unrelated_text_stock(monkeypatch):
    setup_services(monkeypatch)
    photo = image_input()
    state = {"messages": [human_message("what is this?", [photo], "1"), HumanMessage(content="I bought 3 tofu")],
             "turn_has_images": False, "image_task_active": False}
    draft = ActionDraft.model_validate(stock("tofu", quantity_unit="each"))
    assert workflow.image_policy(state, draft) == {"create_only": False, "requires_review": False, "source_image_ids": []}


def test_long_single_turn_keeps_photo_and_real_query_results_with_complete_tool_groups():
    photo = image_input()
    messages = [human_message("enter", [photo], "receipt")]
    for n in range(9):
        messages.extend([AIMessage(content="", tool_calls=[{"id": f"q{n}", "type": "tool_call",
            "name": "lookup_item_definitions", "args": {"query": f"item{n}"}}]),
            ToolMessage(content=f'{{"id":"actual-id-{n}","name":"item{n}"}}', tool_call_id=f"q{n}")])
    reduced = workflow.concise_tool_history(messages)
    assert reduced[1] == messages[0]
    assert len([m for m in reduced if isinstance(m, AIMessage)]) == 4
    assert all(f"actual-id-{n}" in str(reduced[0].content) for n in range(5))
    pending = set()
    for message in reduced:
        if isinstance(message, AIMessage):
            pending.update(c["id"] for c in message.tool_calls)
        if isinstance(message, ToolMessage):
            assert message.tool_call_id in pending
            pending.remove(message.tool_call_id)
    assert not pending and len(image_catalog(reduced)) == 1


def test_edit_cannot_remove_explicit_confirmation_requirement():
    item = record(stock(quantity_unit="盒", confirmation_requested=True))
    item.update(revision_requested=True, confirmation_required=True)
    edited = merge_draft(item, ActionDraft.model_validate(stock(quantity_value="4", quantity_unit="盒", confirmation_requested=False)))
    assert edited.quantity_value == "4" and edited.confirmation_requested is True


def test_text_proposal_cannot_replace_extracted_purchase_quantity_with_package_size():
    item = record(stock(quantity_value="2", quantity_unit="袋", package_description="500g each"))
    proposal = ActionDraft.model_validate(stock(quantity_value="500", quantity_unit="g", package_description=None))
    result = merge_draft(item, proposal)
    assert (result.quantity_value, result.quantity_unit, result.package_description) == ("2", "袋", "500g each")


def test_explicit_quantity_correction_does_not_keep_old_receipt_doubt_active():
    item = record(stock(quantity_value="1.0015", quantity_unit="瓶", quantity_issue="Unusual old printed count"))
    item.update(revision_requested=True, source_texts=["气泡水实际买了一瓶。"])
    edited = merge_draft(item, ActionDraft.model_validate(stock(quantity_value="1", quantity_unit="瓶",
        quantity_issue="The old receipt printed an unusual number")))
    assert edited.quantity_value == "1" and edited.quantity_issue is None


def test_packaged_receipt_integer_count_without_unit_does_not_ask_user_to_repeat_it():
    draft = ActionDraft.model_validate(stock(quantity_value="1.00", quantity_unit=None,
        package_description="500g", source_image_ids=[str(uuid4())], receipt_quantity_text="1.00 @ 5.99"))
    result = retain_receipt_quantity(draft)
    assert result.quantity_value == "1.00" and result.quantity_unit == "each"
    assert result.package_description == "500g" and result.quantity_issue is None


def test_model_question_cannot_hide_a_real_unit_gap():
    draft = ActionDraft.model_validate(stock(quantity_value="0.17", quantity_unit=None,
        clarification_question="What unit is the onion amount in?"))
    async def scenario():
        with pytest.raises(PreparationError) as exc:
            await prepare_action(object(), uuid4(), draft, object())
        assert exc.value.code == "INITIAL_QUANTITY_REQUIRED"
        assert exc.value.details["missing_fields"] == ["quantity_unit"]
    asyncio.run(scenario())


@pytest.mark.parametrize("message", ["不要确认全部商品", "确认全部商品吗？", "确认全部商品，但改成3个", "如果确认全部商品", "好像可以"])
def test_group_confirmation_does_not_accept_negation_questions_or_edits(message):
    assert not continuation.explicit_group_confirmation(message)


def test_explicit_group_confirmation_targets_only_reviewable_current_proposals():
    items = [record(stock()), record(stock("rice", quantity_unit="kg"))]
    items[1]["status"] = "NEEDS_CONFIRMATION"
    result = asyncio.run(interpret_continuation(object(), items, "确认以上所有商品入库。"))
    assert [r.item_id for r in result.responses] == [items[1]["item_id"]]
    assert result.responses[0].decision == "confirm"
