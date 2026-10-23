"""API админ-панели. Каждый эндпоинт закрыт конкретным правом (RBAC), а не ролью."""

from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from sqlalchemy import Date, cast, func, select, update
from sqlalchemy.orm import selectinload

from app.api.deps import PermissionsDep, SessionDep, require
from app.api.v1.orders import order_out
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.core.security import hash_password, password_problem
from app.models import (
    Category,
    DiscountType,
    Expense,
    LoyaltyTier,
    Order,
    OrderStatus,
    PaymentStatus,
    Permission,
    Product,
    ProductImage,
    PromoCode,
    RefreshToken,
    Review,
    ReviewStatus,
    Role,
    SystemRole,
    User,
)
from app.schemas.catalog import MoneyOut
from app.schemas.orders import AdminOrderOut, DayOut, FinanceOut, Totals
from app.services import images
from app.services.bootstrap import ensure_system_roles

router = APIRouter(prefix="/admin", tags=["admin"])


def guard(*perms: Permission):
    return Depends(require(*perms))


async def _admin_order(session, o: Order) -> AdminOrderOut:
    user = await session.get(User, o.user_id)
    profit = o.total - o.shipping_price - o.cost_total - o.expenses_total
    return await order_out(
        session,
        o,
        AdminOrderOut,
        customer_name=o.customer_name or (user.full_name if user else ""),
        customer_phone=o.customer_phone,
        customer_email=(user.email or user.phone_e164 or "") if user else "",
        address=o.shipping_address,
        note=o.customer_note,
        segment=o.customer_segment,
        subtotal=o.subtotal,
        discounts=o.loyalty_discount + o.promo_discount,
        cost_total=o.cost_total,
        expenses_total=o.expenses_total,
        profit=profit,
    )


