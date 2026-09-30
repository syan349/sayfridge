"""Offline contract test for the live deployment smoke runner."""
from __future__ import annotations

from datetime import date
from uuid import uuid4

import httpx
import pytest

from scripts.smoke_deployment import SmokeConfig, SmokeFailure, run_smoke




def test_smoke_flow_is_repeatable_without_duplicate_business_resources():
    user_email = "deployment-smoke@example.com"
    admin_email = "deployment-admin@example.com"
    ids = {name: str(uuid4()) for name in ("user", "space", "category", "definition", "item")}
    state = {"registered": False, "space": None, "definition": None, "item": None}
    creations = {"space": 0, "definition": 0, "item": 0}

    def response(status: int, body: dict) -> httpx.Response:
        return httpx.Response(status, json=body)

    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        params = request.url.params
        if path == "/health":
            return response(200, {"status": "ok", "service": "sayfridge-backend"})
        if path == "/api/v1/system/version":
            return response(
                200,
                {
                    "service": "sayfridge-backend",
                    "version": "0.1.0",
                    "commit_sha": "0123456789abcdef0123456789abcdef01234567",
                },
            )
        if path == "/api/v1/auth/register":
            if state["registered"]:
                return response(409, {"detail": "Email is already registered"})
            state["registered"] = True
            return response(201, {"id": ids["user"], "email": user_email})
        if path == "/api/v1/auth/login":
            email = request.read().decode()
            token = "admin-token" if admin_email in email else "user-token"
            return response(200, {"access_token": token})
        if path == "/api/v1/auth/me":
            return response(200, {"email": user_email})
        if path == "/api/v1/storage-spaces" and request.method == "GET":
            return response(200, {"items": [state["space"]] if state["space"] else []})
        if path == "/api/v1/storage-spaces" and request.method == "POST":
            creations["space"] += 1
            state["space"] = {
                "id": ids["space"],
                "name": "Deployment Smoke Pantry",
                "status": "ACTIVE",
            }
            return response(201, state["space"])
        if path == "/api/v1/item-categories":
            return response(200, {"items": [{"id": ids["category"]}]})
        if path == "/api/v1/item-definitions" and request.method == "GET":
            return response(200, {"items": [state["definition"]] if state["definition"] else []})
        if path == "/api/v1/item-definitions" and request.method == "POST":
            creations["definition"] += 1
            state["definition"] = {
                "id": ids["definition"],
                "name": "Deployment Smoke Item",
                "scope": "PRIVATE",
                "status": "ACTIVE",
            }
            return response(201, state["definition"])
        if path == "/api/v1/inventory-items" and request.method == "GET":
            return response(200, {"items": [state["item"]] if state["item"] else []})
        if path == "/api/v1/inventory-items" and request.method == "POST":
            creations["item"] += 1
            state["item"] = {
                "id": ids["item"],
                "item_definition_id": ids["definition"],
            }
            return response(201, state["item"])
        if path == f"/api/v1/inventory-items/{ids['item']}":
            return response(200, state["item"])
        if path == "/api/v1/inventory-items/expiry-summary":
            assert params["as_of"] == "2026-09-28"
            return response(200, {"items": [state["item"]]})
        if path == "/api/v1/admin/users":
            assert request.headers["Authorization"] == "Bearer admin-token"
            return response(200, {"items": [{"email": user_email}]})
        return response(404, {"detail": f"Unhandled test route: {request.method} {path}"})

    config = SmokeConfig(
        base_url="https://backend.example.test",
        user_email=user_email,
        user_password="user-password",
        admin_email=admin_email,
        admin_password="admin-password",
    )
    transport = httpx.MockTransport(handler)
    run_smoke(config, transport=transport, today=date(2026, 9, 28))
    run_smoke(config, transport=transport, today=date(2026, 9, 28))
    assert creations == {"space": 1, "definition": 1, "item": 1}


def test_smoke_configuration_requires_https_and_all_credentials(monkeypatch):
    for name in (
        "SMOKE_BASE_URL",
        "SMOKE_USER_EMAIL",
        "SMOKE_USER_PASSWORD",
        "SMOKE_ADMIN_EMAIL",
        "SMOKE_ADMIN_PASSWORD",
    ):
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(SmokeFailure, match="Missing smoke-test configuration"):
        SmokeConfig.from_environment()

    monkeypatch.setenv("SMOKE_USER_EMAIL", "user@example.com")
    monkeypatch.setenv("SMOKE_USER_PASSWORD", "password")
    monkeypatch.setenv("SMOKE_ADMIN_EMAIL", "admin@example.com")
    monkeypatch.setenv("SMOKE_ADMIN_PASSWORD", "password")
    with pytest.raises(SmokeFailure, match="must be an HTTPS origin"):
        SmokeConfig.from_environment("http://backend.example.com")
