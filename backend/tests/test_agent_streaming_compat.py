"""Start before summary, bounded streaming, comment heartbeats and cancellation."""
import asyncio
from contextlib import AsyncExitStack
from types import SimpleNamespace
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessageChunk

from app.api.routes import agent as api
from app.agents.state import AgentContext

pytestmark = pytest.mark.ci


def test_start_precedes_summary_heartbeats_and_summary_never_becomes_public(monkeypatch):
    monkeypatch.setattr(api, "HEARTBEAT_SECONDS", 0.05)
    class Graph:
        invoked = False
        async def astream(self, *args, **kwargs):
            self.invoked = True
            await asyncio.sleep(0.06)
            for _ in range(20):
                # Stay above Windows' monotonic clock resolution so these model
                # chunks take real time instead of coalescing into one tick.
                await asyncio.sleep(0.02)
                yield "messages", (AIMessageChunk(content="PRIVATE SUMMARY"), {"tags": ["agent_summary"]})
            yield "messages", (AIMessageChunk(content="Public reply"), {"tags": ["agent_final"]})
        async def aget_state(self, config):
            return SimpleNamespace(values={}, tasks=[], next=())
    async def scenario():
        graph = Graph()
        async def connected():
            return False
        request = SimpleNamespace(is_disconnected=connected)
        stack = AsyncExitStack()
        response = api._response(stack, SimpleNamespace(graph=graph), {}, {}, AgentContext(uuid4(), None, uuid4()), request, uuid4())
        iterator = response.body_iterator
        first = await anext(iterator)
        assert '"type": "start"' in first and not graph.invoked
        remaining = [chunk async for chunk in iterator]
        text = "".join(remaining)
        assert ": keep-alive\n\n" in text and "Public reply" in text and "PRIVATE SUMMARY" not in text
        assert text.count(": keep-alive\n\n") >= 5
    asyncio.run(scenario())


def test_disconnect_cancels_waiting_graph_and_releases_lock(monkeypatch):
    monkeypatch.setattr(api, "HEARTBEAT_SECONDS", 0.01)
    closed = []
    class Graph:
        async def astream(self, *args, **kwargs):
            try:
                await asyncio.sleep(10)
                yield "updates", {}
            finally:
                closed.append("graph")
    async def scenario():
        async def disconnected():
            return True
        stack = AsyncExitStack()
        stack.callback(lambda: closed.append("lock"))
        response = api._response(stack, SimpleNamespace(graph=Graph()), {}, {}, AgentContext(uuid4(), None, uuid4()),
            SimpleNamespace(is_disconnected=disconnected), uuid4())
        iterator = response.body_iterator
        await anext(iterator)
        with pytest.raises(asyncio.CancelledError):
            await anext(iterator)
        assert closed == ["graph", "lock"]
    asyncio.run(scenario())