@router.get("/orders", response_model=list[AdminOrderOut], dependencies=[guard(Permission.ORDERS_READ_ALL)])
async def admin_orders(
    session: SessionDep,
    status_: Annotated[OrderStatus | None, Query(alias="status")] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 100,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    stmt = (
        select(Order).options(selectinload(Order.items)).order_by(Order.created_at.desc()).offset(offset).limit(limit)
    )
    if status_ is not None:
        stmt = stmt.where(Order.status == status_)
    return [await _admin_order(session, o) for o in (await session.scalars(stmt)).all()]


@router.get("/orders/{order_id}", response_model=AdminOrderOut, dependencies=[guard(Permission.ORDERS_READ_ALL)])
async def admin_order(order_id: int, session: SessionDep):
    order = await session.get(Order, order_id)
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    return await _admin_order(session, order)


@router.get("/finance", response_model=FinanceOut, dependencies=[guard(Permission.DASHBOARD_VIEW)])
async def finance(session: SessionDep, perms: PermissionsDep, days: Annotated[int, Query(ge=1, le=366)] = 14):
    """
    Выручка — заказы, которые не отменены и оплачены (или с оплатой при получении).
    Расходы = себестоимость + наша доставка/эквайринг по заказам + операционные расходы периода.
    """
    tz = get_settings().timezone
    today = datetime.now(ZoneInfo(tz)).date()
    start = today - timedelta(days=days * 2 - 1)
    day = cast(func.timezone(tz, Order.created_at), Date).label("day")
    rows = await session.execute(
        select(
            day,
            func.sum(Order.total - Order.shipping_price),
            func.sum(Order.cost_total + Order.expenses_total),
            func.count(),
        )
        .where(
            Order.status != OrderStatus.CANCELLED,
            Order.payment_status.in_((PaymentStatus.PAID, PaymentStatus.NOT_REQUIRED)),
            Order.created_at >= datetime.combine(start, datetime.min.time(), ZoneInfo(tz)),
        )
        .group_by(day)
    )
    by_day: dict[date, list] = {d: [Decimal(r or 0), Decimal(e or 0), n] for d, r, e, n in rows}
    opex = await session.execute(
        select(Expense.incurred_on, func.sum(Expense.amount))
        .where(Expense.order_id.is_(None), Expense.incurred_on >= start)
        .group_by(Expense.incurred_on)
    )
    for d, amount in opex:
        by_day.setdefault(d, [Decimal(0), Decimal(0), 0])[1] += Decimal(amount)

    series = [
        DayOut(
            day=(d := start + timedelta(days=i)).isoformat(),
            revenue=by_day.get(d, [0, 0, 0])[0],
            expenses=by_day.get(d, [0, 0, 0])[1],
            orders=by_day.get(d, [0, 0, 0])[2],
        )
        for i in range(days * 2)
    ]
    show_profit = Permission.FINANCE_VIEW in perms

    def totals(chunk: list[DayOut]) -> Totals:
        revenue = sum((x.revenue for x in chunk), Decimal(0))
        expenses = sum((x.expenses for x in chunk), Decimal(0))
        n = sum(x.orders for x in chunk)
        return Totals(
            revenue=revenue,
            profit=revenue - expenses if show_profit else None,
            orders=n,
            avg_check=revenue / n if n else Decimal(0),
        )

    if not show_profit:
        for x in series:
            x.expenses = Decimal(0)
    # series — оба периода (2×days): клиент сам строит сравнение «к прошлому периоду»
    return FinanceOut(days=days, previous=totals(series[:days]), current=totals(series[days:]), series=series)


class AdminProductOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    sku: str
    name: str
    description: str
    brand: str | None
    unit: str | None
    category_id: int | None
    cost_price: MoneyOut
    retail_price: MoneyOut
    compare_at_price: MoneyOut | None
    wholesale_price: MoneyOut | None
    stock: int
    is_active: bool
    is_hit: bool
    attributes: dict
    image_url: str | None = None
    margin_percent: float = 0


def _admin_product(p: Product) -> AdminProductOut:
    out = AdminProductOut.model_validate(p)
    out.image_url = p.images[0].url if p.images else None
    out.margin_percent = (
        round(float((p.retail_price - p.cost_price) / p.retail_price * 100), 1) if p.retail_price else 0
    )
    return out


class ProductIn(BaseModel):
    sku: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9._\-]+$")
    name: str = Field(min_length=1, max_length=255)
    description: str = Field(default="", max_length=10_000)
    brand: str | None = Field(default=None, max_length=120)
    unit: str | None = Field(default=None, max_length=32)
    category_id: int | None = None
    cost_price: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    retail_price: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    compare_at_price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    wholesale_price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    stock: int = Field(default=0, ge=0, le=1_000_000)
    is_active: bool = True
    is_hit: bool = False
    attributes: dict[str, str] = Field(default_factory=dict, max_length=30)
    image_url: str | None = Field(default=None, max_length=1024, pattern=r"^(https://|/media/|/static/)")


class ProductPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=10_000)
    brand: str | None = Field(default=None, max_length=120)
    unit: str | None = Field(default=None, max_length=32)
    category_id: int | None = None
    cost_price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    retail_price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    compare_at_price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    wholesale_price: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    stock: int | None = Field(default=None, ge=0, le=1_000_000)
    is_active: bool | None = None
    is_hit: bool | None = None
    attributes: dict[str, str] | None = None
    image_url: str | None = Field(default=None, max_length=1024, pattern=r"^(https://|/media/|/static/)")


@router.get("/products", response_model=list[AdminProductOut], dependencies=[guard(Permission.PRODUCTS_READ)])
async def admin_products(
    session: SessionDep,
    q: Annotated[str | None, Query(max_length=100)] = None,
    category_id: int | None = None,
    limit: Annotated[int, Query(ge=1, le=1000)] = 500,
):
    stmt = select(Product).order_by(Product.name).limit(limit)
    if q:
        stmt = stmt.where(Product.name.ilike("%" + q.replace("%", r"\%").replace("_", r"\_") + "%"))
    if category_id is not None:
        stmt = stmt.where(Product.category_id == category_id)
    return [_admin_product(p) for p in (await session.scalars(stmt)).unique().all()]


