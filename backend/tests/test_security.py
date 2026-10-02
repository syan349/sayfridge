from datetime import datetime, timedelta, timezone
import uuid

import jwt
import pytest
from pydantic import SecretStr

from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


TEST_SECRET = SecretStr("s" * 40)


def test_password_is_argon2id_hashed_and_verifiable() -> None:
    password = "p" * 16

    hashed = hash_password(password)

    assert hashed != password
    assert hashed.startswith("$argon2id$")
    assert verify_password(password, hashed)
    assert not verify_password("w" * 16, hashed)


def test_access_token_contains_and_decodes_user_id() -> None:
    user_id = uuid.uuid4()

    token = create_access_token(user_id, TEST_SECRET, 15)

    assert decode_access_token(token, TEST_SECRET) == user_id


def test_expired_access_token_is_rejected() -> None:
    token = create_access_token(uuid.uuid4(), TEST_SECRET, -1)

    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(token, TEST_SECRET)


@pytest.mark.ci
def test_forged_access_token_is_rejected() -> None:
    token = create_access_token(uuid.uuid4(), TEST_SECRET, 15)

    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(
            token,
            SecretStr("f" * 40),
        )


def test_wrong_token_type_is_rejected() -> None:
    now = datetime.now(timezone.utc)
    token = jwt.encode(
        {
            "sub": str(uuid.uuid4()),
            "type": "refresh",
            "iat": now,
            "exp": now + timedelta(minutes=15),
        },
        TEST_SECRET.get_secret_value(),
        algorithm="HS256",
    )

    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(token, TEST_SECRET)


@pytest.mark.ci
def test_scoped_token_carries_verified_user_and_session():
    from app.core.security import decode_access_identity, JWT_ISSUER, JWT_AUDIENCE
    user_id, session_id = uuid.uuid4(), uuid.uuid4()
    token = create_access_token(user_id, TEST_SECRET, 15, session_id=session_id)
    payload = jwt.decode(token, TEST_SECRET.get_secret_value(), algorithms=["HS256"],
                         issuer=JWT_ISSUER, audience=JWT_AUDIENCE)
    assert payload["iss"] == JWT_ISSUER
    assert payload["aud"] == JWT_AUDIENCE
    identity = decode_access_identity(token, TEST_SECRET)
    assert (identity.user_id, identity.session_id) == (user_id, session_id)


@pytest.mark.ci
@pytest.mark.parametrize("scope", [
    {"iss": "other", "aud": "sayfridge-api"},
    {"iss": "sayfridge", "aud": "other"},
    {"iss": "sayfridge"}, {"aud": "sayfridge-api"},
    {"iss": None, "aud": None},
    {"iss": "sayfridge", "aud": ["sayfridge-api", "other"]},
])
def test_wrong_or_partial_scope_is_rejected(scope):
    import json
    now = datetime.now(timezone.utc)
    payload = {"sub": str(uuid.uuid4()), "type": "access", "iat": int(now.timestamp()),
               "exp": int((now + timedelta(minutes=15)).timestamp()), **scope}
    token = jwt.api_jws.encode(json.dumps(payload).encode(), TEST_SECRET.get_secret_value(), algorithm="HS256")
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(token, TEST_SECRET)


@pytest.mark.ci
@pytest.mark.parametrize("sid", [None, 123, {}, "not-a-uuid"])
def test_invalid_session_claim_is_rejected(sid):
    now = datetime.now(timezone.utc)
    token = jwt.encode({"sub": str(uuid.uuid4()), "type": "access", "iat": now,
                        "exp": now + timedelta(minutes=15), "sid": sid},
                       TEST_SECRET.get_secret_value(), algorithm="HS256")
    with pytest.raises(jwt.InvalidTokenError):
        decode_access_token(token, TEST_SECRET)
