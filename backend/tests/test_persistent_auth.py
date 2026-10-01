"""Real database checks for refresh rotation, revocation and session limits."""
from datetime import datetime, timedelta, timezone
import jwt
import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.db.models import AuthSession, RefreshCredential, User
from auth_test_support import make_user, seed_users, request, VALID_PASSWORD

pytestmark = pytest.mark.postgres


def login(database):
    seed_users(database, make_user())
    result = request(database, "POST", "/api/v1/auth/login", json={"email": "user@example.com", "password": VALID_PASSWORD})
    assert result.status_code == 200, result.text
    return result.json()


def refresh(database, data):
    return request(database, "POST", "/api/v1/auth/refresh", json={"refresh_token": data["refresh_token"]})


def me(database, data):
    return request(database, "GET", "/api/v1/auth/me", headers={"Authorization": "Bearer " + data["access_token"]})


@pytest.mark.ci
def test_rotation_and_logout_revoke_access(database):
    first = login(database)
    second = refresh(database, first)
    assert second.status_code == 200
    second = second.json()
    assert second["refresh_token"] != first["refresh_token"]
    assert me(database, second).status_code == 200
    with Session(database[2]) as db:
        rows = list(db.scalars(select(RefreshCredential)))
        assert len(rows) == 2
        assert all(first["refresh_token"] != row.token_hash for row in rows)
    assert request(database, "POST", "/api/v1/auth/logout", json={"refresh_token": second["refresh_token"]}).status_code == 204
    assert me(database, first).status_code == 401
    assert me(database, second).status_code == 401
    assert refresh(database, second).status_code == 401
    assert request(database, "POST", "/api/v1/auth/logout", json={"refresh_token": second["refresh_token"]}).status_code == 204


def test_replayed_refresh_revokes_entire_family(database):
    first = login(database)
    second = refresh(database, first).json()
    third = refresh(database, second).json()
    assert refresh(database, first).status_code == 401
    assert refresh(database, third).status_code == 401
    assert me(database, third).status_code == 401


@pytest.mark.parametrize("limit", ["expires_at", "absolute_expires_at"])
def test_session_deadlines_require_login(database, limit):
    data = login(database)
    with Session(database[2]) as db:
        session = db.scalar(select(AuthSession))
        setattr(session, limit, datetime.now(timezone.utc) - timedelta(seconds=1))
        db.commit()
    assert me(database, data).status_code == 401
    assert refresh(database, data).status_code == 401


def test_sliding_expiry_never_exceeds_absolute_deadline(database):
    data = login(database)
    with Session(database[2]) as db:
        session = db.scalar(select(AuthSession))
        session.absolute_expires_at = datetime.now(timezone.utc) + timedelta(days=1)
        db.commit()
    assert refresh(database, data).status_code == 200
    with Session(database[2]) as db:
        session = db.scalar(select(AuthSession))
        assert session.expires_at == session.absolute_expires_at


def test_disabled_account_cannot_refresh(database):
    data = login(database)
    with Session(database[2]) as db:
        user = db.scalar(select(User))
        user.status = "DISABLED"
        db.commit()
    assert refresh(database, data).status_code == 401
    assert me(database, data).status_code == 401


def test_expired_access_can_be_renewed(database):
    data = login(database)
    claims = jwt.decode(data["access_token"], "s" * 40, algorithms=["HS256"])
    claims["exp"] = int(datetime.now(timezone.utc).timestamp()) - 1
    data["access_token"] = jwt.encode(claims, "s" * 40, algorithm="HS256")
    assert me(database, data).status_code == 401
    renewed = refresh(database, data)
    assert renewed.status_code == 200
    assert me(database, renewed.json()).status_code == 200


def test_unknown_refresh_is_rejected_without_disclosing_account(database):
    assert refresh(database, {"refresh_token": "x" * 64}).status_code == 401
    assert request(database, "POST", "/api/v1/auth/refresh", json={"refresh_token": "short"}).status_code == 422


def test_logging_out_one_device_preserves_another(database):
    first = login(database)
    second = request(database, "POST", "/api/v1/auth/login", json={"email": "user@example.com", "password": VALID_PASSWORD}).json()
    assert request(database, "POST", "/api/v1/auth/logout", json={"refresh_token": first["refresh_token"]}).status_code == 204
    assert me(database, second).status_code == 200
    assert refresh(database, second).status_code == 200


def test_simultaneous_refresh_detects_reuse(database):
    import asyncio
    from auth_test_support import exercise
    data = login(database)
    async def scenario(client, sessions):
        results = await asyncio.gather(*[
            client.post("/api/v1/auth/refresh", json={"refresh_token": data["refresh_token"]})
            for _ in range(2)
        ])
        assert sorted(result.status_code for result in results) == [200, 401]
        winner = next(result.json() for result in results if result.status_code == 200)
        result = await client.get("/api/v1/auth/me", headers={"Authorization": "Bearer " + winner["access_token"]})
        assert result.status_code == 401
    asyncio.run(exercise(database, scenario))