@router.post(
    "/products", response_model=AdminProductOut, status_code=201, dependencies=[guard(Permission.PRODUCTS_WRITE)]
)
async def create_product(body: ProductIn, session: SessionDep):
    if await session.scalar(select(Product.id).where(Product.sku == body.sku)):
        raise HTTPException(status.HTTP_409_CONFLICT, "SKU already exists")
    data = body.model_dump(exclude={"image_url"})
    product = Product(**data)
    if body.image_url:
        product.images = [ProductImage(url=body.image_url, position=0)]
    session.add(product)
    await session.flush()
    await session.refresh(product, ["images"])
    return _admin_product(product)


@router.patch("/products/{product_id}", response_model=AdminProductOut, dependencies=[guard(Permission.PRODUCTS_WRITE)])
async def update_product(product_id: int, body: ProductPatch, session: SessionDep):
    product = await session.get(Product, product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    data = body.model_dump(exclude_unset=True)
    image_url = data.pop("image_url", None)
    for key, value in data.items():
        setattr(product, key, value)
    if image_url:
        product.images = [ProductImage(url=image_url, position=0)]
    await session.flush()
    await session.refresh(product, ["images"])
    return _admin_product(product)


@router.delete("/products/{product_id}", status_code=204, dependencies=[guard(Permission.PRODUCTS_WRITE)])
async def archive_product(product_id: int, session: SessionDep):
    """Мягкое удаление: товар есть в истории заказов, физически не удаляем."""
    product = await session.get(Product, product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")
    product.is_active = False


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    slug: str = Field(min_length=1, max_length=140, pattern=r"^[a-z0-9\-]+$")
    parent_id: int | None = None
    image_url: str | None = Field(default=None, max_length=1024, pattern=r"^(https://|/media/|/static/)")
    position: int = 0


@router.post("/categories", status_code=201, dependencies=[guard(Permission.PRODUCTS_WRITE)])
async def create_category(body: CategoryIn, session: SessionDep):
    if await session.scalar(select(Category.id).where(Category.slug == body.slug)):
        raise HTTPException(status.HTTP_409_CONFLICT, "Slug already exists")
    c = Category(**body.model_dump())
    session.add(c)
    await session.flush()
    return {"id": c.id}


@router.patch("/categories/{category_id}", dependencies=[guard(Permission.PRODUCTS_WRITE)])
async def update_category(category_id: int, body: CategoryIn, session: SessionDep):
    c = await session.get(Category, category_id)
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Category not found")
    for k, v in body.model_dump().items():
        setattr(c, k, v)
    return {"id": c.id}


@router.delete("/categories/{category_id}", status_code=204, dependencies=[guard(Permission.PRODUCTS_WRITE)])
async def delete_category(category_id: int, session: SessionDep):
    c = await session.get(Category, category_id)
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Category not found")
    await session.delete(c)  # товары остаются без категории (FK ON DELETE SET NULL)


class AdminReviewOut(BaseModel):
    id: int
    product_id: int
    product_name: str
    product_image: str | None
    author: str
    rating: int
    text: str
    status: ReviewStatus
    created_at: datetime


class ModerateIn(BaseModel):
    approve: bool
    reason: str | None = Field(default=None, max_length=500)


@router.get("/reviews", response_model=list[AdminReviewOut], dependencies=[guard(Permission.REVIEWS_MODERATE)])
async def admin_reviews(session: SessionDep, status_: Annotated[ReviewStatus | None, Query(alias="status")] = None):
    stmt = (
        select(Review, Product, User.full_name)
        .join(Product, Product.id == Review.product_id)
        .join(User, User.id == Review.user_id)
        .order_by(Review.created_at.desc())
        .limit(500)
    )
    if status_ is not None:
        stmt = stmt.where(Review.status == status_)
    return [
        AdminReviewOut(
            id=r.id,
            product_id=p.id,
            product_name=p.name,
            product_image=p.images[0].url if p.images else None,
            author=name,
            rating=r.rating,
            text=r.text,
            status=r.status,
            created_at=r.created_at,
        )
        for r, p, name in (await session.execute(stmt)).unique()
    ]


@router.post("/reviews/{review_id}/moderate", status_code=204)
async def moderate_review(
    review_id: int,
    body: ModerateIn,
    session: SessionDep,
    admin: Annotated[User, Depends(require(Permission.REVIEWS_MODERATE))],
):
    review = await session.get(Review, review_id)
    if review is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Review not found")
    review.status = ReviewStatus.APPROVED if body.approve else ReviewStatus.REJECTED
    review.rejection_reason = None if body.approve else body.reason
    review.moderated_by_id = admin.id


class BulkModerateIn(BaseModel):
    ids: list[int] = Field(min_length=1, max_length=500)
    approve: bool
    reason: str | None = Field(default=None, max_length=500)


@router.post("/reviews/moderate-bulk")
async def moderate_reviews_bulk(
    body: BulkModerateIn,
    session: SessionDep,
    admin: Annotated[User, Depends(require(Permission.REVIEWS_MODERATE))],
):
    result = await session.execute(
        update(Review)
        .where(Review.id.in_(set(body.ids)))
        .values(
            status=ReviewStatus.APPROVED if body.approve else ReviewStatus.REJECTED,
            rejection_reason=None if body.approve else body.reason,
            moderated_by_id=admin.id,
        )
    )
    return {"updated": result.rowcount}


class UploadedImageOut(BaseModel):
    url: str
    width: int
    height: int


@router.post(
    "/uploads/product-image",
    response_model=UploadedImageOut,
    status_code=201,
    dependencies=[guard(Permission.PRODUCTS_WRITE)],
)
@limiter.limit("120/hour")  # хватит на заливку каталога, но не на забивание диска
async def upload_product_image(
    request: Request,
    file: Annotated[UploadFile, File()],
    kind: Literal["products", "banners"] = "products",
) -> UploadedImageOut:
    """Фото с компьютера → /media/<kind>/<случайное>.webp. URL затем сохраняется в товаре, категории или баннере."""
    raw = await file.read(images.MAX_BYTES + 1)
    if len(raw) > images.MAX_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Файл больше 10 МБ — уменьшите фото")
    try:
        url, w, h = images.store(raw, kind)
    except images.ImageError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)) from exc
    return UploadedImageOut(url=url, width=w, height=h)


