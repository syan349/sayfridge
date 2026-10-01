from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.config import Settings, get_settings
from app.core.login_rate_limit import login_rate_limiter
from app.core.security import create_access_token
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.auth import (
    AuthErrorResponse,
    AuthValidationErrorResponse,
    LoginRequest,
    LoginResponse,
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
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> LoginResponse:
    """Validate credentials and issue a short-lived access token."""
    client_host = request.client.host if request.client else "unknown"
    limit_key = login_rate_limiter.key(client_host, str(payload.email))
    decision = login_rate_limiter.reserve(
        limit_key,
        maximum_attempts=settings.login_rate_limit_attempts,
        window_seconds=settings.login_rate_limit_window_seconds,
    )
    if not decision.allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many login attempts; try again later",
            headers={"Retry-After": str(decision.retry_after_seconds)},
        )

    user = await authenticate_user(session, str(payload.email), payload.password)
    if user is None:
        # Return the same response for unknown emails, incorrect passwords, and unavailable accounts to avoid disclosing account status.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    login_rate_limiter.clear(limit_key)
    from app.services.storage_spaces import ensure_default_space
    await ensure_default_space(session, user.id)
    return LoginResponse(
        access_token=create_access_token(
            user.id,
            settings.jwt_secret_key,
            settings.access_token_expire_minutes,
        ),
        expires_in=settings.access_token_expire_minutes * 60,
        user=UserPublic.model_validate(user),
    )


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
