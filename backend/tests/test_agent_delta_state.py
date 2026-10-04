"""Replay-safe accumulation and stable archived-image updates."""
import asyncio
from uuid import uuid4

import pytest
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore

from app.agents.messages import human_message
from app.agents.state import AgentContext, merge_images, merge_records
from app.agents.workflow import build_agent_graph
from agent_image_support import image_input
from test_agent_workflow import ScriptModel, intake, setup_services, fake_session

pytestmark = pytest.mark.ci


def test_record_and_image_reducers_are_batch_invariant_and_do_not_mutate():
    original = {"old": {"answer": "first"}}
    updates = [{"a": {"answer": "one"}}, {"a": {"answer": "corrected"}, "b": {"answer": "two"}}]
    expected = merge_records(original, updates)
    assert merge_records(merge_records(original, updates[:1]), updates[1:]) == expected
    assert merge_records(expected, updates) == expected
    assert original == {"old": {"answer": "first"}}
    a = human_message("photo", [image_input()], "a")
    b = human_message("another", [image_input("Bread")], "b")
    corrected = a.model_copy(update={"additional_kwargs": {**a.additional_kwargs, "context_position": 1}})
    assert merge_images([a], [[b], [corrected]]) == [corrected, b]
    assert merge_images(merge_images([a], [[b]]), [[corrected]]) == [corrected, b]
    assert "context_position" not in a.additional_kwargs


def test_one_image_then_100_text_turns_do_not_rewrite_image_collection(monkeypatch):
    setup_services(monkeypatch)
    async def run():
        saver = InMemorySaver()
        model = ScriptModel([], intents=[intake() for _ in range(101)])
        graph = build_agent_graph(model, checkpointer=saver, store=InMemoryStore(), session_factory=fake_session, tools=[])
        cfg = {"configurable": {"thread_id": "image-retention"}, "recursion_limit": 128}
        ctx = AgentContext(uuid4(), None, uuid4())
        picture = image_input()
        for n in range(101):
            rid = str(uuid4())
            state = await graph.ainvoke({"messages": [human_message("visual question" if n == 0 else "Hi", [picture] if n == 0 else [], rid)],
                "turn_id": rid, "request_fingerprint": str(n), "chat_requests": {rid: str(n)},
                "items": [], "context_next": "prepare_context"}, cfg, context=ctx)
        writes = [r for group in saver.writes.values() for r in group.values() if r[1] == "image_messages"]
        assert len(writes) == 1
        assert len(state["image_messages"]) == 1
        assert len(state["requests"]) == len(state["chat_requests"]) == 101
        assert "image_url" in str(state["image_messages"][0].content)
    asyncio.run(run())
