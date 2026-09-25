"""Pure quantity calculations shared by submission and future preview."""
from dataclasses import dataclass
from fractions import Fraction
from decimal import Decimal, ROUND_HALF_UP

from app.db.models import InventoryItem
from app.core.quantity import (
    MAX_QUANTITY, QUANTITY_PRECISION, QuantityError, validate_addition_amount, validate_quantity_amount,
    parse_consumption_fraction,
)

@dataclass(frozen=True)
class QuantityCalculation:
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
    from app.core.quantity import normalize_standard_unit
    source, target = normalize_standard_unit(input_unit), normalize_standard_unit(target_unit)
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


def calculate_addition(item: InventoryItem, added_amount: Decimal, input_unit: str) -> QuantityCalculation:
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
    return QuantityCalculation(output_amount, current_unit, amount_type, applied, method, applied != converted)


def prepare_addition(item: InventoryItem, added_amount: Decimal, input_unit: str) -> tuple[Decimal, str, str]:
    """Keep the learned tuple interface; submission also needs calculation details."""
    result = calculate_addition(item, added_amount, input_unit)
    return (result.amount, result.unit, result.affects_state)


def calculate_consumption(item: InventoryItem, quantity_kind: str, quantity_value: str,
                          input_unit: str) -> QuantityCalculation:
    """Consume an amount or exact fraction without silently erasing a remainder.

    Fraction arithmetic keeps arbitrary valid integer ratios exact. Only the final
    applied change is rounded to 0.001 using integer half-up arithmetic.
    """
    current_amount, current_unit, amount_type = get_addition_base(item)
    balance = Fraction(current_amount)
    if quantity_kind == "FRACTION":
        numerator, denominator = parse_consumption_fraction(quantity_value)
        if input_unit != "remaining":
            raise ValueError("Fraction quantity_unit must be remaining")
        unrounded = balance * Fraction(numerator, denominator)
        method = "EXACT"
    elif quantity_kind == "AMOUNT":
        amount = Decimal(quantity_value)
        validate_addition_amount(amount)
        unrounded = Fraction(convert_addition_amount(amount, input_unit, current_unit))
        method = "EXACT" if input_unit.strip().casefold() == current_unit.strip().casefold() else "CONVERTED"
    else:
        raise ValueError("Unsupported quantity kind")
    if unrounded > balance:
        raise QuantityError("INSUFFICIENT_QUANTITY", "Consumption exceeds the current balance")

    scaled = unrounded * 1000
    whole, remainder = divmod(scaled.numerator, scaled.denominator)
    milliunits = whole + (2 * remainder >= scaled.denominator)
    applied = (Decimal(milliunits) / 1000).quantize(QUANTITY_PRECISION)
    if applied == 0:
        raise QuantityError("QUANTITY_TOO_SMALL", "Consumed amount rounds to zero in the inventory unit")
    if applied > MAX_QUANTITY:
        raise QuantityError("QUANTITY_OUT_OF_RANGE", "Consumed amount is above the maximum")
    output_amount = current_amount - applied
    if unrounded < balance and output_amount == 0:
        raise QuantityError("QUANTITY_PRECISION_UNSUPPORTED", "Rounding would erase a positive remaining quantity")
    return QuantityCalculation(output_amount, current_unit, amount_type, applied, method,
                               Fraction(applied) != unrounded)

def calculate_estimated_change(item: InventoryItem, operation: str, amount: Decimal, unit: str) -> QuantityCalculation:
    """Apply an approved estimated delta, never promote it to a confirmed fact."""
    if operation not in {"ADD", "CONSUME"}:
        raise ValueError("Estimates only apply to ADD/CONSUME")
    if not amount.is_finite() or amount <= 0 or amount > MAX_QUANTITY:
        raise ValueError("Estimated change must be a positive finite supported amount")
    base, base_unit, _ = get_addition_base(item)
    converted = convert_addition_amount(amount, unit, base_unit)
    if operation == "CONSUME" and converted > base:
        raise QuantityError("INSUFFICIENT_QUANTITY", "Consumption exceeds current balance")
    applied = converted.quantize(QUANTITY_PRECISION, rounding=ROUND_HALF_UP)
    if applied == 0:
        raise QuantityError("QUANTITY_TOO_SMALL", "Estimated change rounds to zero")
    result = base + applied if operation == "ADD" else base - applied
    if operation == "CONSUME" and converted < base and result == 0:
        raise QuantityError("QUANTITY_PRECISION_UNSUPPORTED", "Rounding erases positive remainder")
    validate_quantity_amount(result, allow_zero=True)
    return QuantityCalculation(result, base_unit, "ESTIMATED", applied, "AI_ESTIMATED", applied != converted)


def prepare_reconciliation(amount: Decimal, unit: str) -> tuple[Decimal, str]:
    """Validate and return a confirmed stocktake total without unit conversion."""
    validate_quantity_amount(amount, allow_zero=True)
    return (amount, unit)
