"""Read-only verification that PostgreSQL matches the current ORM schema."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from sqlalchemy import (
    CheckConstraint,
    ForeignKeyConstraint,
    Index,
    MetaData,
    PrimaryKeyConstraint,
    UniqueConstraint,
    inspect,
)
from sqlalchemy.dialects import postgresql
from sqlalchemy.engine import Connection


class SchemaVerificationError(RuntimeError):
    """Raised when a database is missing an ORM-required schema object."""


@dataclass(frozen=True, slots=True)
class SchemaVerificationReport:
    tables: int
    columns: int
    primary_keys: int
    foreign_keys: int
    unique_constraints: int
    check_constraints: int
    indexes: int


def _column_names(columns: Iterable[object]) -> tuple[str, ...]:
    return tuple(column.name for column in columns)


def _type_signature(column_type: object) -> str:
    return str(column_type.compile(dialect=postgresql.dialect())).upper()


def _foreign_key_signature(constraint: ForeignKeyConstraint) -> tuple[object, ...]:
    elements = tuple(constraint.elements)
    return (
        _column_names(constraint.columns),
        tuple(element.target_fullname.rsplit(".", 1)[-2] for element in elements),
        tuple(element.target_fullname.rsplit(".", 1)[-1] for element in elements),
        (constraint.ondelete or "").upper(),
    )


def _reflected_foreign_key_signature(
    foreign_key: dict[str, object],
) -> tuple[object, ...]:
    options = foreign_key.get("options") or {}
    return (
        tuple(foreign_key.get("constrained_columns") or ()),
        tuple(
            str(foreign_key.get("referred_table"))
            for _ in foreign_key.get("referred_columns") or ()
        ),
        tuple(foreign_key.get("referred_columns") or ()),
        str(options.get("ondelete") or "").upper(),
    )


def _verify_columns(inspector, table, schema: str, problems: list[str]) -> int:
    reflected = {
        column["name"]: column
        for column in inspector.get_columns(table.name, schema=schema)
    }
    for column in table.columns:
        actual = reflected.get(column.name)
        if actual is None:
            problems.append(f"{table.name}: missing column {column.name}")
            continue
        if bool(actual["nullable"]) != bool(column.nullable):
            problems.append(
                f"{table.name}.{column.name}: nullable is {actual['nullable']}, "
                f"expected {column.nullable}"
            )
        if _type_signature(actual["type"]) != _type_signature(column.type):
            problems.append(
                f"{table.name}.{column.name}: type {actual['type']} does not match "
                f"{column.type}"
            )
    return len(table.columns)


def _verify_constraints(
    inspector,
    table,
    schema: str,
    problems: list[str],
) -> tuple[int, int, int, int]:
    primary_keys = [
        constraint
        for constraint in table.constraints
        if isinstance(constraint, PrimaryKeyConstraint)
    ]
    reflected_primary_key = inspector.get_pk_constraint(table.name, schema=schema)
    for constraint in primary_keys:
        expected = _column_names(constraint.columns)
        actual = tuple(reflected_primary_key.get("constrained_columns") or ())
        if actual != expected:
            problems.append(
                f"{table.name}: primary key columns {actual} do not match {expected}"
            )

    expected_foreign_keys = {
        _foreign_key_signature(constraint)
        for constraint in table.constraints
        if isinstance(constraint, ForeignKeyConstraint)
    }
    actual_foreign_keys = {
        _reflected_foreign_key_signature(foreign_key)
        for foreign_key in inspector.get_foreign_keys(table.name, schema=schema)
    }
    for missing in sorted(expected_foreign_keys - actual_foreign_keys, key=str):
        problems.append(f"{table.name}: missing foreign key {missing}")

    expected_unique = {
        _column_names(constraint.columns)
        for constraint in table.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    actual_unique = {
        tuple(constraint.get("column_names") or ())
        for constraint in inspector.get_unique_constraints(table.name, schema=schema)
    }
    for missing in sorted(expected_unique - actual_unique):
        problems.append(f"{table.name}: missing unique constraint on {missing}")

    expected_checks = {
        constraint.name
        for constraint in table.constraints
        if isinstance(constraint, CheckConstraint)
    }
    actual_checks = {
        constraint.get("name")
        for constraint in inspector.get_check_constraints(table.name, schema=schema)
    }
    for missing in sorted(expected_checks - actual_checks):
        problems.append(f"{table.name}: missing check constraint {missing}")

    return (
        len(primary_keys),
        len(expected_foreign_keys),
        len(expected_unique),
        len(expected_checks),
    )


def _verify_indexes(inspector, table, schema: str, problems: list[str]) -> int:
    reflected = {
        index["name"]: index
        for index in inspector.get_indexes(table.name, schema=schema)
        if not index.get("duplicates_constraint")
    }
    for index in table.indexes:
        actual = reflected.get(index.name)
        if actual is None:
            problems.append(f"{table.name}: missing index {index.name}")
            continue
        if bool(actual.get("unique")) != bool(index.unique):
            problems.append(
                f"{table.name}.{index.name}: unique is {actual.get('unique')}, "
                f"expected {index.unique}"
            )
        _verify_plain_index_columns(table.name, index, actual, problems)
    return len(table.indexes)


def _verify_plain_index_columns(
    table_name: str,
    index: Index,
    reflected: dict[str, object],
    problems: list[str],
) -> None:
    """Compare ordinary index columns; Alembic checks expression definitions."""

    expected = tuple(
        expression.name
        for expression in index.expressions
        if getattr(expression, "table", None) is not None
    )
    if len(expected) != len(index.expressions):
        return
    actual = tuple(reflected.get("column_names") or ())
    if actual != expected:
        problems.append(
            f"{table_name}.{index.name}: columns {actual} do not match {expected}"
        )


def verify_schema(
    connection: Connection,
    metadata: MetaData,
    *,
    schema: str = "public",
) -> SchemaVerificationReport:
    """Verify required tables and their structural objects without changing data."""

    inspector = inspect(connection)
    expected_tables = {table.name: table for table in metadata.sorted_tables}
    actual_tables = set(inspector.get_table_names(schema=schema))
    missing_tables = sorted(set(expected_tables) - actual_tables)
    problems = [f"missing table {table}" for table in missing_tables]

    counts = {
        "columns": 0,
        "primary_keys": 0,
        "foreign_keys": 0,
        "unique_constraints": 0,
        "check_constraints": 0,
        "indexes": 0,
    }
    for name, table in expected_tables.items():
        if name not in actual_tables:
            continue
        counts["columns"] += _verify_columns(inspector, table, schema, problems)
        primary, foreign, unique, checks = _verify_constraints(
            inspector, table, schema, problems
        )
        counts["primary_keys"] += primary
        counts["foreign_keys"] += foreign
        counts["unique_constraints"] += unique
        counts["check_constraints"] += checks
        counts["indexes"] += _verify_indexes(inspector, table, schema, problems)

    if problems:
        raise SchemaVerificationError(
            "Database schema does not match the current ORM:\n- "
            + "\n- ".join(problems)
        )

    return SchemaVerificationReport(tables=len(expected_tables), **counts)
