import secrets
import uuid

from starlette.concurrency import run_in_threadpool

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password, verify_password
from app.db.models import StorageSpace, User


LOCAL_PROVIDER = "LOCAL"
ACTIVE_STATUS = "ACTIVE"
USER_ROLE = "USER"
DEFAULT_STORAGE_SPACE_NAME = "Default Space"
DEFAULT_STORAGE_SPACE_TYPE = "FRIDGE"

# Verify an Argon2id hash even for unknown users to reduce email enumeration through response timing.
_DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(32))


class EmailAlreadyRegisteredError(Exception):
    pass


def normalize_email(email: str) -> str:
    return email.strip().lower()


async def get_user_by_email(session: AsyncSession, email: str) -> User | None:
    result = await session.execute(
        select(User).where(User.email == normalize_email(email)).with_for_update().execution_options(populate_existing=True)
    )
    return result.scalar_one_or_none()


async def get_user_by_id(session: AsyncSession, user_id: uuid.UUID) -> User | None:
    result = await session.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


async def register_user(
    session: AsyncSession,
    email: str,
    password: str,
) -> User:
    normalized_email = normalize_email(email)
    if await get_user_by_email(session, normalized_email) is not None:
        raise EmailAlreadyRegisteredError

    user = User(
        email=normalized_email,
        password_hash=await run_in_threadpool(hash_password, password),
        auth_provider=LOCAL_PROVIDER,
        role=USER_ROLE,
        status=ACTIVE_STATUS,
    )
    default_space = StorageSpace(
        user=user,
        name=DEFAULT_STORAGE_SPACE_NAME,
        type=DEFAULT_STORAGE_SPACE_TYPE,
        status=ACTIVE_STATUS,
    )
    session.add_all((user, default_space))
    try:
        await session.commit()
    except IntegrityError as exc:
        # Treat only email uniqueness violations as duplicate registration; propagate other database errors.
        await session.rollback()
        if (
            getattr(exc.orig, "sqlstate", None) == "23505"
            and getattr(getattr(exc.orig, "diag", None), "constraint_name", None)
            == "uq_user_email"
        ):
            raise EmailAlreadyRegisteredError from exc
        raise
    await session.refresh(user)
    return user


async def authenticate_user(
    session: AsyncSession,
    email: str,
    password: str,
) -> User | None:
    user = await get_user_by_email(session, email)
    stored_hash = user.password_hash if user and user.password_hash else _DUMMY_PASSWORD_HASH
    password_matches = await run_in_threadpool(verify_password, password, stored_hash)

    if (
        user is None
        or not password_matches
        or user.auth_provider != LOCAL_PROVIDER
        or user.password_hash is None
        or user.status != ACTIVE_STATUS
    ):
        return None
    return user


class PasswordChangeError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


async def change_password(db: AsyncSession, user_id: uuid.UUID, current: str, new: str) -> None:
    from datetime import datetime, timezone
    from app.db.models import AuthSession
    user = await db.scalar(select(User).where(User.id == user_id).with_for_update().execution_options(populate_existing=True))
    if user is None or user.status != ACTIVE_STATUS:
        raise PasswordChangeError(401, "SESSION_ENDED", "Please sign in again.")
    if user.auth_provider != LOCAL_PROVIDER or not user.password_hash:
        raise PasswordChangeError(403, "PASSWORD_CHANGE_UNAVAILABLE", "This account does not use a local password.")
    if not await run_in_threadpool(verify_password, current, user.password_hash):
        raise PasswordChangeError(400, "CURRENT_PASSWORD_INCORRECT", "Current password is incorrect.")
    if new == current:
        raise PasswordChangeError(422, "PASSWORD_UNCHANGED", "Choose a different new password.")
    user.password_hash = await run_in_threadpool(hash_password, new)
    sessions = list(await db.scalars(select(AuthSession).where(AuthSession.user_id == user_id).with_for_update().execution_options(populate_existing=True)))
    now = datetime.now(timezone.utc)
    for item in sessions:
        item.revoked_at = item.revoked_at or now
    try:
        await db.commit()
    except Exception:
        await db.rollback()
        raise
