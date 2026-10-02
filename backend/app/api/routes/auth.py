from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.config import Settings, get_settings
from app.core.login_rate_limit import login_rate_limiter
from app.core.security_events import request_correlation_id, security_event
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.auth import (
    AuthErrorResponse,
    AuthValidationErrorResponse,
    LoginRequest,
    LoginResponse,
    RefreshRequest,
    RegisterRequest,
    UserPublic,
)
from app.services.auth import (
    EmailAlreadyRegisteredError,
    authenticate_user,
    register_user,
)


router = APIRouter(
    prefix="/api/v1/auth",
    tags=["auth"],
    responses={
        422: {
            "model": AuthValidationErrorResponse,
            "description": "Malformed or invalid authentication request",
        }
    },
)


@router.post(
    "/register",
    response_model=UserPublic,
    summary="Register user",
    status_code=status.HTTP_201_CREATED,
    responses={
        409: {
            "model": AuthErrorResponse,
            "description": "The normalized email is already registered",
        }
    },
)
async def register(
    payload: RegisterRequest,
    session: AsyncSession = Depends(get_db_session),
) -> User:
    """Create a local non-admin account without creating inventory."""
    try:
        return await register_user(session, str(payload.email), payload.password)
    except EmailAlreadyRegisteredError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email is already registered",
        ) from exc


@router.post(
    "/login",
    response_model=LoginResponse,
    summary="Log in",
    responses={
        401: {"model": AuthErrorResponse, "description": "Invalid credentials or unavailable account"},
        429: {"model": AuthErrorResponse, "description": "Too many login attempts"},
    },
)
async def login(
    payload: LoginRequest,
    request: Request,
    response: Response,
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> LoginResponse:
    """Validate credentials and issue a short-lived access token."""
    response.headers["Cache-Control"] = "no-store"
    client_host = request.client.host if request.client else "unknown"
    limit_key = login_rate_limiter.key(client_host, str(payload.email))
    decision = login_rate_limiter.reserve(
        limit_key,
        maximum_attempts=settings.login_rate_limit_attempts,
        window_seconds=settings.login_rate_limit_window_seconds,
    )
    if not decision.allowed:
        security_event("login_rate_limited", request_id=request_correlation_id(request))
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts; try again later",
            headers={"Retry-After": str(decision.retry_after_seconds)},
        )

    user = await authenticate_user(session, str(payload.email), payload.password)
    if user is None:
        security_event("login_denied", request_id=request_correlation_id(request))
        # Return the same response for unknown emails, incorrect passwords, and unavailable accounts to avoid disclosing account status.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    login_rate_limiter.clear(limit_key)
    from app.services.storage_spaces import ensure_default_space
    await ensure_default_space(session, user.id)
    from app.services.auth_sessions import start_session
    result = await start_session(session, user, settings)
    security_event("login_succeeded", request_id=request_correlation_id(request), user_id=user.id)
    return result


@router.post(
    "/refresh", response_model=LoginResponse,
    summary="Rotate refresh credential and renew access",
    responses={401: {
        "model": AuthErrorResponse,
        "description": "Expired, revoked or reused refresh credential",
    }},
)
async def refresh(
    payload: RefreshRequest,
    request: Request,
    response: Response,
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> LoginResponse:
    """Renew a device session and replace its single-use refresh credential."""
    from app.services.auth_sessions import InvalidSession, rotate_session
    response.headers["Cache-Control"] = "no-store"
    try:
        return await rotate_session(session, payload.refresh_token, settings, request_id=request_correlation_id(request))
    except InvalidSession:
        security_event("refresh_denied", request_id=request_correlation_id(request))
        raise HTTPException(
            status_code=401, detail="Session expired or revoked; please sign in again",
        ) from None


@router.post("/logout", status_code=204, summary="Revoke the device session")
async def logout(
    payload: RefreshRequest,
    request: Request,
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    """Revoke a device session; unknown or already revoked credentials return 204."""
    from app.services.auth_sessions import revoke_session
    await revoke_session(session, payload.refresh_token, request_id=request_correlation_id(request))
    return Response(status_code=204)


@router.get(
    "/me",
    response_model=UserPublic,
    summary="Get current user",
    responses={
        401: {"model": AuthErrorResponse, "description": "Missing, invalid, expired, or unavailable identity"}
    },
)
async def me(current_user: User = Depends(get_current_user)) -> User:
    """Read the current account status and role."""
    return current_user
