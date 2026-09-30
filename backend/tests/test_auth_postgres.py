"""PostgreSQL lifecycle, concurrent registration, and transaction regression tests."""
import asyncio

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.services import auth
from app.core.security import verify_password
from auth_test_support import exercise

pytestmark = pytest.mark.postgres


@pytest.mark.ci
def test_register_login_me_database_lifecycle(database):
    async def scenario(client, sessions):
        payload = {"email": " User@Example.COM ", "password": "PostmanDemo42!"}
        register = await client.post("/api/v1/auth/register", json=payload)
        assert register.status_code == 201
        user = register.json()
        assert set(user) == {"id", "email", "role", "status", "created_at"}
        assert user["email"] == "user@example.com" and user["role"] == "USER"
        async with sessions() as s:
            row = (await s.execute(text('SELECT password_hash, auth_provider FROM "user"'))).one()
            assert row.auth_provider == "LOCAL" and verify_password(payload["password"], row.password_hash)
            space = (
                await s.execute(
                    text(
                        "SELECT name, type, status FROM storage_space "
                        "WHERE user_id = :user_id"
                    ),
                    {"user_id": user["id"]},
                )
            ).one()
            assert space.name == "Default Space"
            assert space.type == "FRIDGE"
            assert space.status == "ACTIVE"
        assert (await client.post("/api/v1/auth/register", json=payload)).status_code == 409
        login = await client.post("/api/v1/auth/login", json=payload)
        assert login.status_code == 200 and login.json()["expires_in"] == 900
        headers = {"Authorization": "Bearer " + login.json()["access_token"]}
        assert (await client.get("/api/v1/auth/me", headers=headers)).json() == user
        wrong = await client.post("/api/v1/auth/login", json={**payload, "password": "wrong-pass"})
        missing = await client.post("/api/v1/auth/login", json={**payload, "email": "missing@example.com"})
        assert wrong.status_code == missing.status_code == 401 and wrong.json() == missing.json()
        async with sessions() as s:
            await s.execute(text('UPDATE "user" SET role=:role'), {"role": "ADMIN"})
            await s.commit()
        assert (await client.get("/api/v1/auth/me", headers=headers)).json()["role"] == "ADMIN"
        for status in ["SUSPENDED", "DISABLED"]:
            async with sessions() as s:
                await s.execute(text('UPDATE "user" SET status=:status'), {"status": status})
                await s.commit()
            assert (await client.get("/api/v1/auth/me", headers=headers)).status_code == 401
            assert (await client.post("/api/v1/auth/login", json=payload)).status_code == 401
        async with sessions() as s:
            await s.execute(text('DELETE FROM "user"'))
            await s.commit()
        assert (await client.get("/api/v1/auth/me", headers=headers)).status_code == 401
    asyncio.run(exercise(database, scenario))


def test_concurrent_registration_has_one_winner(database, monkeypatch):
    lookup = auth.get_user_by_email
    async def scenario(client, sessions):
        barrier = asyncio.Barrier(2)
        async def simultaneous_lookup(session, email):
            result = await lookup(session, email)
            await asyncio.wait_for(barrier.wait(), timeout=30)
            return result
        monkeypatch.setattr(auth, "get_user_by_email", simultaneous_lookup)
        body = {"email": "race@example.com", "password": "PostmanDemo42!"}
        responses = await asyncio.gather(*(client.post("/api/v1/auth/register", json=body) for _ in range(2)))
        assert sorted(r.status_code for r in responses) == [201, 409]
        async with sessions() as s:
            assert (await s.execute(text('SELECT count(*) FROM "user"'))).scalar_one() == 1
    asyncio.run(exercise(database, scenario))


def test_unrelated_constraint_is_not_reported_as_duplicate(database):
    with database[2].begin() as conn:
        conn.execute(text("""ALTER TABLE "user" ADD CONSTRAINT reject_fixture_email CHECK (email <> 'blocked@example.com')"""))
    async def scenario(client, sessions):
        async with sessions() as session:
            with pytest.raises(IntegrityError):
                await auth.register_user(session, "blocked@example.com", "PostmanDemo42!")
            assert (await session.execute(text('SELECT count(*) FROM "user"'))).scalar_one() == 0
            # A new write succeeds after rollback, proving the session is usable.
            user = await auth.register_user(session, "allowed@example.com", "PostmanDemo42!")
            assert user.email == "allowed@example.com"
    asyncio.run(exercise(database, scenario))
