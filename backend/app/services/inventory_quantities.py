"""Quantity calculations shared by future operation preview and submission.

Guided development: addition calculations include input precision validation.
This module is not yet connected to an HTTP endpoint.
"""
from decimal import Decimal, ROUND_HALF_UP

from app.db.models import InventoryItem
from app.core.quantity import MAX_QUANTITY, QUANTITY_PRECISION, validate_addition_amount


def get_addition_base(item: InventoryItem) -> tuple[Decimal, str, str]:
    if item.estimated_current_amount is None:
        return (item.confirmed_current_amount, item.confirmed_current_unit, "CONFIRMED")
    else:
        return (item.estimated_current_amount, item.estimated_current_unit, "ESTIMATED")


def calculate_addition_amount(current_amount:Decimal, added_amount:Decimal) -> Decimal:
    return (current_amount + added_amount)

def grams_to_kilograms(num_grams:Decimal) -> Decimal:
    return (num_grams/1000)

def kilograms_to_grams(num_kgs:Decimal) -> Decimal:
    return (num_kgs*1000)

def milliliter_to_liter(num_mls:Decimal) -> Decimal:
    return (num_mls/1000)

def liter_to_milliliter(num_liters:Decimal) -> Decimal:
    return (num_liters*1000)

def convert_addition_amount(added_amount:Decimal, input_unit:str, target_unit:str) -> Decimal:
    if input_unit.lower()=='g' and target_unit.lower()=='kg':
        return grams_to_kilograms(added_amount)
    elif input_unit.lower()=='kg' and target_unit.lower()=='g':
        return kilograms_to_grams(added_amount)
    elif input_unit.lower()=='ml' and target_unit.lower()=='l':
            return milliliter_to_liter(added_amount)
    elif input_unit.lower()=='l' and target_unit.lower()=='ml':
            return liter_to_milliliter(added_amount)
    elif input_unit.lower()==target_unit.lower():
         return added_amount
    else:
         raise ValueError("Invalid unit")

def prepare_addition(item: InventoryItem, added_amount:Decimal, input_unit:str) -> tuple[Decimal, str, str]:
    validate_addition_amount(added_amount)

    (current_amount, current_unit, amount_type) = get_addition_base(item)
    added_amount_standardised=convert_addition_amount(added_amount, input_unit, current_unit)\
        .quantize(QUANTITY_PRECISION, rounding=ROUND_HALF_UP)
    if added_amount_standardised > MAX_QUANTITY:
        raise ValueError("Converted added amount is above the maximum")
    if added_amount_standardised == 0:
        raise ValueError("Added value is below the minimum")

    output_amount = calculate_addition_amount(current_amount, added_amount_standardised)
    if output_amount > MAX_QUANTITY:
        raise ValueError("Inventory value is above the maximum")
    
    return (output_amount, current_unit, amount_type)
