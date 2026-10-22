from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.config import get_settings

_settings = get_settings()
# В тестах — NullPool: у каждого теста свой event loop, а соединения asyncpg привязаны к циклу
engine = (
    create_async_engine(_settings.database_url, poolclass=NullPool)
    if _settings.app_env == "test"
    else create_async_engine(_settings.database_url, pool_pre_ping=True, pool_size=10, max_overflow=20)
)
SessionFactory = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """Unit of Work на запрос: коммит при успехе, откат при исключении."""
    async with SessionFactory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
