"""Database-free RECONCILE request and calculation checks."""
from decimal import Decimal

import pytest
from pydantic import ValidationError

from app.core.quantity import QuantityError
from app.schemas.inventory_operations import InventoryOperationCreate
from app.services.inventory_quantities import prepare_reconciliation


def reconciliation(**changes):
    return dict(expected_version=1, operation_type="RECONCILE", quantity_kind="AMOUNT",
                quantity_value="6", quantity_unit="kg") | changes


@pytest.mark.parametrize("value", ["0", "6", "6.000", "999999999.999"])
def test_reconciliation_contract_accepts_nonnegative_totals(value):
    request = InventoryOperationCreate(**reconciliation(quantity_value=value, quantity_unit=" kg "))
    assert request.quantity_value == value and request.quantity_unit == "kg"


@pytest.mark.parametrize("changes", [
    {"quantity_kind": "FRACTION", "quantity_value": "1/2", "quantity_unit": "remaining"},
    {"quantity_value": "-1"}, {"quantity_value": "6.0001"},
    {"quantity_value": "1e2"}, {"quantity_value": 6},
])
def test_reconciliation_contract_rejects_invalid_input(changes):
    with pytest.raises(ValidationError):
        InventoryOperationCreate(**reconciliation(**changes))


@pytest.mark.parametrize("value", ["8", "0", "8.125"])
def test_prepare_reconciliation_returns_the_submitted_total(value):
    result = prepare_reconciliation(Decimal(value), "litres")
    assert result == (Decimal(value), "litres")


def test_prepare_reconciliation_rejects_negative_and_oversized_totals():
    with pytest.raises(ValueError, match="nonnegative"):
        prepare_reconciliation(Decimal("-1"), "kg")
    with pytest.raises(QuantityError) as error:
        prepare_reconciliation(Decimal("1000000000"), "kg")
    assert error.value.code == "QUANTITY_OUT_OF_RANGE"


def test_existing_operations_still_reject_zero_amounts():
    for operation_type in ("ADD", "CONSUME"):
        with pytest.raises(ValidationError):
            InventoryOperationCreate(**reconciliation(
                operation_type=operation_type, quantity_value="0"
            ))
