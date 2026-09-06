from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings


settings = get_settings()

# 应用运行时只使用 Neon 池化连接；迁移使用 DATABASE_URL_DIRECT。
engine = create_async_engine(
    settings.database_url.get_secret_value(),
    pool_pre_ping=True,
)
AsyncSessionFactory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db_session() -> AsyncIterator[AsyncSession]:
    """为未来的 FastAPI 路由提供请求级异步数据库会话。"""

    async with AsyncSessionFactory() as session:
        yield session
