"""Database-free CONSUME contract and exact rounding checks."""
from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.core.quantity import QuantityError
from app.db.models import InventoryItem
from app.schemas.inventory_operations import InventoryOperationCreate
from app.services.inventory_quantities import calculate_consumption


def consumption(**changes):
    return dict(expected_version=1, operation_type="CONSUME", quantity_kind="AMOUNT",
                quantity_value="500", quantity_unit="g") | changes


def stock(amount="2.5", unit="kg"):
    return InventoryItem(confirmed_current_amount=Decimal(amount), confirmed_current_unit=unit)


@pytest.mark.parametrize("balance,unit,kind,value,input_unit,applied,remaining,method,rounded", [
    ("2.5", "kg", "AMOUNT", "500", " G ", ".5", "2", "CONVERTED", False),
    ("2500", "g", "AMOUNT", ".5", "kg", "500", "2000", "CONVERTED", False),
    ("2.5", "l", "AMOUNT", "250", "ml", ".25", "2.25", "CONVERTED", False),
    ("2500", "ml", "AMOUNT", "1", "l", "1000", "1500", "CONVERTED", False),
    ("2", "piece", "AMOUNT", "1", "PIECE", "1", "1", "EXACT", False),
    ("1", "kg", "FRACTION", "1/3", "remaining", ".333", ".667", "EXACT", True),
    ("1", "kg", "FRACTION", "2/3", "remaining", ".667", ".333", "EXACT", True),
    ("1", "kg", "FRACTION", "2/4", "remaining", ".5", ".5", "EXACT", False),
    (".001", "kg", "FRACTION", "1/1", "remaining", ".001", "0", "EXACT", False),
    ("999999999.999", "kg", "AMOUNT", "999999999.999", "kg", "999999999.999", "0", "EXACT", False),
    (".002", "kg", "FRACTION", "499999999999999/1000000000000000", "remaining", ".001", ".001", "EXACT", True),
])
def test_consumption_calculation(balance, unit, kind, value, input_unit, applied, remaining, method, rounded):
    item = stock(balance, unit)
    result = calculate_consumption(item, kind, value, input_unit)
    assert result.applied_change_amount == Decimal(applied)
    assert result.amount == Decimal(remaining) and result.unit == unit
    assert result.calculation_method == method and result.rounded is rounded
    assert result.affects_state == "CONFIRMED"
    assert item.confirmed_current_amount == Decimal(balance)


@pytest.mark.parametrize("balance,kind,value,unit,code", [
    (".001", "AMOUNT", "1.001", "g", "INSUFFICIENT_QUANTITY"),
    ("1", "AMOUNT", "2", "kg", "INSUFFICIENT_QUANTITY"),
    (".001", "FRACTION", "1/2", "remaining", "QUANTITY_PRECISION_UNSUPPORTED"),
    (".001", "AMOUNT", ".999", "g", "QUANTITY_PRECISION_UNSUPPORTED"),
    ("1", "AMOUNT", ".1", "g", "QUANTITY_TOO_SMALL"),
    (".001", "FRACTION", "1/3", "remaining", "QUANTITY_TOO_SMALL"),
    ("1", "AMOUNT", "1", "ml", "UNIT_NOT_CONVERTIBLE"),
    ("0", "FRACTION", "1/1", "remaining", "QUANTITY_TOO_SMALL"),
    ("0", "AMOUNT", "1", "g", "INSUFFICIENT_QUANTITY"),
])
def test_consumption_rejects_without_rounding_away_errors(balance, kind, value, unit, code):
    with pytest.raises(QuantityError) as error:
        calculate_consumption(stock(balance), kind, value, unit)
    assert error.value.code == code


def test_estimated_zero_is_used_instead_of_confirmed_balance():
    item = stock()
    item.estimated_current_amount = Decimal("0")
    item.estimated_current_unit = "kg"
    with pytest.raises(QuantityError, match="exceeds"):
        calculate_consumption(item, "AMOUNT", "1", "g")


@pytest.mark.parametrize("value", ["0/1", "1/0", "2/1", "-1/2", "1.0/2", "1 /2", "1/2 ", "1e1/20", "1", "1/" + "9" * 31])
def test_fraction_contract_rejects_invalid_expressions(value):
    with pytest.raises(ValidationError):
        InventoryOperationCreate(**consumption(quantity_kind="FRACTION", quantity_value=value, quantity_unit="remaining"))


@pytest.mark.parametrize("changes", [
    {"operation_type": "ADD", "quantity_kind": "FRACTION", "quantity_value": "1/2", "quantity_unit": "remaining"},
    {"quantity_kind": "FRACTION", "quantity_value": "1/2", "quantity_unit": "kg"},
    {"quantity_kind": "FRACTION", "quantity_value": "1/2", "quantity_unit": "Remaining"},
    {"quantity_value": "1.0001"}, {"quantity_value": "0"}, {"quantity_value": "1e2"},
    {"expected_version": True}, {"quantity_value": 1}, {"operation_type": "REMOVE"},
])
def test_consumption_contract_rejects_invalid_combinations(changes):
    with pytest.raises(ValidationError):
        InventoryOperationCreate(**consumption(**changes))


def test_fraction_contract_preserves_literal_and_trims_unit():
    result = InventoryOperationCreate(**consumption(quantity_kind="FRACTION", quantity_value="02/04", quantity_unit=" remaining "))
    assert result.quantity_value == "02/04" and result.quantity_unit == "remaining"
