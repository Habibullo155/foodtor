from collections.abc import Sequence

from sqlalchemy import delete, func, select
from sqlalchemy.orm import selectinload

from app.models import Product, ProductRelation, RelationKind
from app.repositories.base import BaseRepository

MAX_RELATED = 12


def _sellable():
    return (Product.listed, Product.stock > 0)


class CatalogRepository(BaseRepository[Product]):
    model = Product

    async def get_active(self, product_id: int) -> Product | None:
        return await self.session.scalar(select(Product).where(Product.id == product_id, Product.listed))

    async def get_with_relations(self, product_id: int) -> Product | None:
        """Товар + обе подборки за 3 запроса (основной + 2 selectin), без N+1."""
        stmt = (
            select(Product)
            .where(Product.id == product_id, Product.listed)
            .options(selectinload(Product.cross_sell_products), selectinload(Product.upsell_products))
        )
        return (await self.session.scalars(stmt)).unique().one_or_none()

    async def cross_sell_for(self, product_ids: Sequence[int], limit: int = MAX_RELATED) -> Sequence[Product]:
        """
        Рекомендации для корзины: объединяем cross-sell всех её товаров.
        Ранжирование: сколько товаров корзины рекомендуют кандидата (соус подходит и к пасте, и к фаршу → выше),
        затем ручной порядок из админки. Товары, уже лежащие в корзине, исключаются.
        """
        if not product_ids:
            return []
        hits = func.count().label("hits")
        ranked = (
            select(ProductRelation.target_id, hits, func.min(ProductRelation.position).label("pos"))
            .join(Product, Product.id == ProductRelation.target_id)
            .where(
                ProductRelation.source_id.in_(product_ids),
                ProductRelation.kind == RelationKind.CROSS_SELL,
                ProductRelation.target_id.not_in(product_ids),
                *_sellable(),
            )
            .group_by(ProductRelation.target_id)
            .order_by(hits.desc(), func.min(ProductRelation.position))
            .limit(limit)
        ).subquery()
        stmt = (
            select(Product).join(ranked, ranked.c.target_id == Product.id).order_by(ranked.c.hits.desc(), ranked.c.pos)
        )
        return (await self.session.scalars(stmt)).unique().all()

    async def existing_ids(self, ids: Sequence[int]) -> set[int]:
        return set(await self.session.scalars(select(Product.id).where(Product.id.in_(ids))))

    async def replace_relations(self, source_id: int, kind: RelationKind, target_ids: Sequence[int]) -> None:
        """Полная замена подборки: порядок в списке = порядок показа."""
        await self.session.execute(
            delete(ProductRelation).where(ProductRelation.source_id == source_id, ProductRelation.kind == kind)
        )
        self.session.add_all(
            ProductRelation(source_id=source_id, target_id=t, kind=kind, position=i) for i, t in enumerate(target_ids)
        )


def visible_related(products: Sequence[Product]) -> list[Product]:
    """Фильтр для подборок карточки: не рекламируем то, что нельзя купить."""
    return [p for p in products if p.listed and p.stock > 0][:MAX_RELATED]
