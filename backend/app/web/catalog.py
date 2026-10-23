import re
from dataclasses import dataclass, field
from decimal import Decimal

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.catalog import ratings
from app.models import Category, Order, OrderItem, OrderStatus, Product, Review, ReviewStatus, User
from app.schemas.catalog import ProductSummaryOut
from app.services.pricing import PricingRepository, PricingService

PAGE_SIZE = 24

_TRANSLIT = dict(
    zip(
        "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
        [
            "a",
            "b",
            "v",
            "g",
            "d",
            "e",
            "e",
            "zh",
            "z",
            "i",
            "y",
            "k",
            "l",
            "m",
            "n",
            "o",
            "p",
            "r",
            "s",
            "t",
            "u",
            "f",
            "h",
            "ts",
            "ch",
            "sh",
            "sch",
            "",
            "y",
            "",
            "e",
            "yu",
            "ya",
        ],
        strict=True,
    )
)


def slugify(text: str) -> str:
    s = "".join(_TRANSLIT.get(ch, ch) for ch in text.lower())
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:80] or "tovar"


def product_url(p: Product | ProductSummaryOut) -> str:
    return f"/product/{p.id}-{slugify(p.name)}"


@dataclass
class Filters:
    q: str = ""
    category: Category | None = None
    brands: list[str] = field(default_factory=list)
    price_min: Decimal | None = None
    price_max: Decimal | None = None
    in_stock: bool = False
    sort: str = "popular"  # popular | price_asc | price_desc | new
    page: int = 1

    @property
    def active(self) -> int:
        return sum([bool(self.brands), self.price_min is not None or self.price_max is not None, self.in_stock])


@dataclass
class CatalogPage:
    items: list[ProductSummaryOut]
    total: int
    page: int
    pages: int
    brands: list[tuple[str, int]]  # фасет «Бренд» с количеством
    price_range: tuple[Decimal, Decimal] | None


async def summaries(session: AsyncSession, products: list[Product]) -> list[ProductSummaryOut]:
    """Розничные цены (страницы видят все, в т.ч. поисковики) + рейтинг — как у /api/v1/products."""
    if not products:
        return []
    _, prices = await PricingService(PricingRepository(session)).price_many(None, products)
    rates = await ratings(session, [p.id for p in products])
    return [ProductSummaryOut.build(p, prices[p.id], rates.get(p.id)) for p in products]


async def categories(session: AsyncSession) -> list[tuple[Category, int]]:
    counts = dict(
        (
            await session.execute(
                select(Product.category_id, func.count()).where(Product.listed).group_by(Product.category_id)
            )
        )
        .tuples()
        .all()
    )
    cats = (
        await session.scalars(select(Category).where(Category.is_visible).order_by(Category.position, Category.name))
    ).all()
    return [(c, counts.get(c.id, 0)) for c in cats if counts.get(c.id)]


async def category_by_slug(session: AsyncSession, slug: str) -> Category | None:
    return await session.scalar(select(Category).where(Category.slug == slug, Category.is_visible))


async def catalog(session: AsyncSession, f: Filters) -> CatalogPage:
    base = [Product.listed]
    if f.q:
        pattern = "%" + f.q.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_") + "%"
        base.append(or_(Product.name.ilike(pattern), Product.brand.ilike(pattern)))
    if f.category is not None:
        base.append(Product.category_id == f.category.id)

    # фасеты считаем без фильтров по бренду/цене — чтобы можно было переключаться
    brands = (
        (
            await session.execute(
                select(Product.brand, func.count())
                .where(*base, Product.brand.is_not(None))
                .group_by(Product.brand)
                .order_by(func.count().desc(), Product.brand)
            )
        )
        .tuples()
        .all()
    )
    lo, hi = (
        await session.execute(select(func.min(Product.retail_price), func.max(Product.retail_price)).where(*base))
    ).one()

    conds = list(base)
    if f.brands:
        conds.append(Product.brand.in_(f.brands))
    if f.price_min is not None:
        conds.append(Product.retail_price >= f.price_min)
    if f.price_max is not None:
        conds.append(Product.retail_price <= f.price_max)
    if f.in_stock:
        conds.append(Product.stock > 0)

    sold = (
        select(func.coalesce(func.sum(OrderItem.quantity), 0))
        .join(Order, Order.id == OrderItem.order_id)
        .where(OrderItem.product_id == Product.id, Order.status == OrderStatus.DELIVERED)
        .correlate(Product)
        .scalar_subquery()
    )
    ordering = {
        "popular": ((Product.stock > 0).desc(), Product.is_hit.desc(), sold.desc()),
        "price_asc": (Product.retail_price.asc(),),
        "price_desc": (Product.retail_price.desc(),),
        "new": (Product.created_at.desc(),),
    }.get(f.sort, ((Product.stock > 0).desc(), sold.desc()))

    total = await session.scalar(select(func.count()).select_from(Product).where(*conds)) or 0
    pages = max(1, -(-total // PAGE_SIZE))
    page = min(max(1, f.page), pages)
    rows = (
        (
            await session.scalars(
                select(Product)
                .where(*conds)
                .order_by(*ordering, Product.id)
                .offset((page - 1) * PAGE_SIZE)
                .limit(PAGE_SIZE)
            )
        )
        .unique()
        .all()
    )
    return CatalogPage(
        items=await summaries(session, list(rows)),
        total=total,
        page=page,
        pages=pages,
        brands=[(b, n) for b, n in brands],
        price_range=(lo, hi) if lo is not None else None,
    )


async def rail(
    session: AsyncSession, *, hits: bool = False, sale: bool = False, limit: int = 12
) -> list[ProductSummaryOut]:
    conds = [Product.listed, Product.stock > 0]
    if hits:
        conds.append(Product.is_hit)
    order = [Product.id]
    if sale:
        conds += [Product.compare_at_price.is_not(None), Product.compare_at_price > Product.retail_price]
        order.insert(0, Product.retail_price / Product.compare_at_price)  # самые большие скидки — первыми
    rows = (await session.scalars(select(Product).where(*conds).order_by(*order).limit(limit))).unique().all()
    return await summaries(session, list(rows))


@dataclass
class ReviewView:
    author: str
    rating: int
    text: str
    created_at: object


async def product_reviews(session: AsyncSession, product_id: int, limit: int = 20) -> list[ReviewView]:
    rows = await session.execute(
        select(Review, User.full_name)
        .join(User, User.id == Review.user_id)
        .where(Review.product_id == product_id, Review.status == ReviewStatus.APPROVED)
        .order_by(Review.created_at.desc())
        .limit(limit)
    )
    out = []
    for r, name in rows:
        parts = (name or "Покупатель").split()
        short = f"{parts[0]} {parts[1][0]}." if len(parts) > 1 else parts[0]  # фамилию целиком не показываем
        out.append(ReviewView(short, r.rating, r.text, r.created_at))
    return out


async def all_for_sitemap(session: AsyncSession) -> tuple[list[Category], list[Product]]:
    cats = (await session.scalars(select(Category).where(Category.is_visible))).all()
    prods = (await session.scalars(select(Product).where(Product.listed))).unique().all()
    return list(cats), list(prods)
