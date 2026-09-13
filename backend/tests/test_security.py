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
