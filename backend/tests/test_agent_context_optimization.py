"""Production-size budgets, read-only views and bounded cumulative summaries."""
import asyncio
import json

import pytest
import tiktoken
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage

from app.agents.context_budget import Budget, BudgetModel, ContextBudgetError, rolling_summary, summary_data
from app.agents.context_views import clean_tool_results, message_groups, protected_message_ids

pytestmark = pytest.mark.ci
ENCODING = tiktoken.get_encoding("o200k_base")


class TokenModel:
    def __init__(self, replies=()):
        self.replies = iter(replies)
        self.calls = []
        self.options = {}

    def get_num_tokens(self, text):
        return len(ENCODING.encode(text))

    def get_num_tokens_from_messages(self, messages):
        return sum(4 + self.get_num_tokens(json.dumps({"role": m.type, "content": m.content,
            "calls": getattr(m, "tool_calls", [])}, ensure_ascii=False)) for m in messages)

    def bind(self, **kwargs):
        self.options = kwargs
        return self

    def bind_tools(self, tools, **kwargs):
        return self

    async def ainvoke(self, messages, **kwargs):
        self.calls.append(messages)
        return next(self.replies, AIMessage(content="Stable facts. No outstanding authorization."))


def test_default_budget_and_schemas_use_tokens_not_utf8_bytes():
    raw = TokenModel()
    guarded = BudgetModel(raw)
    schemas = [{"name": "lookup", "description": "查询冷藏室中的酸奶，数量必须精确。" * 100}]
    assert guarded.schema_tokens(schemas) == raw.get_num_tokens(json.dumps(schemas, ensure_ascii=False))
    assert guarded.schema_tokens(schemas) < len(json.dumps(schemas, ensure_ascii=False).encode())
    assert (guarded.budget.limit, guarded.budget.trigger, guarded.budget.target) == (150000, 120000, 50000)
    # A smaller actual model window cannot be ignored by a larger application cap.
    assert Budget(trigger=15000, target=14000, model_limit=20000).safe_limit == 20000
    with pytest.raises(ValueError):
        Budget(model_limit=30000)


def test_short_chat_has_no_summary_call():
    async def run():
        raw = TokenModel()
        assert await rolling_summary(BudgetModel(raw), [HumanMessage(content="Add two yoghurts", id="now")]) is None
        assert not raw.calls
    asyncio.run(run())


def test_long_context_has_bounded_summary_recent_history_and_safe_total():
    async def run():
        raw = TokenModel([AIMessage(content="Corrected name: Mei. Rice was saved, milk is awaiting confirmation.")])
        model = BudgetModel(raw, Budget(summary_output=20000))
        # Deliberately use varied words: repeated characters tokenize unrealistically cheaply.
        messages = []
        for n in range(48):
            messages.extend([HumanMessage(id=f"u{n}", content=f"topic {n}: " + "rice milk freezer quantity correction. " * 180),
                             AIMessage(id=f"a{n}", content="Acknowledged historical task, no new approval. " * 80)])
        envelope = [SystemMessage(content="Fixed rules and tool descriptions. " * 1100)]
        info = await rolling_summary(model, messages, envelope=envelope)
        assert info and info["summary_tokens"] <= 10000 and info["recent_tokens"] <= 10000
        assert info["after"] <= 50000 and info["after"] < info["before"]
        assert messages[-2].id not in info["remove_ids"]
        assert raw.options == {"max_tokens": 20000}
        print("COMPACTION_EVIDENCE " + json.dumps({k: v for k, v in info.items() if k in {
            "before", "after", "summary_tokens", "recent_tokens", "input_tokens", "output_reserve", "safety_margin"}}))
    asyncio.run(run())


@pytest.mark.parametrize("repair_succeeds", [True, False])
def test_overlong_summary_is_repaired_once_without_changing_originals(repair_succeeds):
    async def run():
        too_long = AIMessage(content="unnecessary description " * 120)
        raw = TokenModel([too_long, AIMessage(content="Rice is pending.") if repair_succeeds else too_long])
        budget = Budget(trigger=6000, target=4000, limit=20000, output=1000, margin=1024,
                        recent=400, summary_target=40, summary_limit=80)
        model = BudgetModel(raw, budget)
        messages = [HumanMessage(id=str(n), content="old rice quantity and milk location. " * 150) for n in range(7)]
        before = [m.model_dump() for m in messages]
        info = await rolling_summary(model, messages)
        assert bool(info) == repair_succeeds and len(raw.calls) == 2
        assert before == [m.model_dump() for m in messages]
        assert raw.options["max_tokens"] == 80
    asyncio.run(run())


def read_group(rows, name="list_inventory"):
    call = AIMessage(id="call", content="", tool_calls=[{"name": name, "id": "read", "args": {"q": "milk"}, "type": "tool_call"}])
    reply = ToolMessage(id="reply", tool_call_id="read", content=json.dumps({"ok": True, "total": 100,
        "page": 1, "page_size": 100, "items": rows}))
    return [call, reply]


