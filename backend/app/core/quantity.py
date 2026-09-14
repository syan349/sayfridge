"""Shared quantity limits matching the database NUMERIC(12, 3) columns."""
from decimal import Decimal

MAX_QUANTITY = Decimal("999999999.999")

QUANTITY_PRECISION = Decimal("0.001")


def validate_addition_amount(amount: Decimal) -> None:
    """Validate a parsed addition before conversion or rounding.

    The future request schema must also validate the original decimal string;
    Decimal alone cannot preserve every aspect of the client's input syntax.
    """
    if not isinstance(amount, Decimal) or not amount.is_finite():
        raise ValueError("Added amount must be a finite Decimal")
    if amount <= 0:
        raise ValueError("Added value must be greater than zero")
    if amount > MAX_QUANTITY:
        raise ValueError("Added value is above the maximum")
    # Preserve input scale: 2.1250 has four decimal places, even with a final zero.
    if amount.as_tuple().exponent < -3:
        raise ValueError("Added amount must have at most three decimal places")