class TierIn(BaseModel):
    name: str = Field(min_length=1, max_length=50)
    min_total_spent: Decimal = Field(ge=0, le=10_000_000, max_digits=12, decimal_places=2)
    discount_type: DiscountType = DiscountType.PERCENT
    discount_value: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    color_hex: str = Field(default="#CD7F32", pattern=r"^#[0-9A-Fa-f]{6}$")
    is_active: bool = True


class TierOut(TierIn):
    id: int
    customers: int


@router.get("/loyalty-tiers", response_model=list[TierOut], dependencies=[guard(Permission.LOYALTY_MANAGE)])
async def tiers(session: SessionDep):
    counts = dict(
        (await session.execute(select(User.loyalty_tier_id, func.count()).group_by(User.loyalty_tier_id)))
        .tuples()
        .all()
    )
    rows = (await session.scalars(select(LoyaltyTier).order_by(LoyaltyTier.min_total_spent))).all()
    return [
        TierOut(
            id=t.id,
            name=t.name,
            min_total_spent=t.min_total_spent,
            discount_type=t.discount_type,
            discount_value=t.discount_value,
            color_hex=t.color_hex,
            is_active=t.is_active,
            customers=counts.get(t.id, 0),
        )
        for t in rows
    ]


async def _check_tier(session, body: TierIn, tier_id: int | None = None) -> None:
    """Понятные ошибки вместо 500 от уникальных индексов БД."""
    if body.discount_type is DiscountType.PERCENT and body.discount_value > 100:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Скидка не может быть больше 100%")
    clash = await session.scalar(
        select(LoyaltyTier).where(
            (func.lower(LoyaltyTier.name) == body.name.strip().lower())
            | (LoyaltyTier.min_total_spent == body.min_total_spent),
            LoyaltyTier.id != (tier_id or 0),
        )
    )
    if clash is not None:
        what = "названием" if clash.name.lower() == body.name.strip().lower() else "порогом"
        raise HTTPException(status.HTTP_409_CONFLICT, f"Уровень с таким {what} уже есть: {clash.name}")


