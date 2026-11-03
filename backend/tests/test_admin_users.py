"""B25 administrator account-management acceptance tests."""
import asyncio
from datetime import datetime, timedelta, timezone
import uuid

import pytest
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import Session

from app.core.config import get_settings
from auth_test_support import session_token
from app.db.models import User
from auth_test_support import exercise, make_user, request, seed_users

pytestmark = pytest.mark.postgres
BASE = "/api/v1/admin/users"


@pytest.fixture
def admin_context(database):
    admin = make_user(email="admin@example.com", role="ADMIN")
    ordinary = make_user(email="ordinary@example.com")
    suspended = make_user(email="under_score@example.com", status="SUSPENDED")
    disabled = make_user(email="disabled@example.com", status="DISABLED")
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    for offset, user in enumerate((admin, ordinary, suspended, disabled)):
        user.created_at = start + timedelta(days=offset)
        user.updated_at = user.created_at
    seed_users(database, admin, ordinary, suspended, disabled)
    secret = get_settings().jwt_secret_key
    admin_headers = {
        "Authorization": f"Bearer {session_token(database, admin.id)}"
    }
    ordinary_headers = {
        "Authorization": f"Bearer {session_token(database, ordinary.id)}"
    }
    return database, admin, ordinary, suspended, disabled, admin_headers, ordinary_headers


def admin_request(context, method, path="", *, query="", json=None):
    return request(
        context[0],
        method,
        BASE + path + query,
        json=json,
        headers=context[5],
    )


def test_admin_lists_filters_and_paginates_safe_user_fields(admin_context):
    context = admin_context
    response = admin_request(context, "GET")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total"] == 4
    assert [row["id"] for row in body["items"]] == [
        str(context[4].id),
        str(context[3].id),
        str(context[2].id),
        str(context[1].id),
    ]
    assert set(body["items"][0]) == {
        "id",
        "email",
        "role",
        "status",
        "created_at",
        "updated_at",
    }

    filtered = admin_request(
        context,
        "GET",
        query="?role=USER&status=SUSPENDED&q=UNDER_",
    ).json()
    assert filtered["total"] == 1
    assert filtered["items"][0]["id"] == str(context[3].id)

    literal = admin_request(context, "GET", query="?q=_").json()
    assert literal["total"] == 1
    assert literal["items"][0]["email"] == "under_score@example.com"

    page = admin_request(context, "GET", query="?page=2&page_size=2").json()
    assert page["total"] == 4
    assert [row["id"] for row in page["items"]] == [
        str(context[2].id),
        str(context[1].id),
    ]


def test_admin_reads_user_detail_and_hides_missing_account(admin_context):
    context = admin_context
    response = admin_request(context, "GET", "/" + str(context[2].id))
    assert response.status_code == 200
    assert response.json()["email"] == "ordinary@example.com"
    assert "password_hash" not in response.json()
    assert "voice_limit_seconds" not in response.json()

    missing = admin_request(context, "GET", "/" + str(uuid.uuid4()))
    assert missing.status_code == 404
    assert missing.json()["detail"]["code"] == "NOT_FOUND"


def test_admin_list_tolerates_legacy_invalid_stored_email(admin_context):
    legacy = make_user(email="legacy@example.test")
    seed_users(admin_context[0], legacy)

    response = admin_request(admin_context, "GET", query="?q=legacy")

    assert response.status_code == 200, response.text
    assert response.json()["total"] == 1
    assert response.json()["items"][0]["email"] == "legacy@example.test"


@pytest.mark.ci
def test_ordinary_user_is_forbidden_from_every_admin_user_endpoint(admin_context):
    context = admin_context
    paths = [
        ("GET", BASE, None),
        ("GET", BASE + "/" + str(context[2].id), None),
        (
            "PATCH",
            BASE + "/" + str(context[2].id) + "/status",
            {"status": "SUSPENDED"},
        ),
    ]
    for method, path, body in paths:
        response = request(
            context[0],
            method,
            path,
            json=body,
            headers=context[6],
        )
        assert response.status_code == 403
        assert response.json()["detail"]["code"] == "FORBIDDEN"


