"""Target recovery uses the existing tool loop, with bounded durable evidence."""
import asyncio
import json
from copy import deepcopy
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage, ToolMessage
from langchain_core.tools import tool
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
from test_agent_workflow import (
    ScriptModel,
    call,
    draft,
    fake_session,
    initial,
    intake,
    setup_services,
)

from app.agents import workflow
from app.agents.facts import missing_fields
from app.agents.intake import phrase_questions, waiting_question
from app.agents.state import AgentContext
from app.agents.target_resolution import (
    lookup_active,
    lookup_observation,
    record_target_read,
    target_reason,
)
from app.services.agent_actions import PreparationError

pytestmark = pytest.mark.ci


def test_resolved_target_does_not_spend_lookup_budget_on_other_preparation():
    item = {"status": "DRAFT", "draft": {}, "target_lookup": {"revisions": 1, "reads": 6}}
    assert lookup_active(item)
    item["draft"]["inventory_item_id"] = str(uuid4())
    assert not lookup_active(item)


def no_match():
    return PreparationError("TARGET_REQUIRED", "Inspect actual inventory", {"reason": "NO_MATCH", "candidates": [], "total": 0})


def read_call(**args):
    return AIMessage(content="", tool_calls=[{"name": "list_inventory", "args": args, "id": str(uuid4()), "type": "tool_call"}])


def observe(item, *, page=1, size=2, total=3, count=2, args=None, failed=False):
    invocation = {"name": "list_inventory", "id": "read", "args": args or {"q": ""}}
    content = {"ok": False} if failed else {"ok": True, "page": page, "page_size": size, "total": total, "items": [{}] * count}
    record_target_read(item, invocation, [ToolMessage(content=json.dumps(content), tool_call_id="read")])


def test_read_evidence_is_bounded_paginated_and_does_not_mutate_checkpoint():
    item = {"target_lookup": {"revisions": 1}}
    previous = deepcopy(item)
    observe(item, page=2, count=1)
    assert lookup_observation(item) == "INCOMPLETE"
    assert previous == {"target_lookup": {"revisions": 1}}
    observe(item)
    assert lookup_observation(item) == "INCOMPLETE"  # page 1 begins a new scan
    observe(item, page=2, count=1)
    assert lookup_observation(item) == "COMPLETE"
    observe(item, failed=True)
    assert lookup_observation(item) == "FAILED"
    observe(item, total=0, count=0)
    assert lookup_observation(item) == "EMPTY"
    assert item["target_lookup"]["reads"] == 5


@pytest.mark.parametrize("args", [{"q": "苹果"}, {"storage_space_id": str(uuid4())}, {"category_id": str(uuid4())}, {"status": "ALL"}])
def test_filtered_empty_result_never_claims_global_empty(args):
    item = {}
    observe(item, total=0, count=0, args=args)
    assert lookup_observation(item) == "UNRESOLVED"


def test_new_stock_invalidates_previous_empty_observation():
    item = {}
    observe(item, total=0, count=0)
    assert lookup_observation(item) == "EMPTY"
    observe(item, total=1, count=1, args={"q": "Apples"})
    assert lookup_observation(item) == "UNRESOLVED"


def test_legacy_target_errors_and_fixed_questions():
    old = {"code": "TARGET_REQUIRED", "details": {"total": 0, "candidates": []}}
    assert target_reason(old) == "NO_MATCH"
    assert target_reason({"code": "TARGET_REQUIRED", "details": {}}) == "MISSING_QUERY"
    item = {"item_key": "apple", "status": "NEEDS_INPUT", "draft": {"item_query": "苹果"}, "error": old}
    assert missing_fields(item) == []
    assert "哪一批" not in waiting_question(item, "zh")
    class MustNotPhrase:
        def bind_tools(self, *args, **kwargs):
            pytest.fail("No-match wording must not be rewritten by the model")
    asyncio.run(phrase_questions(MustNotPhrase(), [item], [], "zh"))
    observe(item, failed=True)
    assert "无法读取" in waiting_question(item, "zh")
    observe(item, total=0, count=0)
    assert "没有在库" in waiting_question(item, "zh")


