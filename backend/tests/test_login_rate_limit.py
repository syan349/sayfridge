"""Database-free unit and HTTP tests for the process-local login guardrail."""

import asyncio

import httpx
import pytest

from app.api.routes import auth as auth_routes
from app.core.config import get_settings
from app.core.login_rate_limit import LoginRateLimiter
from app.db.session import get_db_session
from app.main import app


pytestmark = pytest.mark.ci


def test_login_limit_is_scoped_clearable_and_expires() -> None:
    limiter = LoginRateLimiter()
    first = limiter.key("192.0.2.1", "user@example.com")
    other_account = limiter.key("192.0.2.1", "other@example.com")

    assert limiter.reserve(
        first, maximum_attempts=2, window_seconds=60, now=100
    ).allowed
    assert limiter.reserve(
        first, maximum_attempts=2, window_seconds=60, now=101
    ).allowed
    blocked = limiter.reserve(
        first, maximum_attempts=2, window_seconds=60, now=102
    )
    assert not blocked.allowed and blocked.retry_after_seconds == 58
    assert limiter.reserve(
        other_account, maximum_attempts=2, window_seconds=60, now=102
    ).allowed

    limiter.clear(first)
    assert limiter.reserve(
        first, maximum_attempts=2, window_seconds=60, now=103
    ).allowed
    assert limiter.reserve(
        other_account, maximum_attempts=2, window_seconds=60, now=163
    ).allowed


def test_login_endpoint_returns_429_with_retry_after(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The HTTP endpoint applies the guard before another authentication attempt."""

    async def no_user(*_args, **_kwargs):
        return None

    async def unused_session():
        yield object()

    monkeypatch.setattr(auth_routes, "authenticate_user", no_user)
    monkeypatch.setattr(auth_routes, "login_rate_limiter", LoginRateLimiter())
    settings = get_settings().model_copy(
        update={
            "login_rate_limit_attempts": 2,
            "login_rate_limit_window_seconds": 60,
        }
    )
    previous_settings = app.dependency_overrides.get(get_settings)
    previous_session = app.dependency_overrides.get(get_db_session)
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_db_session] = unused_session

    async def exercise() -> list[httpx.Response]:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            return [
                await client.post(
                    "/api/v1/auth/login",
                    json={"email": "limited@example.com", "password": "p" * 16},
                )
                for _ in range(3)
            ]

    try:
        responses = asyncio.run(exercise())
    finally:
        for dependency, previous in (
            (get_settings, previous_settings),
            (get_db_session, previous_session),
        ):
            if previous is None:
                app.dependency_overrides.pop(dependency, None)
            else:
                app.dependency_overrides[dependency] = previous

    assert [response.status_code for response in responses] == [401, 401, 429]
    assert responses[-1].json() == {
        "detail": "Too many login attempts; try again later"
    }
    assert 1 <= int(responses[-1].headers["retry-after"]) <= 60
