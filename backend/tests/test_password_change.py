"""Password change contract, isolation and real PostgreSQL transactions."""
import asyncio
import json
from datetime import datetime, timezone
import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import create_access_token, verify_password
from app.db.models import AuthSession, User
from auth_test_support import make_user, seed_users, request, exercise, VALID_PASSWORD

pytestmark = [pytest.mark.postgres, pytest.mark.ci]
PATH = "/api/v1/auth/change-password"
NEW = "New password 2026!"


def signin(database, email="user@example.com", password=VALID_PASSWORD):
    return request(database, "POST", "/api/v1/auth/login", json={"email": email, "password": password})


def headers(data):
    return {"Authorization": "Bearer " + data["access_token"]}


@pytest.fixture
def account(database):
    user = make_user()
    seed_users(database, user)
    return user, signin(database).json()


def change(database, data, current=VALID_PASSWORD, new=NEW, **extra):
    return request(database, "POST", PATH, headers=headers(data),
                   json={"current_password": current, "new_password": new, **extra})


def assert_revoked(database, data):
    assert request(database, "GET", "/api/v1/auth/me", headers=headers(data)).status_code == 401
    assert request(database, "POST", "/api/v1/auth/refresh", json={"refresh_token": data["refresh_token"]}).status_code == 401


def test_change_revokes_every_device_preserves_other_user_and_data(database, account, caplog):
    user, first = account
    second = signin(database).json()
    other = make_user(email="other@example.com")
    seed_users(database, other)
    other_session = signin(database, other.email).json()
    with Session(database[2]) as db:
        old_hash = db.get(User, user.id).password_hash
    caplog.set_level("INFO", logger="app.security.audit")
    result = change(database, first)
    assert result.status_code == 204, result.text
    assert result.content == b""
    assert result.headers["cache-control"] == "no-store"
    with Session(database[2]) as db:
        updated = db.get(User, user.id)
        assert updated.password_hash != old_hash
        assert verify_password(NEW, updated.password_hash)
        assert not verify_password(VALID_PASSWORD, updated.password_hash)
        assert updated.email == user.email and updated.role == "USER"
        assert all(s.revoked_at for s in db.scalars(select(AuthSession).where(AuthSession.user_id == user.id)))
    assert_revoked(database, first)
    assert_revoked(database, second)
    assert signin(database).status_code == 401
    assert signin(database, password=NEW).status_code == 200
    assert request(database, "GET", "/api/v1/auth/me", headers=headers(other_session)).status_code == 200
    assert "password_changed" in caplog.text
    for secret in (VALID_PASSWORD, NEW, old_hash, first["access_token"], first["refresh_token"]):
        assert secret not in caplog.text


def test_wrong_current_password_keeps_credentials_and_does_not_return_401(database, account, caplog):
    _, data = account
    result = change(database, data, current="Incorrect old password")
    assert result.status_code == 400
    assert result.json()["detail"]["code"] == "CURRENT_PASSWORD_INCORRECT"
    assert request(database, "GET", "/api/v1/auth/me", headers=headers(data)).status_code == 200
    assert signin(database).status_code == 200
    assert "Incorrect old password" not in result.text + caplog.text


@pytest.mark.parametrize("new", ["", "zQ7!", "a" * 129, VALID_PASSWORD])
def test_invalid_new_password_is_rejected_without_echo(database, account, new):
    result = change(database, account[1], new=new)
    assert result.status_code == 422
    assert "input" not in result.text
    assert VALID_PASSWORD not in result.text
    if new: assert new not in result.text


@pytest.mark.parametrize("new", ["x" * 8, "x" * 128, "  a password with spaces  "])
def test_password_boundaries_and_spaces_are_preserved(database, account, new):
    assert change(database, account[1], new=new).status_code == 204
    assert signin(database, password=new).status_code == 200
    if new != new.strip(): assert signin(database, password=new.strip()).status_code == 401


def test_cannot_choose_a_different_target_user(database, account):
    assert change(database, account[1], user_id=str(uuid.uuid4())).status_code == 422
    assert signin(database).status_code == 200


def test_missing_auth_is_rejected(database):
    result = request(database, "POST", PATH, json={"current_password": VALID_PASSWORD, "new_password": NEW})
    assert result.status_code == 401


@pytest.mark.parametrize("state", ["SUSPENDED", "DISABLED", "nonlocal", "revoked"])
def test_unavailable_identity_cannot_change_password(database, account, state):
    user, data = account
    with Session(database[2]) as db:
        if state == "revoked":
            db.scalar(select(AuthSession).where(AuthSession.user_id == user.id)).revoked_at = datetime.now(timezone.utc)
        elif state == "nonlocal": db.get(User, user.id).auth_provider = "EXTERNAL"
        else: db.get(User, user.id).status = state
        db.commit()
    result = change(database, data)
    assert result.status_code == (403 if state == "nonlocal" else 401)
    with Session(database[2]) as db:
        assert verify_password(VALID_PASSWORD, db.get(User, user.id).password_hash)


def test_access_without_session_id_is_no_longer_accepted(database, account):
    token = create_access_token(account[0].id, get_settings().jwt_secret_key, 15)
    assert request(database, "GET", "/api/v1/auth/me", headers={"Authorization": "Bearer " + token}).status_code == 401


def test_change_password_is_throttled_separately_from_login(database, account):
    data = account[1]
    results = [change(database, data, current="Wrong old password") for _ in range(6)]
    assert [r.status_code for r in results[:5]] == [400] * 5
    assert results[-1].status_code == 429
    assert int(results[-1].headers["retry-after"]) > 0
    assert signin(database).status_code == 200


def test_failure_to_commit_rolls_back_password_and_revocation(database, account, monkeypatch):
    async def fail_password_commit(db):
        # Only the change request executes inside this patch. Force its pending
        # writes through SQL, then fail before COMMIT so rollback is observable.
        await db.flush()
        raise RuntimeError("simulated transaction failure")
    with monkeypatch.context() as patch:
        patch.setattr(AsyncSession, "commit", fail_password_commit)
        result = change(database, account[1])
        # SafeErrorsMiddleware converts unexpected server errors into HTTP 500.
        assert result.status_code == 500
        assert "simulated transaction failure" not in result.text
    assert signin(database).status_code == 200
    assert request(database, "GET", "/api/v1/auth/me", headers=headers(account[1])).status_code == 200


@pytest.mark.parametrize("competitor", ["change", "refresh", "login"])
def test_concurrent_credentials_do_not_survive_password_change(database, account, competitor):
    data = account[1]
    async def scenario(client, sessions):
        async def do_change(new=NEW):
            return await client.post(PATH, headers=headers(data), json={"current_password": VALID_PASSWORD, "new_password": new})
        if competitor == "change":
            results = await asyncio.gather(do_change(), do_change("Other new password"))
            assert sorted(x.status_code for x in results) in ([204, 400], [204, 401])
        else:
            operation = client.post("/api/v1/auth/refresh", json={"refresh_token": data["refresh_token"]}) if competitor == "refresh" else client.post("/api/v1/auth/login", json={"email":"user@example.com", "password":VALID_PASSWORD})
            changed, competing = await asyncio.gather(do_change(), operation)
            assert changed.status_code == 204
            assert competing.status_code in (200, 401)
            if competing.status_code == 200:
                old = competing.json()
                assert (await client.get("/api/v1/auth/me", headers=headers(old))).status_code == 401
                assert (await client.post("/api/v1/auth/refresh", json={"refresh_token":old["refresh_token"]})).status_code == 401
    asyncio.run(exercise(database, scenario))
