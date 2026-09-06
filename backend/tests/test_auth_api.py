import asyncio
from datetime import datetime, timezone
from typing import Any
import uuid

import httpx
import pytest

from app.core.config import get_settings
from app.core.security import create_access_token, hash_password
from app.db.models import User
from app.db.session import get_db_session
from app.main import app


VALID_PASSWORD = "p" * 16


class ScalarResult:
    def __init__(self, value: User | None) -> None:
        self.value = value

    def scalar_one_or_none(self) -> User | None:
        return self.value


class FakeAsyncSession:
    """只模拟认证服务使用的 AsyncSession 接口，测试期间不连接 Neon。"""

    def __init__(self, users: list[User] | None = None) -> None:
        self.users = {user.id: user for user in users or []}

    async def execute(self, statement: Any) -> ScalarResult:
        criterion = statement._where_criteria[0]
        field_name = criterion.left.key
        expected = criterion.right.value
        user = next(
            (
                candidate
                for candidate in self.users.values()
                if getattr(candidate, field_name) == expected
            ),
            None,
        )
        return ScalarResult(user)

    def add(self, user: User) -> None:
        now = datetime.now(timezone.utc)
        if user.id is None:
            user.id = uuid.uuid4()
        if user.created_at is None:
            user.created_at = now
        if user.updated_at is None:
            user.updated_at = now
        self.users[user.id] = user

    async def commit(self) -> None:
        return None

    async def rollback(self) -> None:
        return None

    async def refresh(self, user: User) -> None:
        return None


def make_user(
    *,
    email: str = "user@example.com",
    password: str = VALID_PASSWORD,
    status: str = "ACTIVE",
    role: str = "USER",
    auth_provider: str = "LOCAL",
) -> User:
    now = datetime.now(timezone.utc)
    return User(
        id=uuid.uuid4(),
        email=email,
        password_hash=hash_password(password),
        auth_provider=auth_provider,
        role=role,
        status=status,
        voice_limit_seconds=0,
        voice_used_seconds=0,
        created_at=now,
        updated_at=now,
    )


def request(
    session: FakeAsyncSession,
    method: str,
    path: str,
    *,
    json: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    async def perform_request() -> httpx.Response:
        async def override_session():
            yield session

        app.dependency_overrides[get_db_session] = override_session
        try:
            transport = httpx.ASGITransport(app=app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://testserver",
            ) as client:
                return await client.request(
                    method,
                    path,
                    json=json,
                    headers=headers,
                )
        finally:
            app.dependency_overrides.clear()

    return asyncio.run(perform_request())


def test_register_succeeds_normalizes_email_and_never_returns_password_hash() -> None:
    session = FakeAsyncSession()

    response = request(
        session,
        "POST",
        "/api/v1/auth/register",
        json={"email": "  User@Example.COM  ", "password": VALID_PASSWORD},
    )

    assert response.status_code == 201
    assert response.json()["email"] == "user@example.com"
    assert response.json()["role"] == "USER"
    assert response.json()["status"] == "ACTIVE"
    assert "password_hash" not in response.json()

    stored_user = next(iter(session.users.values()))
    assert stored_user.email == "user@example.com"
    assert stored_user.password_hash != VALID_PASSWORD
    assert stored_user.password_hash.startswith("$argon2id$")


def test_duplicate_registration_returns_409() -> None:
    session = FakeAsyncSession([make_user()])

    response = request(
        session,
        "POST",
        "/api/v1/auth/register",
        json={"email": "USER@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == 409


def test_registration_cannot_create_admin_user() -> None:
    session = FakeAsyncSession()

    response = request(
        session,
        "POST",
        "/api/v1/auth/register",
        json={
            "email": "user@example.com",
            "password": VALID_PASSWORD,
            "role": "ADMIN",
        },
    )

    assert response.status_code == 422
    assert session.users == {}


@pytest.mark.parametrize(
    ("field_name", "field_value"),
    [
        ("status", "ACTIVE"),
        ("user_id", str(uuid.uuid4())),
    ],
)
def test_registration_rejects_other_server_owned_fields(
    field_name: str,
    field_value: str,
) -> None:
    session = FakeAsyncSession()
    payload = {"email": "user@example.com", "password": VALID_PASSWORD}
    payload[field_name] = field_value

    response = request(
        session,
        "POST",
        "/api/v1/auth/register",
        json=payload,
    )

    assert response.status_code == 422
    assert session.users == {}


def test_password_longer_than_128_characters_is_rejected_without_truncation() -> None:
    response = request(
        FakeAsyncSession(),
        "POST",
        "/api/v1/auth/register",
        json={"email": "user@example.com", "password": "x" * 129},
    )

    assert response.status_code == 422


def test_login_succeeds_with_short_lived_bearer_token() -> None:
    user = make_user()

    response = request(
        FakeAsyncSession([user]),
        "POST",
        "/api/v1/auth/login",
        json={"email": " USER@EXAMPLE.COM ", "password": VALID_PASSWORD},
    )

    body = response.json()
    assert response.status_code == 200
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 900
    assert body["access_token"]
    assert body["user"]["id"] == str(user.id)
    assert "password_hash" not in body["user"]


def test_unknown_email_and_wrong_password_have_identical_401_response() -> None:
    session = FakeAsyncSession([make_user()])
    wrong_email = request(
        session,
        "POST",
        "/api/v1/auth/login",
        json={"email": "missing@example.com", "password": VALID_PASSWORD},
    )
    wrong_password = request(
        session,
        "POST",
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": "w" * 16},
    )

    assert wrong_email.status_code == wrong_password.status_code == 401
    assert wrong_email.json() == wrong_password.json()
    assert wrong_email.headers["www-authenticate"] == "Bearer"
    assert wrong_password.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("account_status", ["SUSPENDED", "DISABLED"])
def test_inactive_user_cannot_login(account_status: str) -> None:
    response = request(
        FakeAsyncSession([make_user(status=account_status)]),
        "POST",
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}


@pytest.mark.parametrize("account_kind", ["non_local", "missing_password"])
def test_user_without_local_password_cannot_login(account_kind: str) -> None:
    user = make_user(auth_provider="GOOGLE" if account_kind == "non_local" else "LOCAL")
    if account_kind == "missing_password":
        user.password_hash = None

    response = request(
        FakeAsyncSession([user]),
        "POST",
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}


def test_me_reads_and_returns_current_active_user_without_password_hash() -> None:
    user = make_user()
    token = create_access_token(
        user.id,
        get_settings().jwt_secret_key,
        15,
    )

    response = request(
        FakeAsyncSession([user]),
        "GET",
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json()["id"] == str(user.id)
    assert response.json()["email"] == user.email
    assert "password_hash" not in response.json()


@pytest.mark.parametrize("token_kind", ["missing", "invalid", "expired"])
def test_me_rejects_missing_invalid_or_expired_token(token_kind: str) -> None:
    headers = None
    if token_kind == "invalid":
        headers = {"Authorization": "Bearer not-a-valid-token"}
    elif token_kind == "expired":
        token = create_access_token(
            uuid.uuid4(),
            get_settings().jwt_secret_key,
            -1,
        )
        headers = {"Authorization": f"Bearer {token}"}

    response = request(
        FakeAsyncSession(),
        "GET",
        "/api/v1/auth/me",
        headers=headers,
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_me_rejects_user_who_is_no_longer_active() -> None:
    user = make_user(status="SUSPENDED")
    token = create_access_token(
        user.id,
        get_settings().jwt_secret_key,
        15,
    )

    response = request(
        FakeAsyncSession([user]),
        "GET",
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
