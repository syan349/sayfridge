"""Ordinary chat supplements preserve facts, cancellation and suspended work."""
import asyncio
from uuid import uuid4
import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
from app.agents import workflow, continuation
from app.agents.continuation import Continuation, ContinuationAnswer
from app.agents.state import AgentContext
from app.services.agent_actions import PreparationError
from test_agent_workflow import ScriptModel, call, intake, initial, fake_session, setup_services

pytestmark = pytest.mark.ci


@pytest.mark.parametrize("decision", ["answer", "cancel", "query"])
def test_chat_supplement_and_query_do_not_lose_or_recreate_work(monkeypatch, decision):
    setup_services(monkeypatch)
    proposed = {"item_key": "apple", "original_text": "add 2 apples", "action": "CREATE_STOCK",
                "item_query": "apple", "quantity_value": "2", "quantity_unit": "个"}
    revised = {"item_key": "apple", "original_text": "put in fridge", "action": "CREATE_STOCK",
               "storage_space_id": str(uuid4())}
    saved = []
    async def prepare(session, user, draft, memory, as_of):
        if not draft.storage_space_id:
            raise PreparationError("SPACE_REQUIRED", "Where?")
        assert draft.quantity_value == "2" and draft.quantity_unit == "个"
        return {"draft": draft.model_dump(mode="json"), "requires_confirmation": False}
    async def execute(*args, **kwargs):
        saved.append(args[4])
        return {"inventory": {"id": "apple"}}
    async def interpret(model, items, message, **kwargs):
        if decision == "query":
            return Continuation(mode="QUERY")
        return Continuation(mode="CONTINUE", responses=[ContinuationAnswer(
            item_id=items[0]["item_id"], decision=decision, message=message, evidence=message)])
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    monkeypatch.setattr(continuation, "interpret_continuation", interpret)
    async def scenario():
        model = ScriptModel([call([proposed]), AIMessage(content="Inventory answer") if decision == "query" else call([revised])],
                            intents=[intake([proposed]), intake(kind="QUERY")])
        from app.agents.context_budget import Budget
        # This test must exercise compaction regardless of production defaults.
        model.budget = Budget(trigger=80000, target=40000, limit=160000, output=1000)
        graph = workflow.build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(),
                                           session_factory=fake_session, tools=[])
        config = {"configurable": {"thread_id": str(uuid4())}, "recursion_limit": 128}
        context = AgentContext(uuid4(), None, uuid4())
        start = initial()
        history = []
        for n in range(20):
            history.extend([HumanMessage(content=f"old topic {n}: " + "x" * 3500), AIMessage(content="old answer")])
        start["messages"] = [*history, *start["messages"]]
        await graph.ainvoke(start, config, context=context)
        before = await graph.aget_state(config)
        old = before.values["items"][0]
        assert before.values["context_compaction"]["after"] < before.values["context_compaction"]["before"]
        intr = before.tasks[0].interrupts[0]
        rid = str(uuid4())
        result = await graph.ainvoke(Command(resume={intr.id: {"chat_message": "put in fridge",
            "request_id": rid, "fingerprint": "digest"}}), config, context=context)
        item = result["items"][0]
        assert item["item_id"] == old["item_id"]
        assert result["chat_requests"][rid] == "digest"
        assert item["status"] == {"answer": "SUCCEEDED", "cancel": "CANCELLED", "query": "NEEDS_INPUT"}[decision]
        assert len(saved) == (1 if decision == "answer" else 0)
        if decision == "query":
            assert (await graph.aget_state(config)).tasks[0].interrupts
            assert item["draft"]["quantity_value"] == "2"
    asyncio.run(scenario())