@pytest.mark.parametrize("read_count", [1, 6])
def test_early_proposal_returns_to_existing_tools_then_succeeds(monkeypatch, read_count):
    setup_services(monkeypatch)
    action = {**draft("apple"), "item_query": "苹果", "quantity_unit": "个"}
    target_id = str(uuid4())
    observed, executed = [], []
    @tool
    async def list_inventory(q: str = "", page: int = 1) -> str:
        """Read actual stock."""
        observed.append((q, page))
        return json.dumps({"ok": True, "items": [{"id": target_id, "item_definition_name": "Apples"}],
                           "total": 1, "page": 1, "page_size": 20})
    async def prepare(session, user, draft, memory, as_of, **kwargs):
        if not draft.inventory_item_id:
            raise no_match()
        assert str(draft.inventory_item_id) == target_id
        assert draft.quantity_value == "1" and draft.quantity_unit == "个"
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": False, "memory_snapshots": []}
    async def execute(*args, **kwargs):
        executed.append(args[5]["draft"])
        return {"inventory": {"id": target_id}}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    async def scenario():
        model = ScriptModel([call([action]), *[read_call() for _ in range(read_count)],
                             call([{**action, "inventory_item_id": target_id}])], intents=[intake([action])])
        graph = workflow.build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[list_inventory])
        config = {"configurable": {"thread_id": str(uuid4())}, "recursion_limit": 100}
        result = await graph.ainvoke(initial(), config, context=AgentContext(uuid4(), None, uuid4()))
        assert result["items"][0]["status"] == "SUCCEEDED"
        assert not (await graph.aget_state(config)).next
        assert result["items"][0]["target_lookup"]["reads"] == read_count
    asyncio.run(scenario())
    assert observed == [("", 1)] * read_count and len(executed) == 1


@pytest.mark.parametrize("repeat_tools", [False, True])
def test_exhaustion_pauses_and_new_answer_resets_only_its_budget(monkeypatch, repeat_tools):
    setup_services(monkeypatch)
    actions = [draft("apple"), draft("pear")]
    read_count = []
    @tool
    async def list_inventory(q: str = "") -> str:
        """Read stock."""
        read_count.append(q)
        return json.dumps({"ok": True, "items": [], "total": 0, "page": 1, "page_size": 20})
    async def prepare(*args, **kwargs):
        raise no_match()
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    async def scenario():
        responses = ([call(actions), *[read_call(q="apple") for _ in range(8)], call(actions)] if repeat_tools
                     else [call(actions)] * 8)
        model = ScriptModel(responses, intents=[intake(actions)])
        saver = InMemorySaver()
        graph = workflow.build_agent_graph(model, checkpointer=saver, store=InMemoryStore(), session_factory=fake_session, tools=[list_inventory])
        config = {"configurable": {"thread_id": str(uuid4())}, "recursion_limit": 160}
        context = AgentContext(uuid4(), None, uuid4())
        await graph.ainvoke(initial(), config, context=context)
        snapshot = await graph.aget_state(config)
        assert all(i["status"] == "NEEDS_INPUT" for i in snapshot.values["items"])
        original = deepcopy(snapshot.values["items"])
        assert original[0]["target_lookup"]["reads" if repeat_tools else "revisions"] == (6 if repeat_tools else 2)
        # The second item enters recovery after the first has paused; its own
        # remaining scripted read is allowed, without reopening the first.
        assert len(read_count) == (7 if repeat_tools else 0)
        assert all(i["target_lookup"].get("reads", 0) <= 6 for i in original)
        # Rebuild the graph from the same checkpoint, then answer only one item.
        graph = workflow.build_agent_graph(ScriptModel([call([actions[0]])] * 4), checkpointer=saver,
            store=InMemoryStore(), session_factory=fake_session, tools=[list_inventory])
        intr = snapshot.tasks[0].interrupts[0]
        item = original[0]
        reply = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()), "interrupt_id": intr.id,
                 "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "answer", "message": "The kitchen apples"}]}
        await graph.ainvoke(Command(resume={intr.id: reply}), config, context=context)
        final = (await graph.aget_state(config)).values["items"]
        assert final[0]["target_lookup"].get("reads", 0) == 0 and final[0]["target_lookup"]["revisions"] == 2
        assert final[1]["target_lookup"] == original[1]["target_lookup"]
        assert all(missing_fields(i) == [] for i in final)
    asyncio.run(scenario())
