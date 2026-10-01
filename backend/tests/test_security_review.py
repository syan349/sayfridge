"""Focused 8.1–8.3 security probes; synthetic data, no live model or deployment."""
import asyncio
import base64
import re
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import httpx
import jwt
from pydantic import SecretStr
from sqlalchemy.exc import StatementError
import pytest

from app.api.dependencies import get_current_user
from app.core.config import get_settings
from app.db.session import engine, get_db_session
from app.main import app
from app.schemas.agent_media import MAX_IMAGE_BYTES, MAX_REQUEST_BYTES
from agent_image_support import image_input

ORIGIN = "http://localhost:5173"


@pytest.fixture
def schema_client():
    # Bypass identity only for upload/schema probes; no database/model can be used.
    previous = dict(app.dependency_overrides)
    app.dependency_overrides[get_current_user] = lambda: object()
    async def no_database():
        yield object()
    app.dependency_overrides[get_db_session] = no_database
    yield
    app.dependency_overrides.clear()
    app.dependency_overrides.update(previous)


def send(method, path, **kwargs):
    async def scenario():
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app, raise_app_exceptions=False),
            base_url="http://test",
        ) as client:
            return await client.request(method, path, **kwargs)
    return asyncio.run(scenario())


@pytest.mark.parametrize("claim,value", [
    ("iat", None), ("iat", {}), ("exp", None), ("exp", []),
    ("nbf", None), ("exp", float("inf")),
])
def test_malformed_signed_numeric_claim_returns_401(claim, value):
    # Signed malformed claims model a corrupt/legacy issuer, not a forged signature.
    now = datetime.now(timezone.utc)
    claims = {"sub": str(uuid4()), "type": "access", "iat": now,
              "exp": now + timedelta(minutes=15), claim: value}
    token = jwt.encode(claims, get_settings().jwt_secret_key.get_secret_value(), algorithm="HS256")
    response = send("GET", "/api/v1/auth/me", headers={"Authorization": "Bearer " + token})
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert token not in response.text


@pytest.mark.parametrize("claim", ["sub", "type", "iat", "exp"])
def test_missing_required_token_claim_is_rejected(claim):
    now = datetime.now(timezone.utc)
    claims = {"sub": str(uuid4()), "type": "access", "iat": now,
              "exp": now + timedelta(minutes=15)}
    claims.pop(claim)
    token = jwt.encode(claims, get_settings().jwt_secret_key.get_secret_value(), algorithm="HS256")
    assert send("GET", "/api/v1/auth/me", headers={"Authorization": "Bearer " + token}).status_code == 401


@pytest.mark.parametrize("algorithm", ["none", "HS384"])
@pytest.mark.ci
def test_unapproved_jwt_algorithm_is_rejected(algorithm, monkeypatch):
    monkeypatch.setattr(get_settings(), "jwt_secret_key", SecretStr("s" * 64))
    now = datetime.now(timezone.utc)
    claims = {"sub": str(uuid4()), "type": "access", "iat": now,
              "exp": now + timedelta(minutes=15)}
    key = "" if algorithm == "none" else get_settings().jwt_secret_key.get_secret_value()
    token = jwt.encode(claims, key, algorithm=algorithm)
    assert send("GET", "/api/v1/auth/me", headers={"Authorization": "Bearer " + token}).status_code == 401


