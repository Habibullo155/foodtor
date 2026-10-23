"""Публичный каталог. Цена в ответе зависит от того, КТО спрашивает: аноним / B2C / подтверждённый B2B."""

from decimal import Decimal
from enum import Enum
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel
from sqlalchemy import exists, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import CurrentUser, OptionalUser, SessionDep, get_pricing_service, get_recommendation_service
from app.models import Category, Order, OrderItem, OrderStatus, Product, Review, ReviewStatus, User
from app.repositories.catalog import CatalogRepository
from app.schemas.catalog import (
    CategoryOut,
    PriceOut,
    ProductDetailOut,
    ProductListOut,
    ProductSummaryOut,
    RecommendationsOut,
    ReviewIn,
    ReviewOut,
)
from app.services.pricing import Audience, PricingService
from app.services.recommendations import RecommendationService

router = APIRouter(prefix="/products", tags=["catalog"])
categories_router = APIRouter(prefix="/categories", tags=["catalog"])

Pricing = Annotated[PricingService, Depends(get_pricing_service)]
Recommender = Annotated[RecommendationService, Depends(get_recommendation_service)]


class SortOrder(str, Enum):
    popular = "popular"
    price_asc = "price_asc"
    price_desc = "price_desc"
    new = "new"


def _cache_headers(response: Response, personalized: bool) -> None:
    # Ответ персонализирован → его нельзя класть в общий CDN-кэш, иначе аноним увидит оптовые цены.
    response.headers["Vary"] = "Authorization"
    response.headers["Cache-Control"] = "private, no-store" if personalized else "public, max-age=60"


async def ratings(session: AsyncSession, ids: list[int]) -> dict[int, tuple[float, int]]:
    """Средняя оценка и число опубликованных отзывов — одним запросом на всю выдачу."""
    if not ids:
        return {}
    rows = await session.execute(
        select(Review.product_id, func.avg(Review.rating), func.count())
        .where(Review.product_id.in_(ids), Review.status == ReviewStatus.APPROVED)
        .group_by(Review.product_id)
    )
    return {pid: (float(avg), n) for pid, avg, n in rows}


async def _summaries(session, pricing, user, products):
    ctx, prices = await pricing.price_many(user, products)
    rates = await ratings(session, [p.id for p in products])
    return ctx, [ProductSummaryOut.build(p, prices[p.id], rates.get(p.id)) for p in products]


@categories_router.get("", response_model=list[CategoryOut])
async def list_categories(session: SessionDep, response: Response) -> list[CategoryOut]:
    counts = dict(
        (
            await session.execute(
                select(Product.category_id, func.count()).where(Product.listed).group_by(Product.category_id)
            )
        )
        .tuples()
        .all()
    )
    response.headers["Cache-Control"] = "public, max-age=300"
    cats = (
        await session.scalars(select(Category).where(Category.is_visible).order_by(Category.position, Category.name))
    ).all()
    return [
        CategoryOut(
            id=c.id,
            name=c.name,
            slug=c.slug,
            parent_id=c.parent_id,
            image_url=c.image_url,
            products_count=counts.get(c.id, 0),
        )
        for c in cats
    ]


