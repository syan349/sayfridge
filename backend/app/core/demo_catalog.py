"""Deterministic acceptance/demo dataset definitions without database access."""
from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID, uuid5


DEMO_NAMESPACE = UUID("955899bb-4dd8-4de0-9288-b594f2628af2")


def demo_uuid(key: str) -> UUID:
    return uuid5(DEMO_NAMESPACE, key)


@dataclass(frozen=True, slots=True)
class DemoUser:
    seed_key: str
    email: str
    role: str
    spaces: tuple[tuple[str, str, str], ...]


TEAM_EMAILS = (
    "member01@example.com",
    "member02@example.com",
    "member03@example.com",
    "member04@example.com",
    "member05@example.com",
)

# The first value is the legacy identity key used to derive existing UUIDs. It
# is never exposed as the account email; retaining it prevents an email repair
# from duplicating the user's spaces, inventory, or operation history.
_VIRTUAL_USERS = (
    ("ava.demo@example.test", "ava.demo@example.com", "USER"),
    ("ben.demo@example.test", "ben.demo@example.com", "USER"),
    ("chloe.demo@example.test", "chloe.demo@example.com", "USER"),
    ("daniel.demo@example.test", "daniel.demo@example.com", "USER"),
    ("emma.demo@example.test", "emma.demo@example.com", "USER"),
    ("admin.demo@example.test", "admin.demo@example.com", "ADMIN"),
)

_SPACE_NAMES = (
    ("MyFridge", "Frosty Freezer", "Snack Corner"),
    ("BoschFridge", "Arctic Box", "Pantry Potter"),
    ("Chill Zone", "Freeze Frame", "Cupboard Kingdom"),
    ("Fresh Fortress", "Ice Ice Pantry", "Midnight Snacks"),
    ("Cool Cabinet", "Polar Pocket", "Daily Staples"),
    ("Happy Fridge", "Frozen Assets", "Treat Treasury"),
    ("Green Machine", "Deep Freeze", "Breakfast Bank"),
    ("The Chiller", "Snow Vault", "Noodle Nook"),
    ("Fresh Station", "Winter Box", "Spice Shelf"),
    ("Kitchen Cloud", "Cold Storage", "Biscuit Bureau"),
    ("Admin Fridge", "Audit Freezer", "Control Pantry"),
)


def _spaces(names: tuple[str, str, str]) -> tuple[tuple[str, str, str], ...]:
    return (
        ("fridge", names[0], "FRIDGE"),
        ("freezer", names[1], "FREEZER"),
        ("pantry", names[2], "PANTRY"),
    )


DEMO_USERS = tuple(
    DemoUser(
        seed_key=email,
        email=email,
        role="USER",
        spaces=_spaces(_SPACE_NAMES[index]),
    )
    for index, email in enumerate(TEAM_EMAILS)
) + tuple(
    DemoUser(
        seed_key=seed_key,
        email=email,
        role=role,
        spaces=_spaces(_SPACE_NAMES[index + 5]),
    )
    for index, (seed_key, email, role) in enumerate(_VIRTUAL_USERS)
)


# One public definition per maintained category. Only a representative subset is
# placed in inventory; the rest makes the shared picker useful during acceptance.
PUBLIC_ITEM_DEFINITIONS = (
    ("Carrots", "Vegetables & Mushrooms"),
    ("Apples", "Fruit"),
    ("Coriander", "Fresh Herbs"),
    ("Chicken Breast", "Meat & Poultry"),
    ("Salmon", "Fish & Seafood"),
    ("Chicken Eggs", "Eggs"),
    ("Ham", "Processed & Deli Meats"),
    ("Whole Milk", "Milk & Plant-Based Milk"),
    ("Greek Yoghurt", "Yoghurt"),
    ("Cheddar", "Cheese"),
    ("Butter", "Butter & Cream"),
    ("Tofu", "Tofu & Meat Alternatives"),
    ("Rice", "Rice, Pasta & Grains"),
    ("Wholemeal Bread", "Bread & Bakery"),
    ("Chickpeas", "Dried Legumes, Nuts & Seeds"),
    ("Flour", "Baking Ingredients"),
    ("Tomato Sauce", "Sauces, Condiments & Spreads"),
    ("Olive Oil", "Oils & Vinegars"),
    ("Cumin", "Dried Herbs & Spices"),
    ("Vegetable Curry", "Prepared Meals & Leftovers"),
    ("Chocolate", "Snacks & Desserts"),
    ("Vanilla Ice Cream", "Ice Cream & Frozen Desserts"),
    ("Orange Juice", "Drinks, Tea & Coffee"),
    ("Dish Soap", "Household Supplies"),
    ("Mystery Ingredient", "Other"),
)


@dataclass(frozen=True, slots=True)
class InventoryScenario:
    key: str
    definition: str
    space: str
    initial_amount: str
    confirmed_amount: str
    unit: str
    status: str = "IN_STOCK"
    expiry_offset_days: int | None = None
    estimated_amount: str | None = None
    version: int = 1
    notes: str | None = None
    operation: tuple[str, str, str, str | None, str, str | None] | None = None


# operation fields: type, quantity kind, value, unit, affected state, applied amount.
INVENTORY_SCENARIOS = (
    InventoryScenario(
        "milk",
        "Whole Milk",
        "fridge",
        "1",
        "2",
        "L",
        expiry_offset_days=3,
        version=2,
        notes="Demo stock: recently topped up.",
        operation=("ADD", "AMOUNT", "1", "L", "CONFIRMED", "1"),
    ),
    InventoryScenario(
        "apples",
        "Apples",
        "fridge",
        "6",
        "6",
        "each",
        expiry_offset_days=7,
        estimated_amount="4",
        version=2,
        operation=("CONSUME", "AMOUNT", "2", "each", "ESTIMATED", "2"),
    ),
    InventoryScenario(
        "chicken",
        "Chicken Breast",
        "freezer",
        "0.8",
        "0.8",
        "kg",
        expiry_offset_days=-1,
        notes="Demo expired item for filtering.",
    ),
    InventoryScenario(
        "rice",
        "Rice",
        "pantry",
        "2",
        "1.5",
        "kg",
        version=2,
        operation=("RECONCILE", "AMOUNT", "1.5", "kg", "CONFIRMED", None),
    ),
    InventoryScenario(
        "yoghurt",
        "Greek Yoghurt",
        "fridge",
        "6",
        "0",
        "each",
        status="EMPTY",
        expiry_offset_days=1,
        version=2,
        operation=("CONSUME", "AMOUNT", "6", "each", "CONFIRMED", "6"),
    ),
    InventoryScenario(
        "chocolate",
        "Chocolate",
        "pantry",
        "2",
        "1",
        "each",
        status="DISCARDED",
        expiry_offset_days=90,
        version=3,
        operation=("CONSUME", "AMOUNT", "1", "each", "CONFIRMED", "1"),
    ),
    InventoryScenario(
        "olive-oil",
        "Olive Oil",
        "pantry",
        "1",
        "0.7",
        "L",
        status="ARCHIVED",
        version=3,
        operation=("CONSUME", "AMOUNT", "0.3", "L", "CONFIRMED", "0.3"),
    ),
)
