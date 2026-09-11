from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_user
from app.core.config import Settings, get_settings
from app.core.security import create_access_token
from app.db.models import User
from app.db.session import get_db_session
from app.schemas.auth import LoginRequest, LoginResponse, RegisterRequest, UserPublic
from app.services.auth import (
    EmailAlreadyRegisteredError,
    authenticate_user,
    register_user,
)


router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=UserPublic,
    summary="Register user",
    status_code=status.HTTP_201_CREATED,
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


@router.post("/login", response_model=LoginResponse, summary="Log in")
async def login(
    payload: LoginRequest,
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> LoginResponse:
    """Validate credentials and issue a short-lived access token."""
    user = await authenticate_user(session, str(payload.email), payload.password)
    if user is None:
        # Return the same response for unknown emails, incorrect passwords, and unavailable accounts to avoid disclosing account status.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return LoginResponse(
        access_token=create_access_token(
            user.id,
            settings.jwt_secret_key,
            settings.access_token_expire_minutes,
        ),
        expires_in=settings.access_token_expire_minutes * 60,
        user=UserPublic.model_validate(user),
    )


@router.get("/me", response_model=UserPublic, summary="Get current user")
async def me(current_user: User = Depends(get_current_user)) -> User:
    """Read the current account status and role."""
    return current_user