def test_tool_excerpt_keeps_required_complete_rows_and_marks_omissions():
    rows = [{"id": f"item-{n}", "name": "Milk", "confirmed_current_amount": "2.000", "confirmed_current_unit": "bottle",
             "notes": "some historical context " * 12} for n in range(100)]
    messages = read_group(rows)
    original = messages[1].content
    cleaned = clean_tool_results(messages, TokenModel().get_num_tokens, limit=500, priority_ids={"item-95"})
    data = json.loads(cleaned[1].content)
    assert data["total"] == 100 and data["page"] == 1
    assert data["context_excerpt"]["incomplete"] and data["context_excerpt"]["omitted_rows"] > 0
    assert rows[95] in data["items"]
    assert TokenModel().get_num_tokens(cleaned[1].content) <= 500
    assert messages[1].content == original and cleaned[0] is messages[0]


def test_protected_evidence_errors_and_incomplete_calls_are_never_truncated():
    model = TokenModel()
    group = read_group([{"id": "one", "notes": "a lot of evidence " * 300}])
    protected = protected_message_ids([HumanMessage(id="pending:one", content="user evidence"), *group], {"pending"})
    assert clean_tool_results(group, model.get_num_tokens, limit=50, protected_ids=protected) == group
    failure = group[1].model_copy(update={"content": json.dumps({"ok": False, "details": "failed " * 300})})
    assert clean_tool_results([group[0], failure], model.get_num_tokens, limit=50)[1] is failure
    assert message_groups([group[0]])[0][1] is True


def test_split_large_old_turn_never_leaves_an_orphan_tool_result():
    async def run():
        model = BudgetModel(TokenModel(), Budget(trigger=6000, target=4000, limit=24000, output=1000,
                                                 margin=1024, recent=600))
        messages = [HumanMessage(id="old-user", content="Check all batches. " * 500)]
        for n in range(7):
            group = read_group([{"id": str(n), "notes": "historic read " * 200}])
            group[0].id, group[1].id = f"call-{n}", f"result-{n}"
            group[0].tool_calls[0]["id"] = str(n)
            group[1].tool_call_id = str(n)
            messages.extend(group)
        messages.extend([AIMessage(id="old-answer", content="Found the batches."), HumanMessage(id="current", content="What next?")])
        info = await rolling_summary(model, messages)
        assert info
        remaining = [m for m in messages if m.id not in info["remove_ids"]]
        assert not any(incomplete for _, incomplete in message_groups(remaining))
        assert info["recent_tokens"] <= 600
    asyncio.run(run())


def test_summary_data_never_contains_pixels_and_preserves_image_uncertainty():
    message = HumanMessage(content=[{"type": "image_url", "image_url": {"url": "data:image/png;base64,PRIVATE"}}],
        additional_kwargs={"user_text": "Quantity on label is unclear", "images": [{"image_id": "label", "mime_type": "image/png"}]})
    assert "PRIVATE" not in json.dumps(summary_data(message))
    assert "unclear" in summary_data(message)["content"]


def test_bound_models_keep_tokenizer_and_summary_timeout_and_reject_before_network():
    async def run():
        raw = TokenModel()
        model = BudgetModel(raw)
        model.summary_timeout_seconds = 12
        bound = model.bind_tools([{"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}])
        assert bound.summary_timeout_seconds == 12 and bound.text_counter == model.text_counter
        with pytest.raises(ContextBudgetError):
            await bound.ainvoke([HumanMessage(content="huge incoming user evidence " * 40000)])
        assert not raw.calls
    asyncio.run(run())


def test_twenty_item_workflow_fits_production_budget_without_frontend_changes(monkeypatch):
    from uuid import uuid4
    from langgraph.checkpoint.memory import InMemorySaver
    from langgraph.store.memory import InMemoryStore
    from app.agents import workflow
    from app.agents.state import AgentContext
    from test_agent_workflow import ScriptModel, call, intake, setup_services, fake_session, draft
    setup_services(monkeypatch)
    executed = []
    async def prepare(session, user, action, memory, as_of, **kwargs):
        return {"draft": action.model_dump(mode="json"), "requires_confirmation": False, "memory_snapshots": []}
    async def execute(session, user, conversation, turn, proposal, preview, memory, **kwargs):
        executed.append(preview["draft"]["item_key"])
        return {"inventory": {"id": preview["draft"]["item_key"]}}
    monkeypatch.setattr(workflow, "prepare_action", prepare)
    monkeypatch.setattr(workflow, "execute_action", execute)
    async def run():
        actions = [draft(f"stock-{n}") for n in range(20)]
        meter = TokenModel()
        model = BudgetModel(ScriptModel([call(actions)], intents=[intake(actions)]), Budget(),
                            counter=meter.get_num_tokens_from_messages, text_counter=meter.get_num_tokens)
        graph = workflow.build_agent_graph(model, checkpointer=InMemorySaver(), store=InMemoryStore(), session_factory=fake_session, tools=[])
        rid = str(uuid4())
        state = await graph.ainvoke({"messages": [HumanMessage(id=rid, content="Use 1 kg of each of the twenty listed stock items")],
            "turn_id": rid, "request_fingerprint": "twenty", "items": [], "context_next": "prepare_context"},
            {"configurable": {"thread_id": "twenty"}, "recursion_limit": 128}, context=AgentContext(uuid4(), None, uuid4()))
        assert len(executed) == 20 and len(set(executed)) == 20
        assert all(item["status"] == "SUCCEEDED" for item in state["items"])
    asyncio.run(run())
