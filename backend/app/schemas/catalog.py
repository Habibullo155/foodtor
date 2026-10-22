from datetime import UTC, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from app.models import Product
from app.services.pricing import Audience, PriceSource, UnitPrice

# Единый формат денег в API: всегда 2 знака ("50000.00"), независимо от источника значения
MoneyOut = Annotated[Decimal, AfterValidator(lambda v: v.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))]


class WholesaleTierOut(BaseModel):
    min_quantity: int
    unit_price: MoneyOut


class PriceOut(BaseModel):
    """Цена, рассчитанная для конкретного зрителя. Себестоимость здесь не появляется никогда."""

    price: MoneyOut  # что заплатит этот пользователь за 1 шт.
    retail_price: MoneyOut
    compare_at_price: MoneyOut | None  # зачеркнуть (для B2B — розничная, для B2C — «старая» цена)
    is_wholesale: bool
    source: PriceSource
    tiers: list[WholesaleTierOut] = []  # «от 10 шт — 850 ₽, от 100 шт — 790 ₽»

    @classmethod
    def from_unit(cls, u: UnitPrice) -> "PriceOut":
        return cls(
            price=u.unit_price,
            retail_price=u.retail_price,
            compare_at_price=u.compare_at_price,
            is_wholesale=u.is_wholesale,
            source=u.source,
            tiers=[WholesaleTierOut(min_quantity=t.min_quantity, unit_price=t.unit_price) for t in u.tiers],
        )


Badge = Literal["hit", "fresh", "lowStock"]
LOW_STOCK = 5
NEW_DAYS = 14


class ProductSummaryOut(BaseModel):
    id: int
    sku: str
    name: str
    image_url: str | None
    in_stock: bool
    price: PriceOut
    brand: str | None = None
    unit: str | None = None
    category_id: int | None = None
    badges: list[Badge] = []
    stock_left: int | None = None  # только при малом остатке — точный остаток конкурентам не показываем
    attributes: dict[str, str] = {}
    rating: float | None = None
    reviews_count: int = 0

    @classmethod
    def build(cls, p: Product, price: UnitPrice, rating: tuple[float, int] | None = None) -> "ProductSummaryOut":
        low = 0 < p.stock <= LOW_STOCK
        badges: list[Badge] = []
        if p.is_hit:
            badges.append("hit")
        created = p.created_at
        if created is not None and created >= datetime.now(UTC) - timedelta(days=NEW_DAYS):
            badges.append("fresh")
        if low:
            badges.append("lowStock")
        return cls(
            id=p.id,
            sku=p.sku,
            name=p.name,
            image_url=p.images[0].url if p.images else None,
            in_stock=p.stock > 0,
            price=PriceOut.from_unit(price),
            brand=p.brand,
            unit=p.unit,
            category_id=p.category_id,
            badges=badges,
            stock_left=p.stock if low else None,
            attributes={k: str(v) for k, v in (p.attributes or {}).items()},
            rating=round(rating[0], 1) if rating else None,
            reviews_count=rating[1] if rating else 0,
        )


class ProductListOut(BaseModel):
    items: list[ProductSummaryOut]
    total: int
    audience: Audience


class CategoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str
    slug: str
    parent_id: int | None
    image_url: str | None = None
    products_count: int = 0


class ReviewIn(BaseModel):
    rating: int = Field(ge=1, le=5)
    text: str = Field(default="", max_length=2000)


class ReviewOut(BaseModel):
    id: int
    author: str
    rating: int
    text: str
    created_at: datetime


class ProductDetailOut(ProductSummaryOut):
    description: str
    images: list[str]
    category: str | None
    cross_sell_products: list[ProductSummaryOut]  # «С этим товаром часто покупают»
    upsell_products: list[ProductSummaryOut]  # «Похожие товары»
    audience: Audience  # клиенту для UI: показать ли B2B-бейдж


class RecommendationsOut(BaseModel):
    audience: Audience
    products: list[ProductSummaryOut]


def _unique(ids: list[int]) -> list[int]:
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate product ids")
    return ids


RelatedIds = Annotated[list[Annotated[int, Field(gt=0)]], Field(max_length=20), AfterValidator(_unique)]


class ProductRelationsIn(BaseModel):
    """PUT из админки: полная замена подборок, порядок = порядок показа."""

    cross_sell: RelatedIds = []
    upsell: RelatedIds = []
