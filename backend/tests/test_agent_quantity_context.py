"""Acceptance cases for request-unit balances, whole counts and bounded prompts."""
from decimal import Decimal
import asyncio
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.store.memory import InMemoryStore

from app.db.models import InventoryItem
from app.core.quantity import QuantityError
from app.services.inventory_quantities import calculate_change
from app.agents.memory import MemoryService
from app.agents.context_budget import Budget, BudgetModel, ContextBudgetError, compact

pytestmark = pytest.mark.ci


def stock(amount, unit):
    return InventoryItem(confirmed_current_amount=Decimal(amount), confirmed_current_unit=unit)


def apply(item, result):
    item.estimated_current_amount = result.amount
    item.estimated_current_unit = result.unit


def test_half_rice_and_odd_count_supplement():
    result = calculate_change(stock("2", "kg"), "CONSUME", "FRACTION", "1/2", "remaining")
    assert (result.amount, result.unit) == (Decimal("1"), "kg")
    with pytest.raises(QuantityError) as exc:
        calculate_change(stock("3", "个"), "CONSUME", "FRACTION", "1/2", "remaining")
    assert exc.value.code == "WHOLE_COUNT_REQUIRED"
    result = calculate_change(stock("3", "个"), "CONSUME", "AMOUNT", "1.5", "个")
    assert result.amount == Decimal("1.5")


def test_unit_switches_preserve_initial_baseline_and_estimation():
    item = stock("20", "个")
    relation = dict(source_amount="1", source_unit="个", target_amount="180", target_unit="g",
                    source="MODEL_KNOWLEDGE", rationale="Typical apple estimate")
    first = calculate_change(item, "CONSUME", "AMOUNT", "200", "g", relationship=relation)
    assert (first.amount, first.unit, first.affects_state) == (Decimal("3400"), "g", "ESTIMATED")
    apply(item, first)
    second = calculate_change(item, "CONSUME", "AMOUNT", "0.2", "kg")
    assert (second.amount, second.unit, second.affects_state) == (Decimal("3.2"), "kg", "ESTIMATED")
    apply(item, second)
    third = calculate_change(item, "CONSUME", "AMOUNT", "1", "个", relationship=relation)
    assert (third.amount, third.unit, third.affects_state) == (Decimal("17"), "个", "ESTIMATED")
    assert item.confirmed_current_amount == Decimal("20")


@pytest.mark.parametrize("consumed,remaining", [("1", "18"), ("0.5", "18.5")])
def test_weight_to_count_is_integer_except_explicit_partial(consumed, remaining):
    relation = dict(source_amount="1", source_unit="个", target_amount="180", target_unit="g")
    result = calculate_change(stock("3400", "g"), "CONSUME", "AMOUNT", consumed, "个", relationship=relation)
    assert result.amount == Decimal(remaining)
    assert result.unit == "个" and result.affects_state == "ESTIMATED"


def test_qualitative_count_estimate_cannot_introduce_fractional_stock():
    from app.services.inventory_quantities import calculate_estimated_change
    result = calculate_estimated_change(stock("20", "个"), "CONSUME", Decimal("1.9"), "个")
    assert result.amount == 18 and result.applied_change_amount == 2
    assert result.affects_state == "ESTIMATED"


def test_fraction_is_finite_precision_without_hidden_balance():
    result = calculate_change(stock("1", "kg"), "CONSUME", "FRACTION", "1/3", "remaining")
    assert (result.amount, result.unit, result.applied_change_amount) == (Decimal(".667"), "kg", Decimal(".333"))
    with pytest.raises(QuantityError) as exc:
        calculate_change(stock(".001", "kg"), "CONSUME", "FRACTION", "1/2", "remaining")
    assert exc.value.code == "QUANTITY_PRECISION_UNSUPPORTED"


def test_memory_inverse_and_source_precedence():
    async def scenario():
        service = MemoryService(InMemoryStore(), uuid4())
        definition = str(uuid4())
        payload = {"item_definition_id": definition, "item_name": "Apple", "relationship": {
            "source_amount": "1", "source_unit": "个", "target_amount": "180", "target_unit": "g",
            "source": "MODEL_KNOWLEDGE", "rationale": "Estimated"}}
        await service.save_conversion(payload)
        await service.save_conversion(payload)
        assert len(await service.search_memories("UNIT_RELATIONSHIP")) == 1
        await service.save_conversion({**payload, "relationship": {**payload["relationship"],
            "source": "USER_INPUT", "target_amount": "200"}})
        found = await service.find_conversion_relationship({"item_definition_id": definition,
            "source_unit": "kg", "target_unit": "个"})
        assert found["status"] == "MATCH"
        assert found["items"][0]["structured_value"]["target_amount"] == "200"
    asyncio.run(scenario())


def test_budget_preserves_complete_recent_groups_and_refuses_oversize():
    budget = Budget(trigger=7000, target=4000, limit=16000, output=1000, margin=1024, model_limit=16000)
    history = []
    for n in range(20):
        history.extend([HumanMessage(content=f"Question {n} " + "x" * 300), AIMessage(content="reply " * 40)])
    history.append(HumanMessage(content="放冷藏室"))
    trimmed, info = compact(history, budget)
    assert info and trimmed[-1].content == "放冷藏室"
    class Recorder:
        calls = 0
        async def ainvoke(self, messages, **kwargs):
            self.calls += 1
            return AIMessage(content="ok")
    async def scenario():
        model = Recorder()
        guarded = BudgetModel(model, budget)
        with pytest.raises(ContextBudgetError):
            await guarded.ainvoke([HumanMessage(content="x" * 20000)])
        assert model.calls == 0
        await guarded.ainvoke(history)
        assert model.calls == 1
    asyncio.run(scenario())


@pytest.mark.parametrize("changes", [{"limit": 275000}, {"target": 90000}, {"model_limit": 10000}])
def test_invalid_budget_cannot_disable_cap(changes):
    with pytest.raises(ValueError):
        Budget(**changes)


def test_opaque_provider_blocks_are_budgeted_without_being_changed():
    original = AIMessage(content=[{"type": "reasoning", "encrypted_content": "opaque"}, {"type": "text", "text": "ok"}])
    class Meter:
        def get_num_tokens_from_messages(self, messages):
            assert all(b["type"] == "text" for m in messages for b in m.content)
            return 3
    model = BudgetModel(Meter())
    assert model.count([original]) >= model.budget.output
    assert original.content[0]["encrypted_content"] == "opaque"


def test_batch_function_blocks_share_one_message_generation_reserve():
    blocks = [{"type": "function_call", "name": "lookup", "arguments": {"query": f"item-{n}"}} for n in range(19)]
    original = AIMessage(content=[{"type": "reasoning", "encrypted_content": "opaque"}, *blocks])
    guarded = BudgetModel(object(), counter=lambda messages: 10)
    assert guarded.count([original]) == ((10 + guarded.budget.output) * 5 + 3) // 4
    assert original.content == [{"type": "reasoning", "encrypted_content": "opaque"}, *blocks]


def test_unknown_meter_stops_before_network_and_preserves_private_errors():
    class Meter:
        def get_num_tokens_from_messages(self, messages):
            raise ValueError("provider private details")
    with pytest.raises(ContextBudgetError) as exc:
        BudgetModel(Meter()).count([HumanMessage(content="hello")])
    assert "private details" not in str(exc.value)
