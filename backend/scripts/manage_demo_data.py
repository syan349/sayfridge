"""Seed, check, or reset deterministic non-production acceptance data."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import os
from pathlib import Path
import re
import sys

from sqlalchemy import create_engine, delete, func, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import NullPool


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.core.catalog import normalize_catalog_name  # noqa: E402
from app.core.demo_catalog import (  # noqa: E402
    DEMO_USERS,
    INVENTORY_SCENARIOS,
    PUBLIC_ITEM_DEFINITIONS,
    demo_uuid,
)
from app.core.security import hash_password  # noqa: E402
from app.core.config import get_settings  # noqa: E402
from app.db.models import (  # noqa: E402
    AgentInventoryAction,
    Conversation,
    InventoryItem,
    InventoryOperation,
    ItemCategory,
    ItemDefinition,
    StorageSpace,
    User,
)


SCHEMA_PATTERN = re.compile(r"^[a-z_][a-z0-9_]*$")
SEED_CONFIRMATION = "SEED-DEMO-DATA"
RESET_CONFIRMATION = "RESET-DEMO-DATA"


@dataclass(frozen=True, slots=True)
class DemoDataReport:
    users: int
    storage_spaces: int
    public_definitions: int
    inventory_items: int
    inventory_operations: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("seed", "check", "reset"))
    parser.add_argument(
        "--target",
        required=True,
        choices=("local", "predeploy", "acceptance"),
        help="Explicitly identify the non-production target.",
    )
    parser.add_argument("--business-schema", default="public")
    parser.add_argument(
        "--confirm",
        help=f"Use {SEED_CONFIRMATION} for seed or {RESET_CONFIRMATION} for reset.",
    )
    return parser.parse_args()


def _validate_password(name: str, value: str | None) -> str:
    if value is None or len(value) < 12 or len(value) > 128:
        raise SystemExit(f"{name} must contain 12 to 128 characters")
    return value


def _expected_ids(kind: str, keys: list[str]) -> set:
    return {demo_uuid(f"{kind}:{key}") for key in keys}


def _category_map(session: Session) -> dict[str, ItemCategory]:
    categories = {
        row.normalized_name: row
        for row in session.scalars(select(ItemCategory)).all()
        if row.status == "ACTIVE"
    }
    required = {
        normalize_catalog_name(category)
        for _name, category in PUBLIC_ITEM_DEFINITIONS
    }
    missing = sorted(required - set(categories))
    if missing:
        raise RuntimeError(
            "Demo seed requires the baseline category seed; missing: "
            + ", ".join(missing)
        )
    return categories


def _seed_definitions(
    session: Session,
    categories: dict[str, ItemCategory],
) -> dict[str, ItemDefinition]:
    existing = {
        row.normalized_name: row
        for row in session.scalars(
            select(ItemDefinition).where(ItemDefinition.owner_user_id.is_(None))
        ).all()
    }
    result: dict[str, ItemDefinition] = {}
    for name, category_name in PUBLIC_ITEM_DEFINITIONS:
        normalized = normalize_catalog_name(name)
        row = existing.get(normalized)
        if row is None:
            row = ItemDefinition(
                id=demo_uuid(f"definition:{normalized}"),
                name=name,
                normalized_name=normalized,
                category_id=categories[normalize_catalog_name(category_name)].id,
                owner_user_id=None,
                status="ACTIVE",
            )
            session.add(row)
        elif row.status != "ACTIVE":
            raise RuntimeError(f"Public item definition is archived: {name}")
        elif row.category_id != categories[normalize_catalog_name(category_name)].id:
            raise RuntimeError(
                f"Public item definition has an unexpected category: {name}"
            )
        result[name] = row
    session.flush()
    return result


def _seed_users(
    session: Session,
    user_password: str,
    admin_password: str,
) -> dict[str, User]:
    emails = [entry.email for entry in DEMO_USERS]
    existing = {
        row.email: row
        for row in session.scalars(select(User).where(User.email.in_(emails))).all()
    }
    user_hash = hash_password(user_password)
    admin_hash = hash_password(admin_password)
    result: dict[str, User] = {}
    for entry in DEMO_USERS:
        row = existing.get(entry.email)
        if row is None:
            row = User(
                id=demo_uuid(f"user:{entry.email}"),
                email=entry.email,
                password_hash=admin_hash if entry.role == "ADMIN" else user_hash,
                auth_provider="LOCAL",
                role=entry.role,
                status="ACTIVE",
                voice_limit_seconds=0,
                voice_used_seconds=0,
            )
            session.add(row)
        elif entry.role == "ADMIN" and row.role != "ADMIN":
            raise RuntimeError(
                f"Existing demo administrator has role {row.role}; refusing to change it"
            )
        elif row.status != "ACTIVE" or row.auth_provider != "LOCAL" or row.password_hash is None:
            raise RuntimeError(
                f"Existing demo account is not an active local-password account: {entry.email}"
            )
        result[entry.email] = row
    session.flush()
    return result


def _seed_spaces(session: Session, users: dict[str, User]) -> dict[tuple[str, str], StorageSpace]:
    result: dict[tuple[str, str], StorageSpace] = {}
    for entry in DEMO_USERS:
        user = users[entry.email]
        existing = {
            row.name.casefold(): row
            for row in session.scalars(
                select(StorageSpace).where(
                    StorageSpace.user_id == user.id,
                    StorageSpace.status == "ACTIVE",
                )
            ).all()
        }
        for key, name, space_type in entry.spaces:
            row = existing.get(name.casefold())
            if row is None:
                row = StorageSpace(
                    id=demo_uuid(f"space:{entry.email}:{key}"),
                    user_id=user.id,
                    name=name,
                    type=space_type,
                    status="ACTIVE",
                )
                session.add(row)
            elif row.type != space_type:
                raise RuntimeError(
                    f"Existing demo storage space has an unexpected type: {name}"
                )
            result[(entry.email, key)] = row
    session.flush()
    return result


def _seed_inventory(
    session: Session,
    users: dict[str, User],
    spaces: dict[tuple[str, str], StorageSpace],
    definitions: dict[str, ItemDefinition],
    *,
    today: date,
    now: datetime,
) -> None:
    inventory_ids = _expected_ids(
        "inventory",
        [f"{entry.email}:{scenario.key}" for entry in DEMO_USERS for scenario in INVENTORY_SCENARIOS],
    )
    existing_inventory = set(
        session.scalars(select(InventoryItem.id).where(InventoryItem.id.in_(inventory_ids)))
    )
    for entry in DEMO_USERS:
        for scenario in INVENTORY_SCENARIOS:
            row_id = demo_uuid(f"inventory:{entry.email}:{scenario.key}")
            if row_id in existing_inventory:
                continue
            estimated_at = now if scenario.estimated_amount is not None else None
            session.add(
                InventoryItem(
                    id=row_id,
                    storage_space_id=spaces[(entry.email, scenario.space)].id,
                    item_definition_id=definitions[scenario.definition].id,
                    notes=scenario.notes,
                    purchase_date=today - timedelta(days=7),
                    expiry_date=(
                        today + timedelta(days=scenario.expiry_offset_days)
                        if scenario.expiry_offset_days is not None
                        else None
                    ),
                    status=scenario.status,
                    initial_amount=Decimal(scenario.initial_amount),
                    initial_unit=scenario.unit,
                    confirmed_current_amount=Decimal(scenario.confirmed_amount),
                    confirmed_current_unit=scenario.unit,
                    confirmed_at=now,
                    estimated_current_amount=(
                        Decimal(scenario.estimated_amount)
                        if scenario.estimated_amount is not None
                        else None
                    ),
                    estimated_current_unit=(
                        scenario.unit if scenario.estimated_amount is not None else None
                    ),
                    estimated_at=estimated_at,
                    version=scenario.version,
                )
            )
    session.flush()

    operation_ids = _expected_ids(
        "operation",
        [f"{entry.email}:{scenario.key}" for entry in DEMO_USERS for scenario in INVENTORY_SCENARIOS if scenario.operation],
    )
    existing_operations = set(
        session.scalars(
            select(InventoryOperation.id).where(InventoryOperation.id.in_(operation_ids))
        )
    )
    for entry in DEMO_USERS:
        user_id = users[entry.email].id
        for scenario in INVENTORY_SCENARIOS:
            if scenario.operation is None:
                continue
            row_id = demo_uuid(f"operation:{entry.email}:{scenario.key}")
            if row_id in existing_operations:
                continue
            operation_type, quantity_kind, value, unit, affects_state, applied = scenario.operation
            session.add(
                InventoryOperation(
                    id=row_id,
                    inventory_item_id=demo_uuid(f"inventory:{entry.email}:{scenario.key}"),
                    operation_type=operation_type,
                    affects_state=affects_state,
                    input_method="MANUAL",
                    quantity_kind=quantity_kind,
                    quantity_value=value,
                    quantity_unit=unit,
                    calculation_method="EXACT",
                    applied_change_amount=Decimal(applied) if applied is not None else None,
                    applied_change_unit=unit if applied is not None else None,
                    status="SUCCESS",
                    idempotency_key=f"{user_id}:demo-seed-{scenario.key}",
                )
            )
    session.flush()


def inspect_demo_data(session: Session) -> DemoDataReport:
    emails = [entry.email for entry in DEMO_USERS]
    users = list(session.scalars(select(User).where(User.email.in_(emails))))
    users_by_email = {user.email: user for user in users}
    definition_names = [normalize_catalog_name(name) for name, _ in PUBLIC_ITEM_DEFINITIONS]
    inventory_ids = _expected_ids(
        "inventory",
        [f"{entry.email}:{scenario.key}" for entry in DEMO_USERS for scenario in INVENTORY_SCENARIOS],
    )
    operation_ids = _expected_ids(
        "operation",
        [f"{entry.email}:{scenario.key}" for entry in DEMO_USERS for scenario in INVENTORY_SCENARIOS if scenario.operation],
    )
    expected_space_count = 0
    for entry in DEMO_USERS:
        user = users_by_email.get(entry.email)
        if user is None:
            continue
        names = [name.casefold() for _key, name, _type in entry.spaces]
        expected_space_count += session.scalar(
            select(func.count()).select_from(StorageSpace).where(
                StorageSpace.user_id == user.id,
                func.lower(StorageSpace.name).in_(names),
                StorageSpace.status == "ACTIVE",
            )
        ) or 0

    return DemoDataReport(
        users=len(users),
        storage_spaces=expected_space_count,
        public_definitions=session.scalar(
            select(func.count()).select_from(ItemDefinition).where(
                ItemDefinition.owner_user_id.is_(None),
                ItemDefinition.normalized_name.in_(definition_names),
                ItemDefinition.status == "ACTIVE",
            )
        ) or 0,
        inventory_items=session.scalar(
            select(func.count()).select_from(InventoryItem).where(InventoryItem.id.in_(inventory_ids))
        ) or 0,
        inventory_operations=session.scalar(
            select(func.count()).select_from(InventoryOperation).where(InventoryOperation.id.in_(operation_ids))
        ) or 0,
    )


def _assert_complete(report: DemoDataReport) -> None:
    expected = DemoDataReport(
        users=len(DEMO_USERS),
        storage_spaces=sum(len(entry.spaces) for entry in DEMO_USERS),
        public_definitions=len(PUBLIC_ITEM_DEFINITIONS),
        inventory_items=len(DEMO_USERS) * len(INVENTORY_SCENARIOS),
        inventory_operations=len(DEMO_USERS)
        * sum(scenario.operation is not None for scenario in INVENTORY_SCENARIOS),
    )
    if report != expected:
        raise RuntimeError(f"Demo dataset is incomplete: {report}; expected {expected}")


def seed_demo_data(
    session: Session,
    *,
    user_password: str,
    admin_password: str,
    today: date | None = None,
) -> DemoDataReport:
    categories = _category_map(session)
    definitions = _seed_definitions(session, categories)
    users = _seed_users(session, user_password, admin_password)
    spaces = _seed_spaces(session, users)
    now = datetime.now(timezone.utc)
    _seed_inventory(
        session,
        users,
        spaces,
        definitions,
        today=today or now.date(),
        now=now,
    )
    report = inspect_demo_data(session)
    _assert_complete(report)
    return report


def reset_demo_data(session: Session) -> None:
    inventory_keys = [
        f"{entry.email}:{scenario.key}"
        for entry in DEMO_USERS
        for scenario in INVENTORY_SCENARIOS
    ]
    operation_keys = [
        f"{entry.email}:{scenario.key}"
        for entry in DEMO_USERS
        for scenario in INVENTORY_SCENARIOS
        if scenario.operation
    ]
    session.execute(
        delete(InventoryOperation).where(
            InventoryOperation.id.in_(_expected_ids("operation", operation_keys))
        )
    )
    session.execute(
        delete(InventoryItem).where(
            InventoryItem.id.in_(_expected_ids("inventory", inventory_keys))
        )
    )
    session.execute(
        delete(StorageSpace).where(
            StorageSpace.id.in_(
                _expected_ids(
                    "space",
                    [f"{entry.email}:{key}" for entry in DEMO_USERS for key, _name, _type in entry.spaces],
                )
            )
        )
    )
    seeded_user_ids = _expected_ids("user", [entry.email for entry in DEMO_USERS])
    session.execute(
        delete(User).where(
            User.id.in_(seeded_user_ids),
            ~select(StorageSpace.id)
            .where(StorageSpace.user_id == User.id)
            .exists(),
            ~select(ItemDefinition.id)
            .where(ItemDefinition.owner_user_id == User.id)
            .exists(),
            ~select(Conversation.id).where(Conversation.user_id == User.id).exists(),
            ~select(AgentInventoryAction.id)
            .where(AgentInventoryAction.user_id == User.id)
            .exists(),
        )
    )
    definition_ids = _expected_ids(
        "definition",
        [normalize_catalog_name(name) for name, _category in PUBLIC_ITEM_DEFINITIONS],
    )
    referenced_definition_ids = select(InventoryItem.item_definition_id)
    session.execute(
        delete(ItemDefinition).where(
            ItemDefinition.id.in_(definition_ids),
            ItemDefinition.id.not_in(referenced_definition_ids),
        )
    )
    session.flush()


def _print_report(action: str, target: str, report: DemoDataReport) -> None:
    print(f"Demo data {action}:")
    print(f"  declared target: {target}")
    print(f"  users: {report.users}")
    print(f"  active storage spaces: {report.storage_spaces}")
    print(f"  public item definitions: {report.public_definitions}")
    print(f"  inventory items: {report.inventory_items}")
    print(f"  inventory operations: {report.inventory_operations}")


def main() -> None:
    args = parse_args()
    if not SCHEMA_PATTERN.fullmatch(args.business_schema):
        raise SystemExit("--business-schema must be a lowercase PostgreSQL identifier")
    if args.action == "seed" and args.confirm != SEED_CONFIRMATION:
        raise SystemExit(f"Seed requires --confirm {SEED_CONFIRMATION}")
    if args.action == "reset" and args.confirm != RESET_CONFIRMATION:
        raise SystemExit(f"Reset requires --confirm {RESET_CONFIRMATION}")

    settings = get_settings()
    engine = create_engine(
        settings.database_url_direct.get_secret_value(),
        poolclass=NullPool,
        hide_parameters=True,
        connect_args={"connect_timeout": 15},
    )
    quoted_schema = engine.dialect.identifier_preparer.quote(args.business_schema)
    try:
        with engine.begin() as connection:
            connection.exec_driver_sql(f"SET LOCAL search_path TO {quoted_schema}")
            with Session(connection) as session:
                if args.action == "seed":
                    report = seed_demo_data(
                        session,
                        user_password=_validate_password(
                            "DEMO_USER_PASSWORD", os.getenv("DEMO_USER_PASSWORD")
                        ),
                        admin_password=_validate_password(
                            "DEMO_ADMIN_PASSWORD", os.getenv("DEMO_ADMIN_PASSWORD")
                        ),
                    )
                    _print_report("seeded and verified", args.target, report)
                elif args.action == "check":
                    connection.exec_driver_sql("SET TRANSACTION READ ONLY")
                    report = inspect_demo_data(session)
                    _assert_complete(report)
                    _print_report("verification passed", args.target, report)
                else:
                    reset_demo_data(session)
                    _print_report(
                        "reset completed",
                        args.target,
                        inspect_demo_data(session),
                    )
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
