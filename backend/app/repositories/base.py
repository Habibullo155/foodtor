from collections.abc import Sequence
from typing import Any, Generic, TypeVar

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import Base

ModelT = TypeVar("ModelT", bound=Base)


class BaseRepository(Generic[ModelT]):
    """Только доступ к данным. Никакой бизнес-логики и никаких commit — транзакцией владеет UoW (get_session)."""

    model: type[ModelT]

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get(self, id_: int) -> ModelT | None:
        return await self.session.get(self.model, id_)

    async def list(self, *, offset: int = 0, limit: int = 50, **filters: Any) -> Sequence[ModelT]:
        stmt = select(self.model).filter_by(**filters).offset(offset).limit(limit)
        return (await self.session.scalars(stmt)).unique().all()

    def add(self, obj: ModelT) -> ModelT:
        self.session.add(obj)
        return obj

    async def delete(self, obj: ModelT) -> None:
        await self.session.delete(obj)
