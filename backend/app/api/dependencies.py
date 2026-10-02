import jwt
from fastapi import Depends, HTTPException, Request, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import decode_access_identity
from app.core.security_events import request_correlation_id, security_event
from app.db.models import User
from app.db.session import get_db_session
from app.services.auth import ACTIVE_STATUS, get_user_by_id


bearer_scheme = HTTPBearer(auto_error=False)


def authentication_error() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired access token",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Security(bearer_scheme),
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> User:
    request_id = request_correlation_id(request)
    if credentials is None or credentials.scheme.lower() != "bearer":
        security_event("authentication_denied", request_id=request_id)
        raise authentication_error()

    try:
        identity = decode_access_identity(
            credentials.credentials,
            settings.jwt_secret_key,
        )
    except jwt.InvalidTokenError as exc:
        security_event("authentication_denied", request_id=request_id)
        raise authentication_error() from exc

    from app.services.auth_sessions import InvalidSession, validate_access_session
    try:
        await validate_access_session(session, identity)
    except (InvalidSession, jwt.InvalidTokenError):
        security_event("authentication_denied", request_id=request_id)
        raise authentication_error() from None

    # A token proves identity at issuance; read the current role and status from the database on every request.
    user = await get_user_by_id(session, identity.user_id)
    if user is None or user.status != ACTIVE_STATUS:
        security_event("authentication_denied", request_id=request_id)
        raise authentication_error()
    return user


async def get_current_admin(request: Request, user: User = Depends(get_current_user)) -> User:
    """Require the current active account to hold the existing ADMIN role."""
    if user.role != "ADMIN":
        security_event("admin_access_denied", request_id=request_correlation_id(request), user_id=user.id)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "FORBIDDEN",
                "message": "Administrator access required",
            },
        )
    return user


async def require_empty_body(request: Request) -> None:
    if await request.body():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={"code": "VALIDATION_ERROR", "message": "This endpoint does not accept a request body"},
        )
