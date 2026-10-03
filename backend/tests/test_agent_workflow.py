import asyncio
import json
from contextlib import asynccontextmanager
from types import SimpleNamespace
from uuid import uuid4

import pytest

from langchain_core.messages import AIMessage, HumanMessage
from langchain_core.tools import tool
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command

from app.agents.state import AgentContext
from app.agents.workflow import build_agent_graph
from app.services import agent_actions, storage_spaces
from app.services.inventory import InventoryError


class ScriptModel:
    def __init__(self, messages, *, intents=()):
        self.messages = iter(messages)
        self.intents = iter(intents)
    def bind_tools(self, tools, **kwargs):
        return self
    async def ainvoke(self, messages, **kwargs):
        if "agent_summary" in kwargs.get("config", {}).get("tags", []):
            return AIMessage(content="Historical conversation facts retained.")
        if "agent_intake" in kwargs.get("config", {}).get("tags", []):
            return next(self.intents)
        if "agent_questions" in kwargs.get("config", {}).get("tags", []):
            return AIMessage(content="")
        return next(self.messages, AIMessage(content="Completed results reported."))


@asynccontextmanager
async def fake_session():
    yield object()


def call(actions):
    return AIMessage(content="", tool_calls=[{"name": "propose_inventory_actions", "args": {"actions": actions}, "id": str(uuid4()), "type": "tool_call"}])


def intake(actions=(), *, kind=None, language="en", exceeds_item_limit=False):
    from app.schemas.agent_actions import IntentItem
    fields = IntentItem.model_fields
    return AIMessage(content="", tool_calls=[{"name": "record_turn_intent", "id": str(uuid4()), "type": "tool_call",
        "args": {"kind": kind or ("INVENTORY" if actions or exceeds_item_limit else "QUERY"), "language": language,
                 "items": [{k: v for k, v in action.items() if k in fields} for action in actions], "exceeds_item_limit": exceeds_item_limit}}])


def initial():
    return {"messages": [HumanMessage(content="use three items")], "turn_id": str(uuid4()),
            "request_fingerprint": "test", "items": [], "requests": {}, "resume_requests": {}}


def draft(key):
    return {"item_key": key, "original_text": key, "action": "CONSUME", "item_query": key, "quantity_value": "1", "quantity_unit": "kg"}


def setup_services(monkeypatch):
    async def spaces(*args, **kwargs):
        return [], 0
    monkeypatch.setattr(storage_spaces, "list_storage_spaces", spaces)