def test_admin_user_endpoints_require_authentication(admin_context):
    response = request(admin_context[0], "GET", BASE)
    assert response.status_code == 401


@pytest.mark.ci
def test_admin_changes_user_status_and_new_state_controls_authentication(admin_context):
    context = admin_context
    target = context[2]
    response = admin_request(
        context,
        "PATCH",
        "/" + str(target.id) + "/status",
        json={"status": "SUSPENDED"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "SUSPENDED"
    assert response.json()["role"] == "USER"
    with Session(context[0][2]) as session:
        stored = session.get(User, target.id)
        assert stored.status == "SUSPENDED" and stored.role == "USER"

    token = session_token(context[0], target.id)
    unavailable = request(
        context[0],
        "GET",
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert unavailable.status_code == 401


def test_repeated_status_update_preserves_updated_at(admin_context):
    context = admin_context
    target = context[3]
    first = admin_request(
        context,
        "PATCH",
        "/" + str(target.id) + "/status",
        json={"status": "SUSPENDED"},
    )
    assert first.status_code == 200
    second = admin_request(
        context,
        "PATCH",
        "/" + str(target.id) + "/status",
        json={"status": "SUSPENDED"},
    )
    assert second.status_code == 200
    assert second.json() == first.json()


def test_admin_accounts_cannot_be_status_targets(admin_context):
    context = admin_context
    other_admin = make_user(email="second-admin@example.com", role="ADMIN")
    seed_users(context[0], other_admin)
    for target_id in (context[1].id, other_admin.id):
        response = admin_request(
            context,
            "PATCH",
            "/" + str(target_id) + "/status",
            json={"status": "DISABLED"},
        )
        assert response.status_code == 403
        assert response.json()["detail"]["code"] == "ADMIN_TARGET_FORBIDDEN"
    with Session(context[0][2]) as session:
        assert session.get(User, other_admin.id).status == "ACTIVE"


def test_admin_rejects_invalid_queries_paths_and_status_bodies(admin_context):
    context = admin_context
    invalid_queries = [
        "?role=OWNER",
        "?status=ARCHIVED",
        "?page=0",
        "?page_size=101",
        "?q=" + "x" * 101,
        "?unknown=1",
    ]
    for query in invalid_queries:
        response = admin_request(context, "GET", query=query)
        assert response.status_code == 422, (query, response.text)
        assert response.json()["detail"]["code"] == "VALIDATION_ERROR"

    path = "/" + str(context[2].id) + "/status"
    for body in ({}, {"status": None}, {"status": "ARCHIVED"},
                 {"status": "ACTIVE", "role": "ADMIN"}):
        response = admin_request(context, "PATCH", path, json=body)
        assert response.status_code == 422, (body, response.text)
        assert response.json()["detail"]["code"] == "VALIDATION_ERROR"
    assert admin_request(context, "GET", "/not-a-uuid").status_code == 422


def test_admin_list_count_and_empty_page_use_one_database_statement(
    admin_context,
    monkeypatch,
):
    context = admin_context
    execute = AsyncSession.execute
    statements = []

    async def observe(session, statement, *args, **kwargs):
        sql = str(statement)
        if "filtered_admin_users" in sql:
            statements.append(sql)
        return await execute(session, statement, *args, **kwargs)

    monkeypatch.setattr(AsyncSession, "execute", observe)

    async def scenario(client, sessions):
        response = await client.get(
            BASE + "?page=2&page_size=100",
            headers=context[5],
        )
        assert response.status_code == 200, response.text
        assert response.json()["items"] == []
        assert response.json()["total"] == 4

    asyncio.run(exercise(context[0], scenario))
    assert len(statements) == 1
    assert "count(" in statements[0].lower()
