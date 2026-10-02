"""Cumulative facts, corrections, complete tool groups and failure safety."""
import asyncio
import json

import pytest
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage, SystemMessage

from app.agents.context_budget import Budget, BudgetModel, ContextBudgetError, rolling_summary, summary_message, size

pytestmark = pytest.mark.ci


class SummaryModel:
    budget = Budget(trigger=9000, target=5000, limit=24000, model_limit=24000, output=1000, margin=1024)
    calls = 0
    def count(self, messages):
        return sum(size(m) for m in messages)
    async def ainvoke(self, messages, **kwargs):
        self.calls += 1
        data = json.loads(messages[-1].content)
        assert kwargs["config"]["tags"] == ["agent_summary"]
        if self.calls > 1:
            assert "peanut allergy" in data["previous_summary"]
        text = data["previous_summary"] + "\n" + "\n".join(m["content"] for m in data["older_messages"])
        name = "Mei" if "correct name is Mei" in text or "name=Mei" in text else "May"
        return AIMessage(content=f"peanut allergy; name={name}; pending rice task needs a target.")


def history(prefix="topic", count=12):
    result = []
    for n in range(count):
        result.extend([HumanMessage(content=f"{prefix} {n}: " + "x" * 900, id=f"{prefix}-{n}"),
                       AIMessage(content="answer", id=f"{prefix}-{n}-reply")])
    return result


def test_three_summaries_merge_previous_facts_and_corrections_without_mutating_input():
    async def scenario():
        model = SummaryModel()
        messages = history("first")
        messages[0].content = "peanut allergy; my name is May. " + "x" * 900
        summary = ""
        for cycle in range(3):
            if cycle:
                messages.extend(history(f"cycle-{cycle}"))
            if cycle == 1:
                messages[len(messages) - 24].content = "The correct name is Mei. " + "x" * 900
            ids = [m.id for m in messages]
            info = await rolling_summary(model, messages, summary=summary)
            assert [m.id for m in messages] == ids
            assert info and info["after"] < info["before"]
            summary = info["summary"]
            messages = [m for m in messages if m.id not in info["remove_ids"]]
            assert messages[-1].content == "answer"
        assert model.calls >= 3 and "name=Mei" in summary and "peanut allergy" in summary
        assert summary_message(summary)[0].content.endswith(summary)
    asyncio.run(scenario())


def test_pending_evidence_and_recent_tool_pairs_are_kept_complete():
    async def scenario():
        model = SummaryModel()
        messages = history()
        messages[0].content = "pending user's exact evidence " + "x" * 900
        messages[-1:] = [AIMessage(content="", id="call", tool_calls=[
            {"name": "lookup", "args": {}, "id": "tool-1", "type": "tool_call"}]),
            ToolMessage(content="current backend balance", tool_call_id="tool-1", id="result")]
        info = await rolling_summary(model, messages, protected_ids={"topic-0"})
        assert info and not {"topic-0", "topic-0-reply", "call", "result"} & set(info["remove_ids"])
        remaining = [m for m in messages if m.id not in info["remove_ids"]]
        assert remaining[-2].tool_calls[0]["id"] == remaining[-1].tool_call_id
    asyncio.run(scenario())


@pytest.mark.parametrize("failure", ["error", "timeout", "empty", "tool"])
def test_summary_failure_preserves_old_summary_and_original_messages(failure):
    class Broken(SummaryModel):
        async def ainvoke(self, messages, **kwargs):
            if failure == "error":
                raise RuntimeError("private provider information")
            if failure == "timeout":
                await asyncio.sleep(1)
            if failure == "tool":
                return AIMessage(content="", tool_calls=[{"name": "execute", "args": {}, "id": "x", "type": "tool_call"}])
            return AIMessage(content="")
    async def scenario():
        messages = history()
        old = [(m.id, m.content) for m in messages]
        assert await rolling_summary(Broken(), messages, summary="previous facts", timeout=0.01) is None
        assert [(m.id, m.content) for m in messages] == old
    asyncio.run(scenario())


def test_single_oversized_turn_is_rejected_before_model_and_budget_never_trims():
    class Recorder(SummaryModel):
        seen = None
        async def ainvoke(self, messages, **kwargs):
            self.seen = messages
            return AIMessage(content="ok")
    async def scenario():
        raw = Recorder()
        model = BudgetModel(raw, raw.budget, counter=raw.count)
        messages = [HumanMessage(content="x" * 30000)]
        with pytest.raises(ContextBudgetError):
            await rolling_summary(model, messages)
        with pytest.raises(ContextBudgetError):
            await model.ainvoke(messages)
        assert raw.seen is None
        smaller = history(count=4)
        await model.ainvoke(smaller)
        assert raw.seen is smaller  # only the explicit graph node can change context
    asyncio.run(scenario())


def test_legacy_excerpt_summary_is_merged_and_images_are_not_sent_as_raw_bytes():
    class Inspect(SummaryModel):
        async def ainvoke(self, messages, **kwargs):
            data = json.loads(messages[-1].content)
            assert "earlier fact" in data["previous_summary"]
            assert "RAW_PIXELS" not in messages[-1].content
            return AIMessage(content="earlier fact and current facts")
    async def scenario():
        from app.agents.context_budget import LEGACY_SUMMARY_PREFIX
        messages = history()
        messages[0] = HumanMessage(id="image", content=[{"type": "image_url", "image_url": {"url": "data:image/png;base64,RAW_PIXELS"}}],
            additional_kwargs={"user_text": "photo instruction", "images": [{"image_id": "photo", "mime_type": "image/png"}]})
        messages.insert(0, SystemMessage(content=LEGACY_SUMMARY_PREFIX + "earlier fact", id="legacy"))
        info = await rolling_summary(Inspect(), messages)
        assert info and "legacy" in info["remove_ids"] and "earlier fact" in info["summary"]
    asyncio.run(scenario())


def test_released_older_evidence_is_marked_before_the_previous_summary():
    class Inspect(SummaryModel):
        async def ainvoke(self, messages, **kwargs):
            data = json.loads(messages[-1].content)
            old = next(m for m in data["older_messages"] if "old correction: name=May" in m["content"])
            assert old["predates_previous_summary"] and old["context_position"] < 20
            assert "name=Mei" in data["previous_summary"]
            return AIMessage(content="name=Mei; peanut allergy remains")
    async def scenario():
        messages = history()
        for n, m in enumerate(messages):
            m.additional_kwargs["context_position"] = n + 1
        messages[0].content = "old correction: name=May " + "x" * 900
        info = await rolling_summary(Inspect(), messages, summary="name=Mei; peanut allergy", summary_position=20)
        assert info and "name=Mei" in info["summary"] and info["position"] >= 20
    asyncio.run(scenario())