def test_partial_success_failure_pause_resume_and_cancel(monkeypatch):
    from app.agents import workflow
    setup_services(monkeypatch)
    executed = []
    async def prepare(session, user, draft, memory, as_of):
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": draft.item_key == "estimated", "memory_snapshots": []}
    async def execute(session, user, conversation, turn, proposal, preview, memory, approved=False):
        key = preview["draft"]["item_key"]
        executed.append(key)
        if key == "failed":
            raise InventoryError("INSUFFICIENT_QUANTITY", "Not enough")
        assert key != "estimated" or approved
        return {"inventory": {"id": key}}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    async def scenario():
        graph = build_agent_graph(ScriptModel([call([draft(k) for k in ("ok", "failed", "estimated")])], intents=[intake([draft(k) for k in ("ok", "failed", "estimated")])]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        config = {"configurable": {"thread_id": "partial"}, "recursion_limit": 80}
        context = AgentContext(uuid4(), None, uuid4())
        await graph.ainvoke(initial(), config, context=context)
        state = await graph.aget_state(config)
        assert [i["status"] for i in state.values["items"]] == ["SUCCEEDED", "FAILED", "NEEDS_CONFIRMATION"]
        item = state.values["items"][-1]
        intr = state.tasks[0].interrupts[0]
        response = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()), "interrupt_id": intr.id,
            "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "confirm"}]}
        final = await graph.ainvoke(Command(resume={intr.id: response}), config, context=context)
        assert [i["status"] for i in final["items"]] == ["SUCCEEDED", "FAILED", "SUCCEEDED"]
        assert executed == ["ok", "failed", "estimated"]
        assert not (await graph.aget_state(config)).next
    asyncio.run(scenario())


def test_tool_runtime_user_is_injected(monkeypatch):
    from langgraph.prebuilt import ToolRuntime
    setup_services(monkeypatch)
    seen = []
    @tool
    async def who(runtime: ToolRuntime[AgentContext]) -> str:
        """Read the authenticated identity."""
        seen.append(runtime.context.user_id)
        return "ok"
    async def scenario():
        user = uuid4()
        graph = build_agent_graph(ScriptModel([AIMessage(content="", tool_calls=[{"name": "who", "args": {}, "id": "t", "type": "tool_call"}]), AIMessage(content="Done")], intents=[intake()]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[who])
        await graph.ainvoke(initial(), {"configurable": {"thread_id": "tools"}}, context=AgentContext(user, None, uuid4()))
        assert seen == [user]
    asyncio.run(scenario())


def test_inventory_cards_use_selected_reads_and_survive_replay_but_not_a_report(monkeypatch):
    from langgraph.prebuilt import ToolRuntime
    from app.agents.workflow import public_state
    from test_agent_inventory_results import stock
    setup_services(monkeypatch)
    owned_item = stock(estimated=True)
    user = uuid4()
    @tool
    async def list_inventory(runtime: ToolRuntime[AgentContext]) -> str:
        """Read owned stock."""
        assert runtime.context.user_id == user
        return json.dumps({"ok": True, "items": [owned_item], "total": 1})
    read_call = AIMessage(content="", tool_calls=[{"name": "list_inventory", "args": {}, "id": "owned-read", "type": "tool_call"}])
    present = AIMessage(content="", tool_calls=[{"name": "present_inventory_results", "args": {
        "introduction": "Here’s what’s currently in your fridge.", "source_tool_call_ids": ["owned-read"]},
        "id": "cards", "type": "tool_call"}])
    async def scenario():
        graph = build_agent_graph(ScriptModel([read_call, present, read_call.model_copy(update={"id": str(uuid4())}),
            AIMessage(content="Here’s your report.\n\n## Inventory report\n\n### Fridge\n1. **Milk** — estimated 1.5 L")], intents=[intake(), intake()]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[list_inventory])
        config = {"configurable": {"thread_id": "query-cards"}}
        context = AgentContext(user, None, uuid4(), inventory_cards=True)
        query = initial()
        query["public_turn"] = {"request_id": query["turn_id"], "conversation_id": str(context.conversation_id)}
        first = await graph.ainvoke(query, config, context=context)
        result = public_state(first)["inventory_query"]
        assert result["items"][0]["id"] == owned_item["id"]
        assert result["items"][0]["is_estimated"] is True
        assert first["requests"][query["turn_id"]]["state"]["inventory_query"] == result
        assert first["messages"][-1].content == "Here’s what’s currently in your fridge."
        public_reply = next(iter(first["history_outbox"].values()))["content"]
        assert "Milk — estimated 1.5 L; Fridge (expiry: 2026-10-05)" in public_reply
        assert owned_item["id"] not in public_reply
        second = await graph.ainvoke({"turn_id": str(uuid4()), "request_fingerprint": "report",
            "messages": [HumanMessage(content="Generate an inventory report")], "items": [], "context_next": "prepare_context"}, config, context=context)
        assert "inventory_query" not in public_state(second)
        assert second["messages"][-1].content.startswith("Here’s your report.")
        assert second["requests"][query["turn_id"]]["state"]["inventory_query"] == result
    asyncio.run(scenario())


def test_clients_without_card_capability_keep_the_inventory_text_answer(monkeypatch):
    from test_agent_inventory_results import stock
    from app.agents.workflow import public_state
    setup_services(monkeypatch)
    item = stock()
    @tool
    async def list_inventory() -> str:
        """Read stock."""
        return json.dumps({"ok": True, "items": [item], "total": 1})
    class LegacyModel(ScriptModel):
        async def ainvoke(self, messages, **kwargs):
            if "agent_internal" in kwargs.get("config", {}).get("tags", []):
                assert "present_inventory_results" not in messages[0].content
            return await super().ainvoke(messages, **kwargs)
    async def scenario():
        graph = build_agent_graph(LegacyModel([
            AIMessage(content="", tool_calls=[{"name": "list_inventory", "args": {}, "id": "read", "type": "tool_call"}]),
            AIMessage(content="Your fridge contains 2 L of milk.")], intents=[intake()]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[list_inventory])
        result = await graph.ainvoke(initial(), {"configurable": {"thread_id": "legacy-client"}}, context=AgentContext(uuid4(), None, uuid4()))
        assert "inventory_query" not in public_state(result)
        assert result["inventory_reads"] == {}
        assert result["messages"][-1].content == "Your fridge contains 2 L of milk."
    asyncio.run(scenario())


def test_mixed_queries_and_proposal_never_execute(monkeypatch):
    setup_services(monkeypatch)
    @tool
    async def forbidden() -> str:
        """Must not run in a mixed proposal response."""
        raise AssertionError("Executed mixed tool")
    message = call([draft("x")])
    message.tool_calls.append({"name": "forbidden", "args": {}, "id": "f", "type": "tool_call"})
    async def scenario():
        graph = build_agent_graph(ScriptModel([message, AIMessage(content="Please clarify")], intents=[intake([draft("x")])]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[forbidden])
        result = await graph.ainvoke(initial(), {"configurable": {"thread_id": "mixed"}}, context=AgentContext(uuid4(), None, uuid4()))
        assert result["items"][0]["status"] == "NEEDS_INPUT"
    asyncio.run(scenario())


def test_memory_save_survives_cancelled_stock_action(monkeypatch):
    from app.agents import workflow
    from app.agents.memory import MemoryService
    from app.agents.tools import save_user_memory
    setup_services(monkeypatch)
    original_node = workflow.ToolNode
    monkeypatch.setattr(workflow, "ToolNode", lambda tools, **kwargs: original_node(tools, handle_tool_errors=False))
    async def prepare(session, user, draft, memory, as_of):
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": True, "memory_snapshots": []}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    async def scenario():
        user, conv = uuid4(), uuid4()
        quote = "Remember that I prefer short answers"
        memory_call = AIMessage(content="", tool_calls=[{"name": "save_user_memory", "id": "memory", "type": "tool_call", "args": {
            "category": "USAGE_PREFERENCE", "content": "short answers", "conditions": {}, "authorization_quote": quote}}])
        store = InMemoryStore()
        graph = build_agent_graph(ScriptModel([memory_call, call([draft("estimate")])], intents=[intake([draft("estimate")])]), checkpointer=InMemorySaver(), store=store, session_factory=fake_session, tools=[save_user_memory])
        config = {"configurable": {"thread_id": "save-cancel"}}
        context = AgentContext(user, None, conv, user_message=quote)
        await graph.ainvoke(initial(), config, context=context)
        state = await graph.aget_state(config)
        item, intr = state.values["items"][0], state.tasks[0].interrupts[0]
        result = await graph.ainvoke(Command(resume={intr.id: {"conversation_id": str(conv), "interrupt_id": intr.id,
            "request_id": str(uuid4()), "responses": [{"item_id": item["item_id"], "proposal_id": item["proposal_id"], "decision": "cancel"}]}}), config, context=context)
        assert result["items"][0]["status"] == "CANCELLED"
        assert len(await MemoryService(store, user).search_memories()) == 1
    asyncio.run(scenario())


def test_generic_confirmation_does_not_authorize_memory_save():
    from app.agents.tools import _require_memory_instruction
    import pytest
    runtime = SimpleNamespace(context=AgentContext(uuid4(), None, user_message="yes"))
    with pytest.raises(ValueError):
        _require_memory_instruction(runtime, "yes")


def test_tool_schemas_hide_injected_runtime_and_keep_strict_public_fields():
    from app.agents.tools import AGENT_TOOLS, save_user_memory
    from pydantic import ValidationError
    import pytest
    for tool in AGENT_TOOLS:
        assert "runtime" not in tool.tool_call_schema.model_json_schema().get("properties", {})
    with pytest.raises(ValidationError):
        save_user_memory.args_schema.model_validate({"runtime": object(), "category": "USAGE_PREFERENCE",
            "content": "short", "conditions": {}, "user_id": str(uuid4())})


@pytest.mark.ci
def test_prose_purchase_stays_pending_and_resume_preserves_item(monkeypatch):
    from app.agents import workflow
    setup_services(monkeypatch)
    stock = {"item_key": "tomatoes", "original_text": "I just bought 2 kg of tomatoes",
             "action": "CREATE_STOCK", "item_query": "tomatoes", "quantity_value": "2", "quantity_unit": "kg"}
    completed = {**stock, "new_space": {"name": "fridge", "type": "FRIDGE"}, "new_space_source_text": "Put them in the fridge"}
    writes = []
    async def prepare(session, user, draft, memory, as_of, **kwargs):
        if not draft.new_space:
            raise agent_actions.PreparationError("SPACE_REQUIRED", "Select a space")
        agent_actions.validate_new_space_source(draft, kwargs["source_texts"])
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": False, "memory_snapshots": []}
    async def execute(*args, **kwargs):
        assert kwargs["approved"] is False
        writes.append(args[5]["draft"])
        return {"inventory": {"confirmed_current_amount": "2.000"}}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    async def scenario():
        model = ScriptModel([*[AIMessage(content="I can add tomatoes. Please confirm the category and location.") for _ in range(3)], call([completed])], intents=[intake([stock])])
        graph = build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        config = {"configurable": {"thread_id": "prose-purchase"}}
        context = AgentContext(uuid4(), None, uuid4())
        result = await graph.ainvoke({**initial(), "messages": [HumanMessage(content=stock["original_text"])]}, config, context=context)
        item = result["items"][0]
        assert workflow.public_state(result)["status"] == "WAITING_INPUT"
        assert item["error"]["code"] == "SPACE_REQUIRED" and not writes
        assert item["question"] == "Where would you like to store tomatoes?"
        assert item["draft"]["quantity_value"] == "2"
        snapshot = await graph.aget_state(config)
        assert snapshot.next == ("await_user",)
        assert workflow.public_item(snapshot.values["items"][0])["display"]["question"] == item["question"]
        response = {"conversation_id": str(context.conversation_id), "request_id": str(uuid4()),
            "interrupt_id": snapshot.tasks[0].interrupts[0].id, "responses": [{"item_id": item["item_id"],
                "proposal_id": item["proposal_id"], "decision": "answer", "message": "Put them in the fridge"}]}
        result = await graph.ainvoke(Command(resume=response), config, context=context)
        assert result["items"][0]["item_id"] == item["item_id"]
        assert result["items"][0]["status"] == "SUCCEEDED" and len(writes) == 1
    asyncio.run(scenario())


def test_invalid_intake_is_bounded_and_recoverable(monkeypatch):
    import pytest
    setup_services(monkeypatch)
    async def scenario():
        model = ScriptModel([], intents=[AIMessage(content="I can add it") for _ in range(3)])
        graph = build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        config = {"configurable": {"thread_id": "bad-intake"}}
        with pytest.raises(ValueError, match="Unable to identify"):
            await graph.ainvoke(initial(), config, context=AgentContext(uuid4(), None))
        snapshot = await graph.aget_state(config)
        assert snapshot.next == ("prepare_context",) and not snapshot.values["items"]
    asyncio.run(scenario())


@pytest.mark.ci
def test_query_cannot_propose_stock_and_bad_proposals_are_bounded(monkeypatch):
    import pytest
    setup_services(monkeypatch)
    async def scenario():
        model = ScriptModel([call([draft("x")]) for _ in range(3)], intents=[intake()])
        graph = build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        config = {"configurable": {"thread_id": "query-no-write"}}
        with pytest.raises(ValueError, match="valid inventory proposal"):
            await graph.ainvoke(initial(), config, context=AgentContext(uuid4(), None))
        assert not (await graph.aget_state(config)).values["items"]
    asyncio.run(scenario())


def test_new_space_requires_actual_task_text():
    import pytest
    from app.schemas.agent_actions import ActionDraft
    action = ActionDraft(item_key="t", original_text="tomatoes", action="CREATE_STOCK",
        new_space={"name": "Fridge", "type": "FRIDGE"}, new_space_source_text="Put them in the Fridge")
    for source in [[], ["I bought tomatoes"], ["Image attachment"]]:
        with pytest.raises(agent_actions.PreparationError):
            agent_actions.validate_new_space_source(action, source)
    agent_actions.validate_new_space_source(action, ["Put them in the Fridge"])
    with pytest.raises(agent_actions.PreparationError):
        agent_actions.validate_new_space_source(action.model_copy(update={"new_space_source_text": "I bought tomatoes"}), ["I bought tomatoes"])


def test_omitted_intake_item_survives_other_item_success(monkeypatch):
    from app.agents import workflow
    setup_services(monkeypatch)
    async def prepare(session, user, action, memory, as_of):
        if action.item_key == "missing":
            raise agent_actions.PreparationError("INITIAL_QUANTITY_REQUIRED", "How much?")
        return {"draft": action.model_dump(mode="json"), "requires_confirmation": False, "memory_snapshots": []}
    writes = []
    async def execute(*args, **kwargs):
        writes.append(args[5]["draft"]["item_key"])
        return {"inventory": {"id": "saved"}}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    async def scenario():
        graph = build_agent_graph(ScriptModel([call([draft("ready")])], intents=[intake([draft("ready"), draft("missing")])]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        result = await graph.ainvoke(initial(), {"configurable": {"thread_id": "omitted"}}, context=AgentContext(uuid4(), None, uuid4()))
        assert [i["status"] for i in result["items"]] == ["SUCCEEDED", "NEEDS_INPUT"]
        assert writes == ["ready"]
    asyncio.run(scenario())


def test_malformed_tool_json_can_be_corrected(monkeypatch):
    setup_services(monkeypatch)
    malformed = AIMessage(content="", invalid_tool_calls=[{"name": "record_turn_intent", "args": "{", "id": "bad-json", "error": "invalid JSON"}])
    async def scenario():
        graph = build_agent_graph(ScriptModel([AIMessage(content="Nothing is in your inventory.")], intents=[malformed, intake()]),
            checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        result = await graph.ainvoke(initial(), {"configurable": {"thread_id": "malformed"}}, context=AgentContext(uuid4(), None))
        assert not result["items"] and result["route"] == "END"
    asyncio.run(scenario())


def test_outcome_uses_estimated_balance_and_never_reasks_confirmation():
    from app.agents.intake import outcome_text
    item = {"status": "SUCCEEDED", "draft": {"action": "CONSUME", "item_query": "Rice"},
        "result": {"inventory": {"display_amount": "1.200", "display_unit": "kg", "is_estimated": True,
                                 "confirmed_current_amount": "2.500"}}}
    assert outcome_text([item], "en") == "Updated Rice. Remaining: about 1.2 kg."
