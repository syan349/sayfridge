"""B01–B03 API tests using real PostgreSQL on both local runs and CI."""
import uuid

import pytest

from app.core.config import get_settings
from app.core.security import create_access_token
from auth_test_support import VALID_PASSWORD, make_user, request, seed_users, read_users

pytestmark = pytest.mark.postgres


def test_register_succeeds_normalizes_email_and_never_returns_password_hash(database) -> None:

    response = request(
        database,
        "POST",
        "/api/v1/auth/register",
        json={"email": "  User@Example.COM  ", "password": VALID_PASSWORD},
    )

    assert response.status_code == 201
    assert response.json()["email"] == "user@example.com"
    assert response.json()["role"] == "USER"
    assert response.json()["status"] == "ACTIVE"
    assert "password_hash" not in response.json()

    stored_user = read_users(database)[0]
    assert stored_user.email == "user@example.com"
    assert stored_user.password_hash != VALID_PASSWORD
    assert stored_user.password_hash.startswith("$argon2id$")


def test_duplicate_registration_returns_409(database) -> None:
    seed_users(database, make_user())

    response = request(
        database,
        "POST",
        "/api/v1/auth/register",
        json={"email": "USER@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == 409


@pytest.mark.ci
def test_registration_cannot_create_admin_user(database) -> None:

    response = request(
        database,
        "POST",
        "/api/v1/auth/register",
        json={
            "email": "user@example.com",
            "password": VALID_PASSWORD,
            "role": "ADMIN",
        },
    )

    assert response.status_code == 422
    assert read_users(database) == []


@pytest.mark.parametrize(
    ("field_name", "field_value"),
    [
        ("status", "ACTIVE"),
        ("user_id", str(uuid.uuid4())),
    ],
)
def test_registration_rejects_other_server_owned_fields(
    database,
    field_name: str,
    field_value: str,
) -> None:
    payload = {"email": "user@example.com", "password": VALID_PASSWORD}
    payload[field_name] = field_value

    response = request(
        database,
        "POST",
        "/api/v1/auth/register",
        json=payload,
    )

    assert response.status_code == 422
    assert read_users(database) == []


def test_password_longer_than_128_characters_is_rejected_without_truncation(database) -> None:
    response = request(
        database,
        "POST",
        "/api/v1/auth/register",
        json={"email": "user@example.com", "password": "x" * 129},
    )

    assert response.status_code == 422


def test_login_succeeds_with_short_lived_bearer_token(database) -> None:
    user = make_user()

    response = request(
        seed_users(database, user),
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


def test_unknown_email_and_wrong_password_have_identical_401_response(database) -> None:
    seed_users(database, make_user())
    wrong_email = request(
        database,
        "POST",
        "/api/v1/auth/login",
        json={"email": "missing@example.com", "password": VALID_PASSWORD},
    )
    wrong_password = request(
        database,
        "POST",
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": "w" * 16},
    )

    assert wrong_email.status_code == wrong_password.status_code == 401
    assert wrong_email.json() == wrong_password.json()
    assert wrong_email.headers["www-authenticate"] == "Bearer"
    assert wrong_password.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("account_status", ["SUSPENDED", "DISABLED"])
def test_inactive_user_cannot_login(database, account_status: str) -> None:
    response = request(
        seed_users(database, make_user(status=account_status)),
        "POST",
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}


@pytest.mark.parametrize("account_kind", ["non_local", "missing_password"])
def test_user_without_local_password_cannot_login(database, account_kind: str) -> None:
    user = make_user(auth_provider="GOOGLE" if account_kind == "non_local" else "LOCAL")
    if account_kind == "missing_password":
        user.password_hash = None

    response = request(
        seed_users(database, user),
        "POST",
        "/api/v1/auth/login",
        json={"email": "user@example.com", "password": VALID_PASSWORD},
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}


def test_me_reads_and_returns_current_active_user_without_password_hash(database) -> None:
    user = make_user()
    token = create_access_token(
        user.id,
        get_settings().jwt_secret_key,
        15,
    )

    response = request(
        seed_users(database, user),
        "GET",
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json()["id"] == str(user.id)
    assert response.json()["email"] == user.email
    assert "password_hash" not in response.json()


@pytest.mark.parametrize("token_kind", ["missing", "invalid", "expired"])
@pytest.mark.ci
def test_me_rejects_missing_invalid_or_expired_token(database, token_kind: str) -> None:
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
        database,
        "GET",
        "/api/v1/auth/me",
        headers=headers,
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_me_rejects_user_who_is_no_longer_active(database) -> None:
    user = make_user(status="SUSPENDED")
    token = create_access_token(
        user.id,
        get_settings().jwt_secret_key,
        15,
    )

    response = request(
        seed_users(database, user),
        "GET",
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
