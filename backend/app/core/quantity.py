"""Shared quantity limits matching the database NUMERIC(12, 3) columns."""
import re
from decimal import Decimal

MAX_QUANTITY = Decimal("999999999.999")

QUANTITY_PRECISION = Decimal("0.001")


class QuantityError(ValueError):
    """A calculation failure with a stable public business error code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def validate_addition_amount(amount: Decimal) -> None:
    """Validate a parsed addition before conversion or rounding.

    The request schema also validates the original decimal string;
    Decimal alone cannot preserve every aspect of the client's input syntax.
    """
    if not isinstance(amount, Decimal) or not amount.is_finite():
        raise ValueError("Added amount must be a finite Decimal")
    if amount <= 0:
        raise ValueError("Added value must be greater than zero")
    if amount > MAX_QUANTITY:
        raise QuantityError("QUANTITY_OUT_OF_RANGE", "Added value is above the maximum")
    # Preserve input scale: 2.1250 has four decimal places, even with a final zero.
    if amount.as_tuple().exponent < -3:
        raise ValueError("Added amount must have at most three decimal places")


def parse_consumption_fraction(value: str) -> tuple[int, int]:
    """Parse an exact positive ratio without converting it to a rounded decimal."""
    if not isinstance(value, str) or len(value) > 32 or not re.fullmatch(r"[0-9]+/[0-9]+", value):
        raise ValueError("Fraction must use p/q with positive integers and at most 32 characters")
    numerator, denominator = map(int, value.split("/"))
    if not 0 < numerator <= denominator:
        raise ValueError("Fraction must satisfy 0 < p <= q")
    return numerator, denominator
