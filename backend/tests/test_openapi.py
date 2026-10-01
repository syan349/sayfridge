"""Release-facing OpenAPI and deployed-version contracts."""

import asyncio

import httpx
import pytest

from app.core.config import get_settings
from app.main import app


pytestmark = pytest.mark.ci


def _operations(schema: dict):
    for path, path_item in schema["paths"].items():
        for method in ("get", "post", "patch", "put", "delete"):
            if method in path_item:
                yield path, method, path_item[method]


def test_openapi_is_complete_enough_for_interactive_acceptance() -> None:
    schema = app.openapi()

    assert schema["info"]["title"] == "SayFridge Backend"
    assert schema["info"]["version"] == get_settings().app_version
    assert {tag["name"] for tag in schema["tags"]} == {
        "system",
        "auth",
        "storage-spaces",
        "catalog",
        "inventory",
        "admin",
        "agent",
    }

    public_paths = {
        "/health",
        "/api/v1/system/version",
        "/api/v1/auth/register",
        "/api/v1/auth/login",
        "/api/v1/auth/refresh",
        "/api/v1/auth/logout",
    }
    for path, _method, operation in _operations(schema):
        assert operation.get("tags"), path
        assert operation.get("summary"), path
        assert operation.get("description"), path
        success_responses = [
            (code, response)
            for code, response in operation["responses"].items()
            if str(code).startswith("2")
        ]
        assert success_responses, path
        assert all(
            (str(code) == "204" and not response.get("content"))
            or any("schema" in media for media in response.get("content", {}).values())
            for code, response in success_responses
        ), path
        if path not in public_paths:
            unauthorized = operation["responses"].get("401", {})
            assert "schema" in unauthorized.get("content", {}).get(
                "application/json", {}
            ), path

    for path in ("/api/v1/auth/register", "/api/v1/auth/login"):
        operation = schema["paths"][path]["post"]
        assert "schema" in operation["requestBody"]["content"]["application/json"]
        assert "schema" in operation["responses"]["422"]["content"]["application/json"]

    body_operations = {
        (path, method)
        for path, method, operation in _operations(schema)
        if "requestBody" in operation
    }
    assert body_operations == {
        ("/api/v1/auth/register", "post"),
        ("/api/v1/auth/login", "post"),
        ("/api/v1/auth/refresh", "post"),
        ("/api/v1/auth/logout", "post"),
        ("/api/v1/storage-spaces", "post"),
        ("/api/v1/storage-spaces/{space_id}", "patch"),
        ("/api/v1/item-definitions", "post"),
        ("/api/v1/item-definitions/{definition_id}", "patch"),
        ("/api/v1/inventory-items", "post"),
        ("/api/v1/inventory-items/batch-create", "post"),
        ("/api/v1/inventory-items/batch-move", "post"),
        ("/api/v1/inventory-items/batch-archive", "post"),
        ("/api/v1/inventory-items/{item_id}", "patch"),
        ("/api/v1/inventory-items/{item_id}/operations", "post"),
        ("/api/v1/inventory-items/{item_id}/discard", "post"),
        ("/api/v1/inventory-items/{item_id}/archive", "post"),
        ("/api/v1/admin/users/{user_id}/status", "patch"),
        ("/api/v1/agent/chat", "post"),
        ("/api/v1/agent/resume", "post"),
    }
    for path, method in body_operations:
        operation = schema["paths"][path][method]
        assert "schema" in operation["requestBody"]["content"]["application/json"]
        assert "schema" in operation["responses"]["422"]["content"]["application/json"]

    assert "schema" in schema["paths"]["/api/v1/auth/login"]["post"][
        "responses"
    ]["429"]["content"]["application/json"]
    assert "schema" in schema["paths"]["/api/v1/inventory-items/{item_id}"][
        "get"
    ]["responses"]["404"]["content"]["application/json"]


def test_version_endpoint_exposes_safe_deployment_identity() -> None:
    settings = get_settings().model_copy(
        update={
            "app_version": "1.2.3",
            "app_commit_sha": "0123456789abcdef0123456789abcdef01234567",
        }
    )
    previous = app.dependency_overrides.get(get_settings)
    app.dependency_overrides[get_settings] = lambda: settings

    async def request_version() -> httpx.Response:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            return await client.get("/api/v1/system/version")

    try:
        response = asyncio.run(request_version())
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_settings, None)
        else:
            app.dependency_overrides[get_settings] = previous

    assert response.status_code == 200
    assert response.json() == {
        "service": "sayfridge-backend",
        "version": "1.2.3",
        "commit_sha": "0123456789abcdef0123456789abcdef01234567",
    }
