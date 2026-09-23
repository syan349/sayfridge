"""Database-free checks for quantity precision and operation request contracts."""
from decimal import Decimal

import pytest
from pydantic import TypeAdapter, ValidationError

from app.core.quantity import MAX_QUANTITY, QuantityError
from app.db.models import InventoryItem
from app.schemas.inventory_operations import InventoryOperationCreate, IdempotencyKey
from app.services.inventory_quantities import calculate_addition, prepare_addition


def body(**changes):
    return dict(expected_version=1, operation_type="ADD", quantity_kind="AMOUNT",
                quantity_value="500", quantity_unit="g") | changes


@pytest.mark.parametrize("amount,source,unit,expected,method", [
    ("500", "g", "kg", "0.500", "CONVERTED"),
    ("0.5", "kg", "g", "500.000", "CONVERTED"),
    ("250", "ml", "l", "0.250", "CONVERTED"),
    ("2.25", "l", "ml", "2250.000", "CONVERTED"),
    ("2", "KG", "kg", "2.000", "EXACT"),
    ("2", "each", "each", "2.000", "EXACT"),
])
def test_supported_conversion_and_exact_units(amount, source, unit, expected, method):
    item = InventoryItem(confirmed_current_amount=Decimal("7"), confirmed_current_unit=unit)
    result = calculate_addition(item, Decimal(amount), source)
    assert result.applied_change_amount == Decimal(expected)
    assert result.amount == Decimal("7") + Decimal(expected)
    assert result.calculation_method == method and not result.rounded
    assert item.confirmed_current_amount == Decimal("7")


@pytest.mark.parametrize("estimate", [None, Decimal("0"), Decimal("3")])
def test_rounding_uses_correct_balance_without_mutation(estimate):
    item = InventoryItem(confirmed_current_amount=Decimal("7"), confirmed_current_unit="kg",
                         estimated_current_amount=estimate,
                         estimated_current_unit="kg" if estimate is not None else None)
    before = dict(item.__dict__)
    result = calculate_addition(item, Decimal("0.5"), "g")
    assert result.rounded and result.applied_change_amount == Decimal("0.001")
    assert result.amount == (Decimal("7") if estimate is None else estimate) + Decimal("0.001")
    assert result.affects_state == ("CONFIRMED" if estimate is None else "ESTIMATED")
    assert prepare_addition(item, Decimal("0.5"), "g") == (result.amount, "kg", result.affects_state)
    assert item.__dict__ == before


@pytest.mark.parametrize("value", ["0", "-1", "NaN", "sNaN", "Infinity", "-Infinity", "2.1250"])
def test_parsed_invalid_amounts_rejected(value):
    item = InventoryItem(confirmed_current_amount=Decimal("7"), confirmed_current_unit="kg")
    with pytest.raises(ValueError):
        calculate_addition(item, Decimal(value), "kg")


@pytest.mark.parametrize("value,unit,base,target,code", [
    ("0.499", "g", "7", "kg", "QUANTITY_TOO_SMALL"),
    ("1", "ml", "7", "kg", "UNIT_NOT_CONVERTIBLE"),
    ("1", "piece", "7", "each", "UNIT_NOT_CONVERTIBLE"),
    ("1000000000", "g", "0", "kg", "QUANTITY_OUT_OF_RANGE"),
    ("1000000", "kg", "0", "g", "QUANTITY_OUT_OF_RANGE"),
    ("0.002", "kg", "999999999.998", "kg", "QUANTITY_OUT_OF_RANGE"),
])
def test_calculation_errors_have_stable_codes(value, unit, base, target, code):
    item = InventoryItem(confirmed_current_amount=Decimal(base), confirmed_current_unit=target)
    with pytest.raises(QuantityError) as exc:
        calculate_addition(item, Decimal(value), unit)
    assert exc.value.code == code


def test_maximum_is_inclusive():
    item = InventoryItem(confirmed_current_amount=MAX_QUANTITY-Decimal("0.001"), confirmed_current_unit="kg")
    assert calculate_addition(item, Decimal("0.001"), "kg").amount == MAX_QUANTITY


@pytest.mark.parametrize("changes", [
    {"quantity_value": value} for value in ["2.1250", "1e2", "NaN", "Infinity", "+1", " 2", "2 ", ".5", "2.", "0", "1000000000", 2, None, "0"*33+"1"]
] + [{"expected_version": value} for value in [True, "1", 1.0, 0, 2147483648]] + [
    {"operation_type": "REMOVE"}, {"quantity_kind": "FRACTION"},
    {"input_method": "MANUAL"}, {"affects_state": "CONFIRMED"},
    {"idempotency_key": "in-body"}, {"quantity_unit": " "}, {"quantity_unit": "x"*17},
])
def test_request_rejects_invalid_fields(changes):
    with pytest.raises(ValidationError):
        InventoryOperationCreate(**body(**changes))


def test_request_preserves_expression_trims_unit_and_requires_all_fields():
    data = body(quantity_value="2.0", quantity_unit="   KG   ")
    result = InventoryOperationCreate(**data)
    assert result.quantity_value == "2.0" and result.quantity_unit == "KG"
    assert InventoryOperationCreate(**body(quantity_unit=" "*20+"x"*16+" "*20)).quantity_unit == "x"*16
    for field in data:
        with pytest.raises(ValidationError):
            InventoryOperationCreate(**{k:v for k,v in data.items() if k != field})


@pytest.mark.parametrize("value", ["", "x"*65, "a b", "x\n", "é", 1])
def test_idempotency_header_rejects_invalid_values(value):
    with pytest.raises(ValidationError):
        TypeAdapter(IdempotencyKey).validate_python(value)
