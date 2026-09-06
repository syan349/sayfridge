import secrets
import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password, verify_password
from app.db.models import User


LOCAL_PROVIDER = "LOCAL"
ACTIVE_STATUS = "ACTIVE"
USER_ROLE = "USER"

# 用户不存在时也执行一次 Argon2id 校验，降低基于响应耗时枚举邮箱的风险。
_DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(32))


class EmailAlreadyRegisteredError(Exception):
    pass


def normalize_email(email: str) -> str:
    return email.strip().lower()


async def get_user_by_email(session: AsyncSession, email: str) -> User | None:
    result = await session.execute(
        select(User).where(User.email == normalize_email(email))
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
        password_hash=hash_password(password),
        auth_provider=LOCAL_PROVIDER,
        role=USER_ROLE,
        status=ACTIVE_STATUS,
    )
    session.add(user)
    try:
        await session.commit()
    except IntegrityError as exc:
        # 预检查之外仍由数据库唯一约束处理并发注册竞争。
        await session.rollback()
        raise EmailAlreadyRegisteredError from exc
    await session.refresh(user)
    return user


async def authenticate_user(
    session: AsyncSession,
    email: str,
    password: str,
) -> User | None:
    user = await get_user_by_email(session, email)
    stored_hash = user.password_hash if user and user.password_hash else _DUMMY_PASSWORD_HASH
    password_matches = verify_password(password, stored_hash)

    if (
        user is None
        or not password_matches
        or user.auth_provider != LOCAL_PROVIDER
        or user.password_hash is None
        or user.status != ACTIVE_STATUS
    ):
        return None
    return user
