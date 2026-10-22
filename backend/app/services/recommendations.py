"""
Гибридные рекомендации.

Cross-sell («С этим часто покупают») — смесь сигналов:
    score = 3.0 · manual        ручные связи из админки (вес убывает с позицией)
          + 2.0 · affinity      «покупали вместе»: заказы, где товар встречался с позициями корзины,
                                нормированные на √(популярность) — иначе всегда побеждают хиты (бананы)
          + 0.3 · popularity    log-популярность — «холодный старт», пока истории заказов мало
Затем — разнообразие: не больше MAX_PER_CATEGORY товаров одной категории подряд в выдаче.

Upsell («Похожие товары»): ручные связи, а если их нет — та же категория, цена ×1.0…×1.8.

Ранжирование — чистая функция `rank_candidates` (тестируется без БД);
SQL только собирает сигналы. Для больших каталогов affinity стоит считать ночным джобом
в таблицу product_affinity — интерфейс сервиса при этом не меняется.
"""

import math
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models import Order, OrderItem, OrderStatus, Product, ProductRelation, RelationKind

W_MANUAL, W_AFFINITY, W_POPULARITY = 3.0, 2.0, 0.3
MAX_PER_CATEGORY = 2
HISTORY_DAYS = 180
CANDIDATE_POOL = 200


@dataclass(frozen=True, slots=True)
class Candidate:
    product_id: int
    category_id: int | None
    score: float


def rank_candidates(
    *,
    manual: Mapping[int, float],
    together: Mapping[int, int],
    popularity: Mapping[int, int],
    categories: Mapping[int, int | None],
    exclude: Iterable[int],
    limit: int,
    max_per_category: int = MAX_PER_CATEGORY,
) -> list[Candidate]:
    excluded = set(exclude)
    ids = (set(manual) | set(together) | set(popularity)) - excluded
    ids &= set(categories)  # только продаваемые (categories содержит лишь активные товары в наличии)

    max_pop = max((popularity.get(i, 0) for i in ids), default=0)
    scored = []
    for pid in ids:
        pop = popularity.get(pid, 0)
        affinity = together.get(pid, 0) / math.sqrt(pop) if pop else float(together.get(pid, 0))
        pop_norm = math.log1p(pop) / math.log1p(max_pop) if max_pop else 0.0
        score = W_MANUAL * manual.get(pid, 0.0) + W_AFFINITY * affinity + W_POPULARITY * pop_norm
        if score > 0:
            scored.append(Candidate(pid, categories[pid], score))
    scored.sort(key=lambda c: (-c.score, c.product_id))

    # Жадный ре-ранкинг на разнообразие: лишние товары категории уходят в «хвост», а не исчезают
    picked: list[Candidate] = []
    overflow: list[Candidate] = []
    per_cat: dict[int | None, int] = {}
    for c in scored:
        if per_cat.get(c.category_id, 0) < max_per_category:
            picked.append(c)
            per_cat[c.category_id] = per_cat.get(c.category_id, 0) + 1
        else:
            overflow.append(c)
        if len(picked) == limit:
            break
    return (picked + overflow)[:limit]


def _sellable():
    return (Product.is_active, Product.stock > 0)


class RecommendationService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def _manual(self, source_ids: Sequence[int], kind: RelationKind) -> dict[int, float]:
        rows = await self.session.execute(
            select(ProductRelation.target_id, ProductRelation.position).where(
                ProductRelation.source_id.in_(source_ids), ProductRelation.kind == kind
            )
        )
        weights: dict[int, float] = {}
        for target, position in rows:
            weights[target] = weights.get(target, 0.0) + 1 / (1 + 0.15 * position)
        return weights

    async def _together(self, source_ids: Sequence[int]) -> dict[int, int]:
        a, b = aliased(OrderItem), aliased(OrderItem)
        since = datetime.now(UTC) - timedelta(days=HISTORY_DAYS)
        stmt = (
            select(b.product_id, func.count(func.distinct(b.order_id)))
            .select_from(a)
            .join(b, and_(a.order_id == b.order_id, b.product_id != a.product_id))
            .join(Order, Order.id == a.order_id)
            .where(
                a.product_id.in_(source_ids),
                b.product_id.is_not(None),
                Order.status == OrderStatus.DELIVERED,
                Order.created_at >= since,
            )
            .group_by(b.product_id)
            .order_by(func.count(func.distinct(b.order_id)).desc())
            .limit(CANDIDATE_POOL)
        )
        return {pid: n for pid, n in await self.session.execute(stmt)}

    async def _popularity(self, product_ids: Iterable[int] | None = None) -> dict[int, int]:
        since = datetime.now(UTC) - timedelta(days=HISTORY_DAYS)
        stmt = (
            select(OrderItem.product_id, func.count(func.distinct(OrderItem.order_id)))
            .join(Order, Order.id == OrderItem.order_id)
            .where(Order.status == OrderStatus.DELIVERED, Order.created_at >= since, OrderItem.product_id.is_not(None))
            .group_by(OrderItem.product_id)
        )
        if product_ids is not None:
            stmt = stmt.where(OrderItem.product_id.in_(list(product_ids)))
        else:
            stmt = stmt.order_by(func.count(func.distinct(OrderItem.order_id)).desc()).limit(CANDIDATE_POOL)
        return {pid: n for pid, n in await self.session.execute(stmt)}

    async def _sellable_categories(self, ids: Iterable[int]) -> dict[int, int | None]:
        ids = list(ids)
        if not ids:
            return {}
        rows = await self.session.execute(
            select(Product.id, Product.category_id).where(Product.id.in_(ids), *_sellable())
        )
        return dict(rows.tuples().all())

    async def _load(self, ids: Sequence[int]) -> list[Product]:
        if not ids:
            return []
        products = {p.id: p for p in (await self.session.scalars(select(Product).where(Product.id.in_(ids)))).unique()}
        return [products[i] for i in ids if i in products]

    async def cross_sell(self, source_ids: Sequence[int], limit: int = 8) -> list[Product]:
        source_ids = list(dict.fromkeys(source_ids))
        if not source_ids:
            return []
        manual = await self._manual(source_ids, RelationKind.CROSS_SELL)
        together = await self._together(source_ids)
        popularity = await self._popularity()
        candidate_ids = set(manual) | set(together) | set(popularity)
        popularity |= await self._popularity(candidate_ids - set(popularity))
        categories = await self._sellable_categories(candidate_ids)
        ranked = rank_candidates(
            manual=manual,
            together=together,
            popularity=popularity,
            categories=categories,
            exclude=source_ids,
            limit=limit,
        )
        return await self._load([c.product_id for c in ranked])

    async def similar(self, product: Product, limit: int = 8) -> list[Product]:
        """Upsell: ручные связи → иначе та же категория чуть дороже (×1.0…×1.8), ближе по цене — выше."""
        manual = await self._manual([product.id], RelationKind.UPSELL)
        manual_sellable = await self._sellable_categories(manual)
        ordered = sorted(manual_sellable, key=lambda i: -manual[i])
        if len(ordered) >= limit or product.category_id is None:
            return await self._load(ordered[:limit])

        price = product.retail_price
        fallback = await self.session.scalars(
            select(Product.id)
            .where(
                Product.category_id == product.category_id,
                Product.id != product.id,
                Product.id.not_in(ordered) if ordered else True,
                Product.retail_price >= price,
                Product.retail_price <= price * 18 / 10,
                *_sellable(),
            )
            .order_by(func.abs(Product.retail_price - price * 13 / 10))
            .limit(limit - len(ordered))
        )
        return await self._load([*ordered, *fallback])
