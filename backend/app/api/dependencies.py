import jwt
from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import decode_access_token
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
    credentials: HTTPAuthorizationCredentials | None = Security(bearer_scheme),
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise authentication_error()

    try:
        user_id = decode_access_token(
            credentials.credentials,
            settings.jwt_secret_key,
        )
    except jwt.InvalidTokenError as exc:
        raise authentication_error() from exc

    # Token 只证明签发时身份；角色和状态必须每次从数据库读取当前值。
    user = await get_user_by_id(session, user_id)
    if user is None or user.status != ACTIVE_STATUS:
        raise authentication_error()
    return user