@pytest.mark.parametrize("case", [pytest.param("svg", marks=pytest.mark.ci), "mime_mismatch", "fake_png", "filename", "url", "oversize", "too_many"])
def test_untrusted_uploads_are_rejected_without_echo(schema_client, case):
    image = image_input().model_dump(mode="json")
    sentinel = "PRIVATE_UPLOAD_SENTINEL"
    if case == "svg":
        image.update(mime_type="image/svg+xml", data_base64=base64.b64encode(b"<svg onload='alert(1)'/>").decode())
    elif case == "mime_mismatch":
        image["mime_type"] = "image/jpeg"
    elif case == "fake_png":
        image["data_base64"] = base64.b64encode(sentinel.encode()).decode()
    elif case == "filename":
        image["filename"] = "../../" + sentinel + ".png"
    elif case == "url":
        image["url"] = "http://169.254.169.254/" + sentinel
    elif case == "oversize":
        image["data_base64"] = base64.b64encode(b"x" * (MAX_IMAGE_BYTES + 1)).decode()
    images = [image] if case != "too_many" else [dict(image, image_id=str(uuid4())) for _ in range(5)]
    response = send("POST", "/api/v1/agent/chat", json={"message": sentinel, "images": images}, headers={"Origin": ORIGIN})
    assert response.status_code == 422
    assert response.headers["access-control-allow-origin"] == ORIGIN
    assert sentinel not in response.text
    assert image["data_base64"] not in response.text


@pytest.mark.parametrize("path", ["/api/v1/agent/chat", "/api/v1/agent/resume"])
def test_declared_oversized_body_is_rejected_with_cors(path):
    response = send("POST", path, headers={"Content-Length": str(MAX_REQUEST_BYTES + 1), "Origin": ORIGIN})
    assert response.status_code == 413
    assert response.headers["access-control-allow-origin"] == ORIGIN


@pytest.mark.ci
def test_chunked_oversized_body_is_rejected_with_cors():
    async def scenario():
        async def chunks():
            for _ in range(13):
                yield b"x" * 1024 * 1024
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
            r = await client.post("/api/v1/agent/chat", content=chunks(), headers={"Origin": ORIGIN})
            assert r.status_code == 413
            assert r.headers["access-control-allow-origin"] == ORIGIN
    asyncio.run(scenario())


@pytest.mark.parametrize("changes", [{"message": "X" * 8001}, {"conversation_id": "not-a-uuid"}, {"request_id": "not-a-uuid"}])
def test_agent_bad_identifiers_and_long_text_are_rejected(schema_client, changes):
    response = send("POST", "/api/v1/agent/chat", json={"message": "PRIVATE_TEXT_SENTINEL", **changes})
    assert response.status_code == 422
    assert "PRIVATE_TEXT_SENTINEL" not in response.text
    assert "X" * 100 not in response.text


PROTECTED_ROUTES = [
    (method.upper(), path)
    for path, operations in app.openapi()["paths"].items()
    if path.startswith("/api/v1/") and path not in {
        "/api/v1/auth/login", "/api/v1/auth/register", "/api/v1/system/version",
        "/api/v1/auth/refresh", "/api/v1/auth/logout"
    }
    for method in operations if method in {"get", "post", "patch", "put", "delete"}
]


@pytest.mark.parametrize("method,path", PROTECTED_ROUTES)
def test_every_protected_route_rejects_missing_identity(method, path):
    concrete = re.sub(r"\{[^}]+\}", str(uuid4()), path)
    response = send(method, concrete)
    assert response.status_code == 401, (method, path, response.text)


@pytest.mark.ci
def test_sql_exception_representation_hides_bound_private_data():
    # Drivers/ASGI servers may log SQLAlchemy exception text on an unhandled error.
    error = StatementError("execution failed", "INSERT INTO users VALUES (:email)",
                           {"email": "PRIVATE_SQL_SENTINEL@example.com"}, RuntimeError(),
                           hide_parameters=engine.sync_engine.hide_parameters)
    assert "PRIVATE_SQL_SENTINEL" not in str(error)


@pytest.mark.parametrize("path", ["/api/v1/auth/refresh", "/api/v1/auth/logout"])
def test_refresh_endpoints_require_credentials_without_echoing_them(path):
    assert send("POST", path).status_code == 422
    response = send("POST", path, json={"refresh_token": "PRIVATE_REFRESH_SENTINEL"})
    assert response.status_code == 422
    assert "PRIVATE_REFRESH_SENTINEL" not in response.text
