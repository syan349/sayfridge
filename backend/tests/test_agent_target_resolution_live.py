"""Opt-in real-model lookup decisions against disposable inventory."""
import os
from decimal import Decimal

import pytest
from agent_dialogue_support import Dialogue
from auth_test_support import exercise
from catalog_test_support import seed_definition
from inventory_test_support import (
    inventory_context as inventory_context,  # noqa: PLC0414 - export the pytest fixture
)
from inventory_test_support import seed_inventory
from test_agent_target_resolution_postgres import apple_action, apples, invocation
from test_agent_workflow import call, intake

from app.agents.model import create_agent_model
from app.api.routes import agent as api

pytestmark = [pytest.mark.postgres, pytest.mark.skipif(os.getenv("AGENT_LIVE_MODEL") != "1", reason="Opt in to model API costs")]


class EarlyProposalModel:
    """Reproduce the observed failure, then let the real model recover unaided."""
    def __init__(self, delegate, progress=None):
        self.delegate = delegate
        self.progress = progress if progress is not None else {"internal": 0}

    def __getattr__(self, name):
        return getattr(self.delegate, name)

    def bind_tools(self, *args, **kwargs):
        return EarlyProposalModel(self.delegate.bind_tools(*args, **kwargs), self.progress)

    async def ainvoke(self, messages, **kwargs):
        tags = kwargs.get("config", {}).get("tags", [])
        if "agent_intake" in tags:
            return intake([apple_action()], language="zh")
        if "agent_internal" in tags and self.progress["internal"] < 2:
            self.progress["internal"] += 1
            return invocation("resolve_inventory_targets", queries=["苹果"]) if self.progress["internal"] == 1 else call([apple_action()])
        return await self.delegate.ainvoke(messages, **kwargs)


@pytest.mark.parametrize("early_proposal", [False, True])
def test_real_model_inspects_stock_and_consumes_only_apples(inventory_context, monkeypatch, live_runner, early_proposal):
    c = inventory_context
    target = apples(c)
    juice = seed_definition(c[0], c[3].id, name="Apple juice", normalized_name="apple juice")
    seed_inventory(c, item_definition_id=juice.id)
    async def scenario(client, sessions):
        model = create_agent_model()
        if early_proposal:
            model = EarlyProposalModel(model)
        dialogue = Dialogue(client, c, sessions, model, monkeypatch)
        state = await dialogue.chat(apple_action()["original_text"])
        item = state["items"][0]
        assert item["status"] == "SUCCEEDED", {"status": item["status"], "error": item.get("error")}
        assert item["result"]["inventory"]["id"] == str(target.id)
        assert Decimal(item["result"]["inventory"]["confirmed_current_amount"]) == 2
        assert not any(e["type"] == "action_required" for e in dialogue.events)
        snapshot = await dialogue.graph.aget_state(api._config(c[1].id, dialogue.conversation_id))
        calls = [t for m in snapshot.values["messages"] for t in getattr(m, "tool_calls", [])]
        if early_proposal:
            assert any(t["name"] == "list_inventory" and not t["args"].get("q") for t in calls[2:])
            assert snapshot.values["items"][0]["target_lookup"]["revisions"] >= 1
        print({"early_proposal": early_proposal, "tools": [t["name"] for t in calls],
               "result": item["status"], "remaining": "2", "operations": (await dialogue.counts())[1]})
        assert (await dialogue.counts())[1:] == (1, 1)
    live_runner.run(exercise(c[0], scenario))
