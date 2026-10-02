from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import uuid

import jwt
from pydantic import SecretStr
from pwdlib import PasswordHash
from pwdlib.exceptions import UnknownHashError
from pwdlib.hashers.argon2 import Argon2Hasher


JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_TYPE = "access"
JWT_ISSUER = "sayfridge"
JWT_AUDIENCE = "sayfridge-api"


@dataclass(frozen=True)
class AccessIdentity:
    user_id: uuid.UUID
    session_id: uuid.UUID | None


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
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
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


def decode_access_identity(token: str, secret_key: SecretStr) -> AccessIdentity:
    # Fix the algorithm and require key claims; do not trust the token header to determine its algorithm or purpose.
    try:
        payload = jwt.decode(
            token,
            secret_key.get_secret_value(),
            algorithms=[JWT_ALGORITHM],
            # Validate the scope pair below to permit existing unscoped tokens
            # until their original expiry, without decoding a second time.
            options={"require": ["sub", "type", "iat", "exp"], "verify_aud": False},
        )
    except (TypeError, ValueError, OverflowError) as exc:
        # Some PyJWT versions leak conversion errors for malformed numeric claims.
        raise jwt.InvalidTokenError("invalid token claims") from exc
    if payload["type"] != ACCESS_TOKEN_TYPE:
        raise jwt.InvalidTokenError("unexpected token type")

    if "iss" in payload or "aud" in payload:
        if payload.get("iss") != JWT_ISSUER or payload.get("aud") != JWT_AUDIENCE:
            raise jwt.InvalidTokenError("unexpected token issuer or audience")

    try:
        user_id = uuid.UUID(payload["sub"])
        session_id = uuid.UUID(payload["sid"]) if "sid" in payload else None
        return AccessIdentity(user_id=user_id, session_id=session_id)
    except (TypeError, ValueError, AttributeError) as exc:
        raise jwt.InvalidTokenError("invalid token identity") from exc


def decode_access_token(token: str, secret_key: SecretStr) -> uuid.UUID:
    """Compatibility wrapper for callers that only need the verified user ID."""
    return decode_access_identity(token, secret_key).user_id
