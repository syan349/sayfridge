"""Date precedence, bounded model output, and optional-enrichment failures."""
import asyncio
from datetime import date, datetime, timezone
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app.schemas.inventory import ShelfLifeInput
from app.services import inventory_expiry as expiry

pytestmark = pytest.mark.ci


def test_explicit_dates_and_label_start_dates_never_call_model(monkeypatch):
    async def forbidden(items):
        raise AssertionError("The supplied dates must not be estimated")
    monkeypatch.setattr(expiry, "estimate_shelf_lives", forbidden)
    items = [expiry.ExpiryInput("Yoghurt", "Yoghurt", "FRIDGE", expiry_date=date(2026, 9, 1)),
        expiry.ExpiryInput("Milk", "Milk", "FRIDGE", purchase_date=date(2026, 10, 2),
            shelf_life=ShelfLifeInput(days=7, basis="MANUFACTURE", starts_on="2026-09-28", evidence="made Sep 28; 7 days"))]
    results = asyncio.run(expiry.resolve_expiries(items, date(2026, 10, 2)))
    assert [r.expiry_date for r in results] == [date(2026, 9, 1), date(2026, 10, 5)]
    assert all(r.code is None for r in results)


@pytest.mark.parametrize("basis", ["MANUFACTURE", "OPENING", "EXPLICIT"])
def test_label_life_cannot_start_from_an_invented_purchase_date(basis):
    with pytest.raises(ValidationError):
        ShelfLifeInput(days=7, basis=basis, evidence="7 days")


def test_mixed_batch_uses_one_call_and_keeps_each_failure_separate(monkeypatch):
    calls = []
    async def estimate(items):
        calls.append(items)
        return {"0": 7, "1": -3, "2": True, "3": 36500}
    monkeypatch.setattr(expiry, "estimate_shelf_lives", estimate)
    items = [expiry.ExpiryInput("Yoghurt", "Yoghurt", "FRIDGE", purchase_date=date(2026, 9, 30)),
             expiry.ExpiryInput("Unknown", "Other", "PANTRY"),
             expiry.ExpiryInput("Apple", "Fruit", "FRIDGE"),
             expiry.ExpiryInput("Overflow", "Other", "PANTRY", purchase_date=date(9999, 12, 31))]
    results = asyncio.run(expiry.resolve_expiries(items, date(2026, 10, 2)))
    assert len(calls) == 1 and len(calls[0]) == 4
    assert results[0].expiry_date == date(2026, 10, 7)
    assert all(r.expiry_date is None and r.code == "EXPIRY_ESTIMATION_FAILED" for r in results[1:])
    assert items[1].purchase_date is None


@pytest.mark.parametrize("error", [TimeoutError(), ValueError("private provider details")])
def test_failed_estimation_is_optional_and_does_not_expose_errors(monkeypatch, error):
    async def fail(items):
        raise error
    monkeypatch.setattr(expiry, "estimate_shelf_lives", fail)
    monkeypatch.setattr(expiry, "local_today", lambda: date(2026, 10, 2))
    result = asyncio.run(expiry.resolve_expiries([expiry.ExpiryInput("Milk", "Milk", "FRIDGE")]))[0]
    assert result.expiry_date is None and result.basis_date == date(2026, 10, 2)
    assert "private" not in result.message


def test_model_adapter_rejects_duplicates_and_invalid_types(monkeypatch):
    from app.agents import model
    class FakeModel:
        def bind_tools(self, *args, **kwargs):
            return self
        async def ainvoke(self, messages):
            return SimpleNamespace(tool_calls=[{"name": "estimate_shelf_lives", "args": {"items": [
                {"key": "0", "days": 7}, {"key": "0", "days": 9}, {"key": "1", "days": True},
                {"key": "2", "days": "7"}, {"key": "3", "days": 5}]}}])
    monkeypatch.setattr(model, "create_agent_model", FakeModel)
    monkeypatch.setattr(model, "get_agent_model_settings", lambda: SimpleNamespace(timeout_seconds=10))
    # The autouse fixture isolates live model use; exercise the actual adapter here.
    # Fetch the original callable captured before monkeypatching by this fixture.
    from conftest import REAL_EXPIRY_ESTIMATOR
    assert asyncio.run(REAL_EXPIRY_ESTIMATOR([])) == {"1": None, "2": None, "3": 5}


@pytest.mark.parametrize("hour,day", [(10, 1), (11, 2)])
def test_auckland_calendar_day_uses_zone_boundary(monkeypatch, hour, day):
    class Clock:
        @staticmethod
        def now(zone):
            return datetime(2026, 10, 1, hour, 30, tzinfo=timezone.utc).astimezone(zone)
    monkeypatch.setattr(expiry, "datetime", Clock)
    assert expiry.local_today() == date(2026, 10, day)


def test_as_of_and_purchase_dates_override_server_calendar(monkeypatch):
    def forbidden_today():
        raise AssertionError("Request-local date must be used")
    async def estimate(items):
        return {i["key"]: 1 for i in items}
    monkeypatch.setattr(expiry, "local_today", forbidden_today)
    monkeypatch.setattr(expiry, "estimate_shelf_lives", estimate)
    results = asyncio.run(expiry.resolve_expiries([
        expiry.ExpiryInput("Milk", "Milk", "FRIDGE"),
        expiry.ExpiryInput("Milk", "Milk", "FRIDGE", purchase_date=date(2026, 9, 29))], date(2026, 10, 1)))
    assert [r.expiry_date for r in results] == [date(2026, 10, 2), date(2026, 9, 30)]


def test_model_timeout_cancels_request_and_returns_failure_warning(monkeypatch):
    from app.agents import model
    from conftest import REAL_EXPIRY_ESTIMATOR
    cancelled = []
    class SlowModel:
        def bind_tools(self, *args, **kwargs):
            return self
        async def ainvoke(self, messages):
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.append(True)
    monkeypatch.setattr(model, "create_agent_model", SlowModel)
    monkeypatch.setattr(model, "get_agent_model_settings", lambda: SimpleNamespace(timeout_seconds=0.01))
    monkeypatch.setattr(expiry, "estimate_shelf_lives", REAL_EXPIRY_ESTIMATOR)
    result = asyncio.run(expiry.resolve_expiries([expiry.ExpiryInput("Milk", "Milk", "FRIDGE")]))[0]
    assert result.code == "EXPIRY_ESTIMATION_FAILED" and cancelled == [True]
