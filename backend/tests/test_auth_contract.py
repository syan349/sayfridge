"""B01–B03 regression tests for request validation and current user state."""
import uuid
import pytest
from app.core.config import get_settings
from app.core.security import create_access_token
from sqlalchemy import update
from app.db.models import User
from auth_test_support import make_user, request, seed_users

pytestmark = pytest.mark.postgres


@pytest.mark.parametrize("path", ["register", "login"])
@pytest.mark.parametrize("payload", [
    {"email": "bad-email", "password": "Secret42!"},
    {"email": "user@example.com", "password": "Ab7!"},
    {"email": "user@example.com", "password": "x" * 129},
    {"email": "user@example.com", "password": "Secret42!", "role": "ADMIN"},
    {"email": "user@example.com"},
])
def test_validation_omits_submitted_values(database, path, payload):
    response = request(database, "POST", f"/api/v1/auth/{path}", json=payload)
    assert response.status_code == 422
    for error in response.json()["detail"]:
        assert set(error) == {"type", "loc", "msg"}
    if "password" in payload:
        assert payload["password"] not in response.text


def test_me_rejects_deleted_user(database):
    token = create_access_token(uuid.uuid4(), get_settings().jwt_secret_key, 15)
    response = request(database, "GET", "/api/v1/auth/me",
                       headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401


def test_me_reads_current_role_and_disabled_status(database):
    user = make_user()
    seed_users(database, user)
    token = create_access_token(user.id, get_settings().jwt_secret_key, 15)
    headers = {"Authorization": f"Bearer {token}"}
    with database[2].begin() as connection:
        connection.execute(update(User).where(User.id == user.id).values(role="ADMIN"))
    assert request(database, "GET", "/api/v1/auth/me", headers=headers).json()["role"] == "ADMIN"
    with database[2].begin() as connection:
        connection.execute(update(User).where(User.id == user.id).values(status="DISABLED"))
    assert request(database, "GET", "/api/v1/auth/me", headers=headers).status_code == 401


@pytest.mark.parametrize("password", ["a" * 8, "a" * 128])
def test_password_boundary_is_accepted(database, password):
    response = request(database, "POST", "/api/v1/auth/register",
                       json={"email": "boundary@example.com", "password": password})
    assert response.status_code == 201
