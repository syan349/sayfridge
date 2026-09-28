"""Guard the documented HTTP, schema, service and persistence boundaries."""
from __future__ import annotations

import ast
from pathlib import Path

import pytest


APP_DIR = Path(__file__).resolve().parents[1] / "app"
pytestmark = pytest.mark.ci


def python_files(directory: Path):
    return sorted(path for path in directory.glob("*.py") if path.name != "__init__.py")


def imported_modules(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    modules: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            modules.add(node.module)
    return modules


def test_schemas_do_not_depend_on_http_or_persistence_layers():
    violations = []
    forbidden = ("app.api", "app.db", "app.services", "fastapi", "sqlalchemy")
    for path in python_files(APP_DIR / "schemas"):
        imports = imported_modules(path)
        invalid = sorted(
            module for module in imports if module.startswith(forbidden)
        )
        if invalid:
            violations.append(f"{path.name}: {', '.join(invalid)}")
    assert not violations, "Schema layer imports forbidden modules: " + "; ".join(violations)


def test_services_do_not_depend_on_fastapi_or_routes():
    violations = []
    forbidden = ("app.api", "fastapi", "starlette.responses")
    for path in python_files(APP_DIR / "services"):
        imports = imported_modules(path)
        invalid = sorted(
            module for module in imports if module.startswith(forbidden)
        )
        if invalid:
            violations.append(f"{path.name}: {', '.join(invalid)}")
    assert not violations, "Service layer imports HTTP modules: " + "; ".join(violations)


def test_orm_does_not_depend_on_upper_layers():
    imports = imported_modules(APP_DIR / "db" / "models.py")
    forbidden = ("app.api", "app.schemas", "app.services", "fastapi", "pydantic")
    invalid = sorted(module for module in imports if module.startswith(forbidden))
    assert not invalid, "ORM imports upper-layer modules: " + ", ".join(invalid)


def test_routes_do_not_execute_queries_or_transactions():
    forbidden_methods = {
        "add",
        "commit",
        "delete",
        "execute",
        "flush",
        "refresh",
        "rollback",
        "scalar",
        "scalars",
    }
    violations = []
    for path in python_files(APP_DIR / "api" / "routes"):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        sql_imports = sorted(
            module
            for module in imported_modules(path)
            if module.startswith("sqlalchemy") and module != "sqlalchemy.ext.asyncio"
        )
        if sql_imports:
            violations.append(f"{path.name} imports {', '.join(sql_imports)}")
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr in forbidden_methods
            ):
                violations.append(f"{path.name}:{node.lineno} .{node.func.attr}()")
    assert not violations, "Route layer performs persistence work: " + "; ".join(violations)
