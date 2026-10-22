from collections.abc import AsyncIterator, Sequence
from typing import Any

from sqlalchemy import literal_column, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import noload

from app.models import Product
from app.repositories.base import BaseRepository

UPSERT_COLUMNS = (
    "name",
    "description",
    "cost_price",
    "retail_price",
    "compare_at_price",
    "wholesale_price",
    "stock",
    "is_active",
    "category_id",
)


class ProductRepository(BaseRepository[Product]):
    model = Product

    async def get_by_skus(self, skus: Sequence[str]) -> dict[str, Product]:
        rows = await self.session.scalars(select(Product).where(Product.sku.in_(skus)))
        return {p.sku: p for p in rows.unique()}

    async def bulk_upsert(self, rows: list[dict[str, Any]]) -> tuple[int, int]:
        """
        INSERT ... ON CONFLICT (sku) DO UPDATE — одна атомарная операция на батч.
        Параметры уходят в драйвер как bind-переменные → SQL-инъекции исключены.
        Возвращает (created, updated) через системную колонку xmax (0 = вставка).
        """
        if not rows:
            return 0, 0
        stmt = pg_insert(Product).values(rows)
        stmt = stmt.on_conflict_do_update(
            index_elements=[Product.sku],
            set_={col: stmt.excluded[col] for col in UPSERT_COLUMNS if col in rows[0]},
        ).returning(Product.id, Product.__table__.c.sku, literal_column("(xmax = 0)").label("inserted"))
        result = (await self.session.execute(stmt)).all()
        created = sum(1 for r in result if r[2])
        return created, len(result) - created

    async def stream_all(self, batch_size: int = 1000) -> AsyncIterator[Product]:
        """Потоковая выгрузка для экспорта больших каталогов без загрузки всего в память."""
        # Для выгрузки нужны только колонки товара. Связи не грузим: joined-загрузка категории несовместима
        # с потоковым чтением (yield_per), а лишние запросы на фото тысячам товаров не нужны
        stream = await self.session.stream_scalars(
            select(Product)
            .options(noload(Product.category), noload(Product.images))
            .order_by(Product.id)
            .execution_options(yield_per=batch_size)
        )
        async for product in stream:
            yield product