@router.post("/loyalty-tiers", status_code=201, dependencies=[guard(Permission.LOYALTY_MANAGE)])
async def create_tier(body: TierIn, session: SessionDep):
    await _check_tier(session, body)
    t = LoyaltyTier(**body.model_dump())
    session.add(t)
    await session.flush()
    return {"id": t.id}


@router.put("/loyalty-tiers/{tier_id}", dependencies=[guard(Permission.LOYALTY_MANAGE)])
async def update_tier(tier_id: int, body: TierIn, session: SessionDep):
    t = await session.get(LoyaltyTier, tier_id)
    if t is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Tier not found")
    await _check_tier(session, body, tier_id)
    for k, v in body.model_dump().items():
        setattr(t, k, v)
    return {"id": t.id}


@router.delete("/loyalty-tiers/{tier_id}", status_code=204, dependencies=[guard(Permission.LOYALTY_MANAGE)])
async def delete_tier(tier_id: int, session: SessionDep):
    t = await session.get(LoyaltyTier, tier_id)
    if t is not None:
        await session.delete(t)  # у клиентов уровень станет NULL и пересчитается при следующем заказе


StaffRole = Literal["owner", "manager", "picker", "courier"]


class StaffOut(BaseModel):
    id: int
    email: str
    full_name: str
    role: str
    role_title: str
    is_active: bool


class StaffIn(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=2, max_length=200)
    role: StaffRole
    password: str = Field(min_length=10, max_length=128)


class StaffPatch(BaseModel):
    role: StaffRole | None = None
    is_active: bool | None = None


@router.get("/staff", response_model=list[StaffOut], dependencies=[guard(Permission.STAFF_MANAGE)])
async def staff(session: SessionDep):
    rows = await session.execute(select(User, Role).join(Role, Role.id == User.role_id).where(Role.is_staff))
    return [
        StaffOut(id=u.id, email=u.email, full_name=u.full_name, role=r.code, role_title=r.title, is_active=u.is_active)
        for u, r in rows.unique()
    ]


@router.post("/staff", response_model=StaffOut, status_code=201, dependencies=[guard(Permission.STAFF_MANAGE)])
async def create_staff(body: StaffIn, session: SessionDep):
    if await session.scalar(select(User.id).where(func.lower(User.email) == body.email.lower())):
        raise HTTPException(status.HTTP_409_CONFLICT, "Email is already registered")
    roles = await ensure_system_roles(session)
    role = roles[SystemRole(body.role)]
    if problem := password_problem(body.password, body.email):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, problem)
    user = User(
        email=body.email.lower(), full_name=body.full_name, password_hash=hash_password(body.password), role_id=role.id
    )
    session.add(user)
    await session.flush()
    return StaffOut(
        id=user.id, email=user.email, full_name=user.full_name, role=role.code, role_title=role.title, is_active=True
    )


