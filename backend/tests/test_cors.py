import asyncio

import httpx
import pytest

from app.main import app


WEB_ORIGIN = "http://localhost:5173"


def _request(method: str, path: str, *, headers: dict[str, str]) -> httpx.Response:
    async def send() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            return await client.request(method, path, headers=headers)

    return asyncio.run(send())


def test_configured_web_origin_receives_cors_header() -> None:
    response = _request("GET", "/health", headers={"Origin": WEB_ORIGIN})

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == WEB_ORIGIN
    assert "access-control-allow-credentials" not in response.headers


def test_preflight_allows_configured_method_and_headers() -> None:
    response = _request(
        "OPTIONS",
        "/api/v1/inventory-items/example/operations",
        headers={
            "Origin": WEB_ORIGIN,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": (
                "Authorization, Content-Type, Idempotency-Key"
            ),
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == WEB_ORIGIN
    allowed_methods = {
        value.strip()
        for value in response.headers["access-control-allow-methods"].split(",")
    }
    assert allowed_methods == {"GET", "POST", "PATCH", "OPTIONS"}
    allowed_headers = response.headers["access-control-allow-headers"].lower()
    for header in ("authorization", "content-type", "idempotency-key"):
        assert header in allowed_headers


@pytest.mark.ci
@pytest.mark.parametrize("path", ["/api/v1/agent/chat", "/api/v1/agent/resume"])
def test_preflight_allows_inventory_card_requests(path: str) -> None:
    response = _request(
        "OPTIONS",
        path,
        headers={
            "Origin": WEB_ORIGIN,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": (
                "authorization,content-type,x-sayfridge-inventory-cards"
            ),
        },
    )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == WEB_ORIGIN
    assert "x-sayfridge-inventory-cards" in response.headers[
        "access-control-allow-headers"
    ].lower()


@pytest.mark.ci
def test_agent_preflight_still_rejects_unconfigured_headers() -> None:
    response = _request(
        "OPTIONS",
        "/api/v1/agent/resume",
        headers={
            "Origin": WEB_ORIGIN,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,x-unapproved-header",
        },
    )

    assert response.status_code == 400
    assert "Disallowed CORS headers" in response.text


def test_unconfigured_origin_is_not_allowed() -> None:
    response = _request(
        "GET",
        "/health",
        headers={"Origin": "http://localhost:3000"},
    )

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


def test_unconfigured_origin_preflight_is_rejected() -> None:
    response = _request(
        "OPTIONS",
        "/health",
        headers={
            "Origin": "https://untrusted.example.com",
            "Access-Control-Request-Method": "GET",
        },
    )

    assert response.status_code == 400
    assert "access-control-allow-origin" not in response.headers