@router.get("", response_model=ProductListOut)
async def list_products(
    session: SessionDep,
    pricing: Pricing,
    user: OptionalUser,
    response: Response,
    q: Annotated[str | None, Query(max_length=100)] = None,
    category_id: int | None = None,
    brand: Annotated[list[str] | None, Query(max_length=20)] = None,
    price_min: Annotated[Decimal | None, Query(ge=0)] = None,
    price_max: Annotated[Decimal | None, Query(ge=0)] = None,
    in_stock: bool = False,
    sort: SortOrder = SortOrder.popular,
    limit: Annotated[int, Query(ge=1, le=500)] = 60,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> ProductListOut:
    """Фильтр по цене — по розничной (оптовая зависит от количества и считается при выдаче)."""
    conds = [Product.listed]
    if q:
        # ILIKE с bind-параметром; экранируем % и _ из пользовательского ввода
        pattern = "%" + q.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_") + "%"
        conds.append(or_(Product.name.ilike(pattern), Product.brand.ilike(pattern)))
    if category_id is not None:
        conds.append(Product.category_id == category_id)
    if brand:
        conds.append(Product.brand.in_(brand))
    if price_min is not None:
        conds.append(Product.retail_price >= price_min)
    if price_max is not None:
        conds.append(Product.retail_price <= price_max)
    if in_stock:
        conds.append(Product.stock > 0)

    sold = (
        select(func.coalesce(func.sum(OrderItem.quantity), 0))
        .join(Order, Order.id == OrderItem.order_id)
        .where(OrderItem.product_id == Product.id, Order.status == OrderStatus.DELIVERED)
        .correlate(Product)
        .scalar_subquery()
    )
    ordering = {
        # «Популярные»: сначала в наличии, затем по продажам
        SortOrder.popular: ((Product.stock > 0).desc(), sold.desc()),
        SortOrder.price_asc: (Product.retail_price.asc(),),
        SortOrder.price_desc: (Product.retail_price.desc(),),
        SortOrder.new: (Product.created_at.desc(),),
    }[sort]

    total = await session.scalar(select(func.count()).select_from(Product).where(*conds))
    products = (
        (
            await session.scalars(
                select(Product).where(*conds).order_by(*ordering, Product.id).offset(offset).limit(limit)
            )
        )
        .unique()
        .all()
    )
    ctx, items = await _summaries(session, pricing, user, list(products))
    _cache_headers(response, personalized=user is not None)
    return ProductListOut(items=items, total=total or 0, audience=ctx.audience)


@router.get("/recommendations", response_model=RecommendationsOut)
async def cart_recommendations(
    session: SessionDep,
    recommender: Recommender,
    pricing: Pricing,
    user: OptionalUser,
    response: Response,
    ids: Annotated[list[int], Query(min_length=1, max_length=50, description="id товаров в корзине")],
    limit: Annotated[int, Query(ge=1, le=20)] = 8,
) -> RecommendationsOut:
    """
    Блок «С этим часто покупают» в корзине. Работает и для гостевой (локальной) корзины,
    поэтому принимает id товаров, а не читает серверную корзину.
    """
    products = await recommender.cross_sell(ids, limit)
    ctx, items = await _summaries(session, pricing, user, products)
    _cache_headers(response, personalized=user is not None)
    return RecommendationsOut(audience=ctx.audience, products=items)


class ProductPriceOut(BaseModel):
    id: int
    price: PriceOut


class PricesOut(BaseModel):
    audience: Audience
    items: list[ProductPriceOut]


@router.get("/prices", response_model=PricesOut)
async def prices(
    session: SessionDep,
    pricing: Pricing,
    user: CurrentUser,
    response: Response,
    ids: Annotated[list[int], Query(min_length=1, max_length=200)],
) -> PricesOut:
    """Цены «для меня» по списку товаров: сайт отдаёт всем розничные страницы, а оптовику подставляет его цены."""
    products = (await session.scalars(select(Product).where(Product.id.in_(ids), Product.listed))).unique().all()
    ctx, unit = await pricing.price_many(user, products)
    _cache_headers(response, personalized=True)
    return PricesOut(
        audience=ctx.audience, items=[ProductPriceOut(id=p.id, price=PriceOut.from_unit(unit[p.id])) for p in products]
    )


@router.get("/{product_id}", response_model=ProductDetailOut)
async def get_product(
    product_id: int,
    session: SessionDep,
    pricing: Pricing,
    recommender: Recommender,
    user: OptionalUser,
    response: Response,
) -> ProductDetailOut:
    product = await CatalogRepository(session).get_active(product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")

    # Ручные связи из админки входят в рекомендатель как самый сильный сигнал
    cross_sell = await recommender.cross_sell([product.id])
    upsell = await recommender.similar(product)

    # Один расчёт на товар + обе подборки: правила прайс-листа загружаются один раз
    ctx, items = await _summaries(session, pricing, user, [product, *cross_sell, *upsell])
    _cache_headers(response, personalized=user is not None)

    summary, rest = items[0], items[1:]
    return ProductDetailOut(
        **summary.model_dump(exclude={"price"}),
        price=summary.price,
        description=product.description,
        images=[img.url for img in product.images],
        category=product.category.name if product.category else None,
        cross_sell_products=rest[: len(cross_sell)],
        upsell_products=rest[len(cross_sell) :],
        audience=ctx.audience,
    )


def _short_name(full: str) -> str:
    """«Мария Кузнецова» → «Мария К.» — фамилию целиком публично не показываем."""
    parts = full.split()
    return f"{parts[0]} {parts[1][0]}." if len(parts) > 1 else (parts[0] if parts else "Покупатель")


@router.get("/{product_id}/reviews", response_model=list[ReviewOut])
async def product_reviews(product_id: int, session: SessionDep, limit: Annotated[int, Query(ge=1, le=100)] = 20):
    rows = await session.execute(
        select(Review, User.full_name)
        .join(User, User.id == Review.user_id)
        .where(Review.product_id == product_id, Review.status == ReviewStatus.APPROVED)
        .order_by(Review.created_at.desc())
        .limit(limit)
    )
    return [
        ReviewOut(id=r.id, author=_short_name(name), rating=r.rating, text=r.text, created_at=r.created_at)
        for r, name in rows
    ]


@router.post("/{product_id}/reviews", status_code=status.HTTP_201_CREATED)
async def create_review(product_id: int, body: ReviewIn, session: SessionDep, user: CurrentUser) -> dict:
    """Отзыв могут оставить только покупатели, получившие этот товар. Публикуется после модерации."""
    bought = await session.scalar(
        select(
            exists().where(
                OrderItem.product_id == product_id,
                OrderItem.order_id == Order.id,
                Order.user_id == user.id,
                Order.status == OrderStatus.DELIVERED,
            )
        )
    )
    if not bought:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Review is allowed after the product is delivered")
    existing = await session.scalar(select(Review).where(Review.product_id == product_id, Review.user_id == user.id))
    if existing is not None:
        existing.rating, existing.text, existing.status = body.rating, body.text, ReviewStatus.PENDING
    else:
        session.add(Review(product_id=product_id, user_id=user.id, rating=body.rating, text=body.text))
    return {"status": "pending"}