@router.patch("/staff/{user_id}", response_model=StaffOut)
async def update_staff(
    user_id: int,
    body: StaffPatch,
    session: SessionDep,
    me: Annotated[User, Depends(require(Permission.STAFF_MANAGE))],
):
    user = await session.get(User, user_id)
    if user is None or not user.role.is_staff:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Staff member not found")
    if user.id == me.id and (body.is_active is False or (body.role and body.role != "owner")):
        raise HTTPException(status.HTTP_409_CONFLICT, "You cannot demote or deactivate yourself")
    if body.role:
        user.role_id = (await ensure_system_roles(session))[SystemRole(body.role)].id
    if body.is_active is not None:
        user.is_active = body.is_active
    await session.flush()
    await session.refresh(user, ["role"])
    return StaffOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        role=user.role.code,
        role_title=user.role.title,
        is_active=user.is_active,
    )


class StaffDeletedOut(BaseModel):
    deleted: bool  # false — у человека есть заказы как у покупателя: аккаунт оставлен, доступ в админку снят


@router.delete("/staff/{user_id}", response_model=StaffDeletedOut)
async def delete_staff(
    user_id: int,
    session: SessionDep,
    me: Annotated[User, Depends(require(Permission.STAFF_MANAGE))],
):
    """Удаление сотрудника. Нельзя удалить себя и последнего владельца."""
    user = await session.get(User, user_id)
    if user is None or not user.role.is_staff:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Staff member not found")
    if user.id == me.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "Нельзя удалить самого себя")
    if user.role.code == SystemRole.OWNER.value:
        owners = await session.scalar(
            select(func.count())
            .select_from(User)
            .join(Role, Role.id == User.role_id)
            .where(Role.code == SystemRole.OWNER.value, User.is_active)
        )
        if owners <= 1:
            raise HTTPException(status.HTTP_409_CONFLICT, "Нельзя удалить последнего владельца")
    # выданные токены перестают работать сразу (сотрудник мог быть в админке прямо сейчас)
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )
    if await session.scalar(select(Order.id).where(Order.user_id == user.id).limit(1)):
        user.role_id = (await ensure_system_roles(session))[SystemRole.CUSTOMER].id
        user.tokens_valid_after = datetime.now(UTC)
        return StaffDeletedOut(deleted=False)
    await session.delete(user)
    return StaffDeletedOut(deleted=True)


class PromoIn(BaseModel):
    code: str = Field(min_length=3, max_length=32, pattern=r"^[A-Za-z0-9_\-]+$")
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    min_order: Decimal = Field(default=Decimal(0), ge=0, max_digits=12, decimal_places=2)
    is_active: bool = True
    valid_until: datetime | None = None
    usage_limit: int | None = Field(default=None, gt=0)


class PromoOut(PromoIn):
    id: int
    used_count: int


@router.get("/promo-codes", response_model=list[PromoOut], dependencies=[guard(Permission.PRICING_MANAGE)])
async def promo_codes(session: SessionDep):
    rows = (await session.scalars(select(PromoCode).order_by(PromoCode.created_at.desc()))).all()
    return [
        PromoOut(
            id=p.id,
            code=p.code,
            amount=p.amount,
            min_order=p.min_order,
            is_active=p.is_active,
            valid_until=p.valid_until,
            usage_limit=p.usage_limit,
            used_count=p.used_count,
        )
        for p in rows
    ]


@router.post("/promo-codes", status_code=201, dependencies=[guard(Permission.PRICING_MANAGE)])
async def create_promo(body: PromoIn, session: SessionDep):
    code = body.code.upper()
    if await session.scalar(select(PromoCode.id).where(PromoCode.code == code)):
        raise HTTPException(status.HTTP_409_CONFLICT, "Promo code already exists")
    p = PromoCode(**body.model_dump() | {"code": code})
    session.add(p)
    await session.flush()
    return {"id": p.id}


@router.patch("/promo-codes/{promo_id}", dependencies=[guard(Permission.PRICING_MANAGE)])
async def toggle_promo(promo_id: int, session: SessionDep, is_active: bool):
    p = await session.get(PromoCode, promo_id)
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Promo code not found")
    p.is_active = is_active
    return {"id": p.id, "is_active": p.is_active}
