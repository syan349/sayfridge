from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings


settings = get_settings()

# Use the Neon pooled connection at runtime; migrations use DATABASE_URL_DIRECT.
engine = create_async_engine(
    settings.database_url.get_secret_value(),
    pool_pre_ping=True,
    # Keep bound account/inventory values out of SQLAlchemy exception logs.
    hide_parameters=True,
)
AsyncSessionFactory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db_session() -> AsyncIterator[AsyncSession]:
    """Provide a request-scoped asynchronous database session for FastAPI routes."""

    async with AsyncSessionFactory() as session:
        yield session
