"""Pure addition calculations shared by submission and future preview."""
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP

from app.db.models import InventoryItem
from app.core.quantity import (
    MAX_QUANTITY, QUANTITY_PRECISION, QuantityError, validate_addition_amount,
)


@dataclass(frozen=True)
class AdditionCalculation:
    """Calculated values only; no mutation, database writes, or new storage fields."""

    amount: Decimal
    unit: str
    affects_state: str
    applied_change_amount: Decimal
    calculation_method: str
    rounded: bool


def get_addition_base(item: InventoryItem) -> tuple[Decimal, str, str]:
    if item.estimated_current_amount is None:
        return (item.confirmed_current_amount, item.confirmed_current_unit, "CONFIRMED")
    return (item.estimated_current_amount, item.estimated_current_unit, "ESTIMATED")


def calculate_addition_amount(current_amount: Decimal, added_amount: Decimal) -> Decimal:
    return current_amount + added_amount


def grams_to_kilograms(num_grams: Decimal) -> Decimal:
    return num_grams / 1000


def kilograms_to_grams(num_kgs: Decimal) -> Decimal:
    return num_kgs * 1000


def milliliter_to_liter(num_mls: Decimal) -> Decimal:
    return num_mls / 1000


def liter_to_milliliter(num_liters: Decimal) -> Decimal:
    return num_liters * 1000


def convert_addition_amount(added_amount: Decimal, input_unit: str, target_unit: str) -> Decimal:
    source, target = input_unit.strip().casefold(), target_unit.strip().casefold()
    if source == "g" and target == "kg":
        return grams_to_kilograms(added_amount)
    if source == "kg" and target == "g":
        return kilograms_to_grams(added_amount)
    if source == "ml" and target == "l":
        return milliliter_to_liter(added_amount)
    if source == "l" and target == "ml":
        return liter_to_milliliter(added_amount)
    if source == target:
        return added_amount
    raise QuantityError("UNIT_NOT_CONVERTIBLE", "Units cannot be converted")


def calculate_addition(item: InventoryItem, added_amount: Decimal, input_unit: str) -> AdditionCalculation:
    """Round the applied change once, then add it to the effective balance."""
    validate_addition_amount(added_amount)
    current_amount, current_unit, amount_type = get_addition_base(item)
    converted = convert_addition_amount(added_amount, input_unit, current_unit)
    applied = converted.quantize(QUANTITY_PRECISION, rounding=ROUND_HALF_UP)
    if applied > MAX_QUANTITY:
        raise QuantityError("QUANTITY_OUT_OF_RANGE", "Converted added amount is above the maximum")
    if applied == 0:
        raise QuantityError("QUANTITY_TOO_SMALL", "Added amount rounds to zero in the inventory unit")
    output_amount = calculate_addition_amount(current_amount, applied)
    if output_amount > MAX_QUANTITY:
        raise QuantityError("QUANTITY_OUT_OF_RANGE", "Inventory amount is above the maximum")
    method = "EXACT" if input_unit.strip().casefold() == current_unit.strip().casefold() else "CONVERTED"
    return AdditionCalculation(output_amount, current_unit, amount_type, applied, method, applied != converted)


def prepare_addition(item: InventoryItem, added_amount: Decimal, input_unit: str) -> tuple[Decimal, str, str]:
    """Keep the learned tuple interface; submission also needs calculation details."""
    result = calculate_addition(item, added_amount, input_unit)
    return (result.amount, result.unit, result.affects_state)
