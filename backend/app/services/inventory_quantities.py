"""Pure quantity calculations shared by submission and future preview."""
from dataclasses import dataclass
from fractions import Fraction
from decimal import Decimal, ROUND_HALF_UP, localcontext

from app.db.models import InventoryItem
from app.core.quantity import (
    MAX_QUANTITY, QUANTITY_PRECISION, QuantityError, validate_addition_amount, validate_quantity_amount,
    parse_consumption_fraction,
)

@dataclass(frozen=True)
class QuantityCalculation:
    """Pure result in the unit of the current operation."""

    amount: Decimal
    unit: str
    affects_state: str
    applied_change_amount: Decimal
    calculation_method: str
    rounded: bool
    is_empty: bool = False


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


COUNT_UNITS = {"个", "颗", "只", "枚", "件", "袋", "瓶", "盒", "包", "罐", "根", "条", "块",
               "each", "pcs", "pc", "piece", "pieces", "count", "item", "items", "bottle", "bottles",
               "bag", "bags", "box", "boxes", "pack", "packs", "can", "cans"}


def canonical(unit):
    from app.core.quantity import normalize_standard_unit
    unit = normalize_standard_unit(unit)
    return {"kg": ("g", 1000), "l": ("ml", 1000)}.get(unit, (unit, 1))


def _ratio(relation):
    source, sf = canonical(relation["source_unit"])
    target, tf = canonical(relation["target_unit"])
    a, b = Fraction(Decimal(relation["source_amount"])) * sf, Fraction(Decimal(relation["target_amount"])) * tf
    if a <= 0 or b <= 0:
        raise ValueError("Conversion amounts must be positive")
    return source, target, b / a


def calculate_change(item, operation, kind, value, input_unit, *, relationship=None, estimated=False):
    """Convert the effective balance to the requested unit, then apply the change."""
    from app.core.quantity import normalize_standard_unit
    if operation not in {"ADD", "CONSUME"} or kind not in {"AMOUNT", "FRACTION"}:
        raise ValueError("Unsupported quantity operation")
    if kind == "FRACTION" and operation != "CONSUME":
        raise ValueError("Fractions only support consumption")
    current, current_unit, affects = get_addition_base(item)
    estimated_input = estimated
    unit = normalize_standard_unit(current_unit if kind == "FRACTION" else input_unit)
    base_unit, base_factor = canonical(current_unit)
    target_unit, target_factor = canonical(unit)
    cross_dimension = base_unit != target_unit
    with localcontext() as context:
        context.prec = 80
        balance = current * base_factor
        if cross_dimension:
            if not relationship:
                raise QuantityError("UNIT_NOT_CONVERTIBLE", "A unit relationship is required")
            left, right, ratio = _ratio(relationship)
            rate = Decimal(ratio.numerator) / Decimal(ratio.denominator)
            if (base_unit, target_unit) == (left, right):
                balance *= rate
            elif (base_unit, target_unit) == (right, left):
                balance /= rate
            else:
                raise QuantityError("UNIT_NOT_CONVERTIBLE", "Relationship does not match units")
            estimated = True
        balance /= target_factor
        if kind == "FRACTION":
            numerator, denominator = parse_consumption_fraction(value)
            delta = balance * Decimal(numerator) / Decimal(denominator)
            if unit in COUNT_UNITS and delta != delta.to_integral_value():
                raise QuantityError("WHOLE_COUNT_REQUIRED", "Specify the actual whole or partial count consumed")
        else:
            delta = Decimal(value)
            if estimated_input:
                if not delta.is_finite() or delta <= 0:
                    raise ValueError("Estimated amount must be positive and finite")
                if delta > MAX_QUANTITY:
                    raise QuantityError("QUANTITY_OUT_OF_RANGE", "Estimated amount exceeds storage capacity")
                if delta < QUANTITY_PRECISION:
                    raise QuantityError("QUANTITY_TOO_SMALL", "Estimated change is below the supported precision")
            else:
                validate_addition_amount(delta)
            if estimated_input and unit in COUNT_UNITS:
                delta = delta.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
        # Check unrounded stock before integer estimation can manufacture inventory.
        if operation == "CONSUME" and delta > balance:
            raise QuantityError("INSUFFICIENT_QUANTITY", "Consumption exceeds the current balance")
        if delta <= 0:
            raise QuantityError("QUANTITY_TOO_SMALL", "No positive quantity to consume")
        count_estimate = (cross_dimension or estimated_input) and unit in COUNT_UNITS
        explicit_partial = not estimated_input and delta != delta.to_integral_value()
        if count_estimate and explicit_partial:
            balance = balance.quantize(Decimal("1"), rounding=ROUND_HALF_UP)
            if operation == "CONSUME" and delta > balance:
                raise QuantityError("INSUFFICIENT_QUANTITY", "Consumption exceeds the estimated whole count")
        exact = balance + delta if operation == "ADD" else balance - delta
        precision = Decimal("1") if count_estimate and not explicit_partial else QUANTITY_PRECISION
        rounded = exact.quantize(precision, rounding=ROUND_HALF_UP).quantize(QUANTITY_PRECISION)
        applied = delta.quantize(QUANTITY_PRECISION, rounding=ROUND_HALF_UP)
        if applied == 0:
            raise QuantityError("QUANTITY_TOO_SMALL", "Change is below the supported quantity precision")
        if not count_estimate and operation == "CONSUME" and exact > 0 and (rounded == 0 or applied >= balance):
            raise QuantityError("QUANTITY_PRECISION_UNSUPPORTED", "Rounding would erase a positive remaining quantity")
        if rounded > MAX_QUANTITY or applied > MAX_QUANTITY:
            raise QuantityError("QUANTITY_OUT_OF_RANGE", "Quantity exceeds storage capacity")
        method = "AI_ESTIMATED" if estimated else "EXACT" if normalize_standard_unit(current_unit) == unit else "CONVERTED"
        return QuantityCalculation(rounded, unit, "ESTIMATED" if estimated else affects,
            applied, method, rounded != exact, rounded == 0)


def calculate_addition(item, added_amount, input_unit):
    return calculate_change(item, "ADD", "AMOUNT", str(added_amount), input_unit)


def prepare_addition(item, added_amount, input_unit):
    result = calculate_addition(item, added_amount, input_unit)
    return result.amount, result.unit, result.affects_state


def calculate_consumption(item, quantity_kind, quantity_value, input_unit):
    return calculate_change(item, "CONSUME", quantity_kind, quantity_value, input_unit)


def calculate_estimated_change(item, operation, amount, unit):
    return calculate_change(item, operation, "AMOUNT", str(amount), unit, estimated=True)


def prepare_reconciliation(amount, unit):
    validate_quantity_amount(amount, allow_zero=True)
    return amount, unit
