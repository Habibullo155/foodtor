"""
Одна точка истины для цены: карточка товара, каталог, рекомендации, корзина и оформление заказа
вызывают PricingService — поэтому цена в UI и в заказе совпадает до копейки.
"""

import enum
from collections import defaultdict
from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CategoryDiscount, PriceList, PriceListItem, Product, User

CENT = Decimal("0.01")


class Audience(str, enum.Enum):
    ANONYMOUS = "anonymous"
    B2C = "b2c"
    B2B = "b2b"  # только подтверждённый оптовик


class PriceSource(str, enum.Enum):
    RETAIL = "retail"
    WHOLESALE = "wholesale"  # оптовая цена из карточки товара
    PRICE_LIST = "price_list"  # явная оптовая цена (с учётом объёма)
    CATEGORY_DISCOUNT = "category_discount"
    LIST_DISCOUNT = "list_discount"  # общая скидка прайс-листа


@dataclass(frozen=True, slots=True)
class WholesaleTier:
    min_quantity: int
    unit_price: Decimal


@dataclass(frozen=True, slots=True)
class UnitPrice:
    unit_price: Decimal  # итоговая цена за единицу для этого зрителя и количества
    retail_price: Decimal
    compare_at_price: Decimal | None  # что зачеркнуть в UI
    source: PriceSource
    tiers: tuple[WholesaleTier, ...] = ()  # лестница оптовых цен (только B2B)

    @property
    def is_wholesale(self) -> bool:
        return self.source is not PriceSource.RETAIL


@dataclass(slots=True)
class PricingRules:
    """Правила одного прайс-листа, загруженные только для нужных товаров/категорий."""

    price_list_name: str
    default_percent: Decimal = Decimal("0")
    # product_id → [(min_qty, price)] по возрастанию min_qty
    items: dict[int, list[tuple[int, Decimal]]] = field(default_factory=dict)
    category_percent: dict[int, Decimal] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class PricingContext:
    audience: Audience
    rules: PricingRules | None = None

    @property
    def is_wholesale(self) -> bool:
        return self.audience is Audience.B2B


def _money(v: Decimal) -> Decimal:
    return v.quantize(CENT, rounding=ROUND_HALF_UP)


def _apply_percent(price: Decimal, percent: Decimal) -> Decimal:
    return _money(price * (100 - percent) / 100)


def price_for(product: Product, ctx: PricingContext, quantity: int = 1) -> UnitPrice:
    retail = product.retail_price
    if not ctx.is_wholesale:
        return UnitPrice(retail, retail, product.compare_at_price, PriceSource.RETAIL)

    rules = ctx.rules or PricingRules(price_list_name="")
    ladder = rules.items.get(product.id, [])
    tiers = tuple(WholesaleTier(q, min(p, retail)) for q, p in ladder)

    # Приоритет: цена прайса по объёму → оптовая цена товара → скидка категории → общая скидка прайса → розница
    applicable = [p for q, p in ladder if q <= quantity]
    if applicable:
        price, source = applicable[-1], PriceSource.PRICE_LIST
    elif product.wholesale_price is not None:
        price, source = product.wholesale_price, PriceSource.WHOLESALE
    elif (pct := rules.category_percent.get(product.category_id or -1)) is not None:
        price, source = _apply_percent(retail, pct), PriceSource.CATEGORY_DISCOUNT
    elif rules.default_percent > 0:
        price, source = _apply_percent(retail, rules.default_percent), PriceSource.LIST_DISCOUNT
    else:
        return UnitPrice(retail, retail, product.compare_at_price, PriceSource.RETAIL, tiers)

    price = min(price, retail)  # оптовая цена выше розничной — ошибка настройки, клиент не переплачивает
    if price == retail:
        return UnitPrice(retail, retail, product.compare_at_price, PriceSource.RETAIL, tiers)
    # B2B видит зачёркнутую розничную рядом со своей оптовой
    return UnitPrice(price, retail, retail, source, tiers)


class PricingRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def load_rules(self, price_list_id: int, products: Iterable[Product]) -> PricingRules | None:
        products = list(products)
        today = datetime.now(UTC).date()
        price_list = await self.session.scalar(
            select(PriceList).where(
                PriceList.id == price_list_id,
                PriceList.is_active,
                or_(PriceList.valid_from.is_(None), PriceList.valid_from <= today),
                or_(PriceList.valid_to.is_(None), PriceList.valid_to >= today),
            )
        )
        if price_list is None:
            return None  # прайс выключен или истёк → оптовик временно видит розницу

        product_ids = {p.id for p in products}
        category_ids = {p.category_id for p in products if p.category_id is not None}

        items: dict[int, list[tuple[int, Decimal]]] = defaultdict(list)
        rows = await self.session.execute(
            select(PriceListItem.product_id, PriceListItem.min_quantity, PriceListItem.unit_price)
            .where(PriceListItem.price_list_id == price_list_id, PriceListItem.product_id.in_(product_ids))
            .order_by(PriceListItem.product_id, PriceListItem.min_quantity)
        )
        for product_id, min_qty, unit_price in rows:
            items[product_id].append((min_qty, unit_price))

        category_percent: dict[int, Decimal] = {}
        if category_ids:
            rows = await self.session.execute(
                select(CategoryDiscount.category_id, CategoryDiscount.percent).where(
                    CategoryDiscount.price_list_id == price_list_id, CategoryDiscount.category_id.in_(category_ids)
                )
            )
            category_percent = dict(rows.tuples().all())

        return PricingRules(
            price_list_name=price_list.name,
            default_percent=price_list.default_discount_percent,
            items=dict(items),
            category_percent=category_percent,
        )


class PricingService:
    def __init__(self, repo: PricingRepository) -> None:
        self.repo = repo

    async def context_for(self, user: User | None, products: Iterable[Product]) -> PricingContext:
        if user is None:
            return PricingContext(Audience.ANONYMOUS)
        if not user.is_verified_b2b:
            return PricingContext(Audience.B2C)  # включая заявки на проверке
        price_list_id = user.wholesale_price_list_id
        rules = await self.repo.load_rules(price_list_id, products) if price_list_id else None
        return PricingContext(Audience.B2B, rules)

    async def price_many(
        self, user: User | None, products: Iterable[Product], quantities: Mapping[int, int] | None = None
    ) -> tuple[PricingContext, dict[int, UnitPrice]]:
        """Батч: одна загрузка правил на весь набор (товар + рекомендации / вся корзина)."""
        products = list(products)
        ctx = await self.context_for(user, products)
        qty = quantities or {}
        return ctx, {p.id: price_for(p, ctx, qty.get(p.id, 1)) for p in products}
