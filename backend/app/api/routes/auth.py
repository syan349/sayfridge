from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.config import Settings, get_settings
from app.core.login_rate_limit import LoginRateLimiter, login_rate_limiter
from app.core.security_events import request_correlation_id, security_event
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.auth import (
    AuthErrorResponse,
    AuthValidationErrorResponse,
    ChangePasswordRequest,
    LoginRequest,
    LoginResponse,
    PasswordChangeErrorResponse,
    RefreshRequest,
    RegisterRequest,
    UserPublic,
)
from app.services.auth import (
    EmailAlreadyRegisteredError,
    PasswordChangeError,
    authenticate_user,
    change_password,
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
    # Keep the user row lock acquired in authenticate_user until start_session
    # commits: committing here would release it and let a concurrent password
    # change revoke sessions before this login mints its own (still-valid) one.
    await ensure_default_space(session, user.id, commit=False)
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


password_change_limiter = LoginRateLimiter()


@router.post(
    "/change-password",
    status_code=204,
    summary="Change password and revoke all sessions",
    description=(
        "Change the password of the currently authenticated local account. Requires "
        "the current password and a new password (8–128 characters, different from "
        "the current one). On success the stored Argon2id hash is updated and every "
        "session of the account is revoked atomically, so all devices must sign in "
        "again with the new password. A wrong current password returns 400 "
        "(not 401, so clients do not mistake it for an expired token and retry)."
    ),
    responses={
        400: {
            "model": PasswordChangeErrorResponse,
            "description": "Current password is incorrect, or the new password equals the current one",
        },
        401: {
            "model": AuthErrorResponse,
            "description": "Missing, invalid, expired or revoked access credentials, or the account session ended",
        },
        403: {
            "model": PasswordChangeErrorResponse,
            "description": "The account does not use a local password (e.g. external identity provider)",
        },
        429: {
            "model": AuthErrorResponse,
            "description": "Too many password-change attempts; Retry-After is included",
        },
    },
)
async def update_password(
    payload: ChangePasswordRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_db_session),
) -> Response:
    """Atomically update the caller's password hash and revoke all sessions."""
    request_id = request_correlation_id(request)
    key = password_change_limiter.key("password-change", str(current_user.id))
    decision = password_change_limiter.reserve(key, maximum_attempts=5, window_seconds=300)
    if not decision.allowed:
        security_event("password_change_rate_limited", request_id=request_id, user_id=current_user.id)
        raise HTTPException(429, "Too many attempts; try again later", headers={"Retry-After":str(decision.retry_after_seconds)})
    try:
        await change_password(session, current_user.id, payload.current_password, payload.new_password)
    except PasswordChangeError as exc:
        security_event("password_change_denied", request_id=request_id, user_id=current_user.id)
        raise HTTPException(exc.status, {"code":exc.code,"message":exc.message}) from None
    password_change_limiter.clear(key)
    security_event("password_changed", request_id=request_id, user_id=current_user.id)
    return Response(status_code=204, headers={"Cache-Control":"no-store"})
