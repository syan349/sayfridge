from datetime import datetime, timedelta, timezone
import uuid

import jwt
from pydantic import SecretStr
from pwdlib import PasswordHash
from pwdlib.exceptions import UnknownHashError
from pwdlib.hashers.argon2 import Argon2Hasher


JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_TYPE = "access"
password_hash = PasswordHash((Argon2Hasher(),))


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, hashed_password: str) -> bool:
    try:
        return password_hash.verify(password, hashed_password)
    except UnknownHashError:
        return False


def create_access_token(
    user_id: uuid.UUID,
    secret_key: SecretStr,
    expires_minutes: int,
    *,
    now: datetime | None = None,
    session_id: uuid.UUID | None = None,
) -> str:
    issued_at = now or datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "type": ACCESS_TOKEN_TYPE,
        "iat": issued_at,
        "exp": issued_at + timedelta(minutes=expires_minutes),
    }
    if session_id is not None:
        payload["sid"] = str(session_id)
    return jwt.encode(
        payload,
        secret_key.get_secret_value(),
        algorithm=JWT_ALGORITHM,
    )


def decode_access_token(token: str, secret_key: SecretStr) -> uuid.UUID:
    # Fix the algorithm and require key claims; do not trust the token header to determine its algorithm or purpose.
    payload = jwt.decode(
        token,
        secret_key.get_secret_value(),
        algorithms=[JWT_ALGORITHM],
        options={"require": ["sub", "type", "iat", "exp"]},
    )
    if payload["type"] != ACCESS_TOKEN_TYPE:
        raise jwt.InvalidTokenError("unexpected token type")

    try:
        return uuid.UUID(payload["sub"])
    except (TypeError, ValueError, AttributeError) as exc:
        raise jwt.InvalidTokenError("invalid token subject") from exc
