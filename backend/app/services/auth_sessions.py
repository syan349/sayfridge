"""Revocable device sessions with single-use refresh credential rotation."""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.security import AccessIdentity, create_access_token
from app.core.security_events import security_event
from app.db.models import AuthSession, RefreshCredential, User
from app.schemas.auth import LoginResponse, UserPublic


class InvalidSession(Exception):
    """The supplied credential cannot authorize this device session."""


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def response(
    session: AuthSession, user: User, settings: Settings, refresh: str, now: datetime,
) -> LoginResponse:
    return LoginResponse(
        access_token=create_access_token(
            user.id, settings.jwt_secret_key, settings.access_token_expire_minutes,
            session_id=session.id,
        ),
        expires_in=settings.access_token_expire_minutes * 60,
        refresh_token=refresh,
        refresh_expires_in=max(0, int((session.expires_at - now).total_seconds())),
        user=UserPublic.model_validate(user),
    )


async def start_session(db: AsyncSession, user: User, settings: Settings) -> LoginResponse:
    now = datetime.now(timezone.utc)
    session = AuthSession(
        id=uuid.uuid4(), user_id=user.id,
        expires_at=now + timedelta(days=min(
            settings.refresh_token_idle_days, settings.refresh_token_absolute_days,
        )),
        absolute_expires_at=now + timedelta(days=settings.refresh_token_absolute_days),
    )
    refresh = secrets.token_urlsafe(48)
    db.add(session)
    await db.flush()
    db.add(RefreshCredential(token_hash=token_hash(refresh), session_id=session.id))
    result = response(session, user, settings, refresh, now)
    await db.commit()
    return result


async def locked_session(
    db: AsyncSession, refresh: str,
) -> tuple[AuthSession, RefreshCredential]:
    # Every credential in a family locks the same session row. Re-read the
    # credential after locking so concurrent refreshes observe used_at.
    digest = token_hash(refresh)
    sid = await db.scalar(select(RefreshCredential.session_id).where(
        RefreshCredential.token_hash == digest,
    ))
    if sid is None:
        raise InvalidSession()
    user_id = await db.scalar(select(AuthSession.user_id).where(AuthSession.id == sid))
    await db.scalar(select(User).where(User.id == user_id).with_for_update().execution_options(populate_existing=True))
    session = await db.scalar(
        select(AuthSession).where(AuthSession.id == sid).with_for_update()
        .execution_options(populate_existing=True)
    )
    credential = await db.scalar(
        select(RefreshCredential).where(RefreshCredential.token_hash == digest)
        .execution_options(populate_existing=True)
    )
    if session is None or credential is None:
        raise InvalidSession()
    return session, credential


async def rotate_session(
    db: AsyncSession, refresh: str, settings: Settings, *, request_id: uuid.UUID | None = None,
) -> LoginResponse:
    session, credential = await locked_session(db, refresh)
    now = datetime.now(timezone.utc)
    user = await db.get(User, session.user_id)
    if (
        credential.used_at is not None or session.revoked_at is not None
        or session.expires_at <= now or session.absolute_expires_at <= now
        or user is None or user.status != "ACTIVE"
    ):
        newly_revoked = session.revoked_at is None
        session.revoked_at = session.revoked_at or now
        await db.commit()
        if credential.used_at is not None:
            security_event("refresh_replay_detected", request_id=request_id, user_id=session.user_id, session_id=session.id)
        if newly_revoked:
            security_event("session_revoked", request_id=request_id, user_id=session.user_id, session_id=session.id)
        raise InvalidSession()
    credential.used_at = now
    session.expires_at = min(
        now + timedelta(days=settings.refresh_token_idle_days), session.absolute_expires_at,
    )
    replacement = secrets.token_urlsafe(48)
    db.add(RefreshCredential(token_hash=token_hash(replacement), session_id=session.id))
    result = response(session, user, settings, replacement, now)
    await db.commit()
    return result


async def revoke_session(
    db: AsyncSession, refresh: str, *, request_id: uuid.UUID | None = None,
) -> None:
    try:
        session, _ = await locked_session(db, refresh)
    except InvalidSession:
        return
    newly_revoked = session.revoked_at is None
    session.revoked_at = session.revoked_at or datetime.now(timezone.utc)
    await db.commit()
    if newly_revoked:
        security_event("session_revoked", request_id=request_id, user_id=session.user_id, session_id=session.id)


async def validate_access_session(
    db: AsyncSession, identity: AccessIdentity,
) -> None:
    if identity.session_id is None:
        raise InvalidSession()
    session = await db.get(AuthSession, identity.session_id)
    now = datetime.now(timezone.utc)
    if (
        session is None or session.user_id != identity.user_id or session.revoked_at is not None
        or session.expires_at <= now or session.absolute_expires_at <= now
    ):
        raise InvalidSession()
