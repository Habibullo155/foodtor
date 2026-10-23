from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.api.deps import (
    CurrentUser,
    PermissionsDep,
    SessionDep,
    get_cart_service,
    get_loyalty_service,
    get_order_service,
    require,
)
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.models import DeliveryMethod, Order, OrderStatus, PaymentMethod, PaymentStatus, Permission, Product, User
from app.models.order import ACTIVE_PICKING_STATUSES, PICKABLE_PAYMENT
from app.schemas.loyalty import LoyaltyProgress
from app.schemas.orders import CheckoutIn, OrderLineOut, OrderOut, PayOut, QuoteIn, QuoteLineOut, QuoteOut
from app.services import shop_info
from app.services.cart import CartService, LineRequest
from app.services.checkout import PromoError, PromoService
from app.services.geo import Point, check_delivery, get_settings_row
from app.services.loyalty import LoyaltyService
from app.services.orders import OrderError, OrderService
from app.services.payments import AlfaClient, PaymentError, sync_payment

router = APIRouter(tags=["orders"])


class StatusIn(BaseModel):
    status: OrderStatus
    comment: str | None = Field(default=None, max_length=500)


class PickItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    sku: str
    name: str
    quantity: int
    unit: str | None = None
    image_url: str | None = None


class PickOrderOut(BaseModel):
    """Сборщик видит только то, что нужно для сборки — без цен, себестоимости и прибыли."""

    id: int
    number: str
    status: OrderStatus
    payment_method: PaymentMethod  # курьеру важно: брать ли оплату при получении
    payment_status: PaymentStatus
    customer_note: str | None
    created_at: str
    items: list[PickItemOut]


async def _product_meta(session, ids) -> dict[int, tuple[str | None, str | None]]:
    """image_url и фасовка для позиций заказа (в OrderItem хранятся только снимки цены/названия)."""
    ids = [i for i in ids if i]
    if not ids:
        return {}
    products = (await session.scalars(select(Product).where(Product.id.in_(ids)))).unique()
    return {p.id: (p.images[0].url if p.images else None, p.unit) for p in products}


async def order_out(session, order: Order, cls=OrderOut, **extra):
    meta = await _product_meta(session, [i.product_id for i in order.items])
    return cls(
        id=order.id,
        number=order.number,
        status=order.status,
        payment_method=order.payment_method,
        payment_status=order.payment_status,
        delivery=order.delivery_method,
        total=order.total,
        delivery_fee=order.shipping_price,
        created_at=order.created_at,
        pay_url=order.payment_url if order.payment_status is PaymentStatus.PENDING else None,
        items=[
            OrderLineOut(
                product_id=i.product_id,
                name=i.name,
                quantity=i.quantity,
                unit_price=i.unit_price,
                line_total=i.line_total,
                image_url=meta.get(i.product_id, (None, None))[0],
                unit=meta.get(i.product_id, (None, None))[1],
            )
            for i in order.items
        ],
        **extra,
    )


@router.get("/me/loyalty", response_model=LoyaltyProgress)
async def my_loyalty(user: CurrentUser, loyalty: Annotated[LoyaltyService, Depends(get_loyalty_service)]):
    return await loyalty.progress(user)


@router.post("/me/orders/quote", response_model=QuoteOut)
@limiter.limit("60/minute")  # расчёт с промокодом — не даём перебирать промокоды
async def quote(
    request: Request,
    body: QuoteIn,
    user: CurrentUser,
    session: SessionDep,
    cart: Annotated[CartService, Depends(get_cart_service)],
) -> QuoteOut:
    """Серверный расчёт итога до оформления: клиент показывает ровно эту сумму на кнопке «Оплатить»."""
    qty: dict[int, int] = {}
    for line in body.items:
        qty[line.product_id] = qty.get(line.product_id, 0) + line.quantity
    products = (await session.scalars(select(Product).where(Product.id.in_(qty), Product.is_active))).unique().all()
    if not products:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "No available products")
    q = await cart.quote(user, [LineRequest(p, qty[p.id]) for p in products])

    promo_discount, promo_error = Decimal("0"), None
    if body.promo_code:
        try:
            promo = await PromoService(session).get_valid(body.promo_code, user)
            if q.total < promo.min_order:
                promo_error = f"Промокод действует от {promo.min_order:.0f} ₽"
            else:
                promo_discount = min(promo.amount, q.total)
        except PromoError as exc:
            promo_error = str(exc)
    settings = await get_settings_row(session)
    rules = shop_info.from_row(settings).delivery
    fee = rules.fee(body.delivery, q.total)
    return QuoteOut(
        lines=[
            QuoteLineOut(
                product_id=ln.product_id,
                name=ln.name,
                quantity=ln.quantity,
                unit_price=ln.unit_price,
                retail_unit_price=ln.retail_unit_price,
                line_total=ln.line_total,
            )
            for ln in q.lines
        ],
        subtotal=q.subtotal,
        loyalty_discount=q.loyalty_discount,
        promo_discount=promo_discount,
        promo_error=promo_error,
        delivery_fee=fee,
        total=q.total - promo_discount + fee,
        tier_name=q.tier_name,
        free_delivery_from=rules.free_from,
        delivery_min_order=rules.min_order,
        delivery_problem=rules.problem(body.delivery, q.total),
        wholesale=q.audience == "b2b",
        wholesale_min_order=settings.wholesale_min_order if q.audience == "b2b" else None,
    )


async def _start_payment(order: Order, user: User) -> None:
    payment = await AlfaClient().register(order, email=user.email)
    order.payment_ref, order.payment_url = payment.bank_order_id, payment.form_url


@router.post("/me/orders", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
async def checkout(
    body: CheckoutIn,
    user: CurrentUser,
    session: SessionDep,
    orders: Annotated[OrderService, Depends(get_order_service)],
) -> OrderOut:
    if body.payment is PaymentMethod.CARD_ONLINE and not get_settings().payments_enabled:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Invalid payment method")
    if body.delivery is not DeliveryMethod.PICKUP:
        # Жёсткая проверка зоны на сервере: подсказка в UI — лишь удобство, обойти её нельзя
        point = Point(body.lat, body.lng) if body.lat is not None and body.lng is not None else None
        zone = await check_delivery(session, body.address, point)
        if not zone.ok:
            raise HTTPException(status.HTTP_409_CONFLICT, zone.reason)
    else:
        zone = None
    try:
        order = await orders.checkout(
            user,
            [(i.product_id, i.quantity) for i in body.items],
            delivery=body.delivery,
            address=body.address,
            name=body.name,
            phone=body.phone,
            payment=body.payment,
            note=body.note,
            promo_code=body.promo_code,
        )
        if zone and zone.point:
            order.dest_lat, order.dest_lng = zone.point.lat, zone.point.lng  # для курьера: «рядом ли он»
        if body.payment is PaymentMethod.CARD_ONLINE:
            await _start_payment(order, user)
    except (OrderError, PromoError) as exc:
        raise HTTPException(status.HTTP_409_CONFLICT, str(exc)) from exc
    except PaymentError as exc:
        # Транзакция откатится целиком (UoW): остатки и промокод вернутся, заказ не создастся
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Payment gateway: {exc}") from exc
    await session.refresh(order, ["items", "created_at"])
    return await order_out(session, order)


@router.post("/me/orders/{order_id}/pay", response_model=PayOut)
async def pay_again(order_id: int, user: CurrentUser, session: SessionDep) -> PayOut:
    """Вернуться к оплате (закрыл вкладку банка и т.п.): ссылка банка живёт ~20 минут, потом выдаём новую."""
    order = await session.get(Order, order_id, with_for_update=True)
    if order is None or order.user_id != user.id or not get_settings().payments_enabled:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    if order.payment_method is not PaymentMethod.CARD_ONLINE or order.payment_status is PaymentStatus.PAID:
        raise HTTPException(status.HTTP_409_CONFLICT, "Order does not need payment")
    try:
        client = AlfaClient()
        if order.payment_ref:
            if await sync_payment(order, client) is PaymentStatus.PAID:
                raise HTTPException(status.HTTP_409_CONFLICT, "Order is already paid")
            if order.payment_url and order.payment_status is PaymentStatus.PENDING:
                return PayOut(pay_url=order.payment_url)
        await _start_payment(order, user)  # новая попытка — новый orderNumber у банка
        order.payment_status = PaymentStatus.PENDING
    except PaymentError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"Payment gateway: {exc}") from exc
    return PayOut(pay_url=order.payment_url)


@router.get("/me/orders", response_model=list[OrderOut])
async def my_orders(user: CurrentUser, session: SessionDep, limit: Annotated[int, Query(ge=1, le=100)] = 30):
    orders = (
        await session.scalars(
            select(Order).where(Order.user_id == user.id).order_by(Order.created_at.desc()).limit(limit)
        )
    ).all()
    return [await order_out(session, o) for o in orders]


@router.get("/staff/picking", response_model=list[PickOrderOut])
async def picking_queue(session: SessionDep, _: Annotated[User, Depends(require(Permission.ORDERS_PICK))]):
    stmt = (
        select(Order)
        .where(Order.status.in_(ACTIVE_PICKING_STATUSES), Order.payment_status.in_(PICKABLE_PAYMENT))
        .order_by(Order.created_at)
        .limit(100)
        .options(selectinload(Order.items))
    )
    orders = (await session.scalars(stmt)).all()
    meta = await _product_meta(session, [i.product_id for o in orders for i in o.items])
    return [
        PickOrderOut(
            id=o.id,
            number=o.number,
            status=o.status,
            payment_method=o.payment_method,
            payment_status=o.payment_status,
            customer_note=o.customer_note,
            created_at=o.created_at.isoformat(),
            items=[
                PickItemOut(
                    sku=i.sku,
                    name=i.name,
                    quantity=i.quantity,
                    image_url=meta.get(i.product_id, (None, None))[0],
                    unit=meta.get(i.product_id, (None, None))[1],
                )
                for i in o.items
            ],
        )
        for o in orders
    ]


@router.patch("/staff/orders/{order_id}/status")
async def change_status(
    order_id: int,
    body: StatusIn,
    session: SessionDep,
    actor: CurrentUser,
    perms: PermissionsDep,
    orders: Annotated[OrderService, Depends(get_order_service)],
):
    order = await session.get(Order, order_id, with_for_update=True)
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")

    # Сборщик может только взять в сборку и отметить отправку; остальные переходы — менеджер+
    picker_allowed = {OrderStatus.PICKING, OrderStatus.SHIPPED}
    if Permission.ORDERS_UPDATE_STATUS not in perms and not (
        Permission.ORDERS_PICK in perms and body.status in picker_allowed
    ):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Insufficient permissions")
    if body.status is OrderStatus.PICKING and order.payment_status not in PICKABLE_PAYMENT:
        raise HTTPException(status.HTTP_409_CONFLICT, "Order is not paid yet")

    try:
        await orders.change_status(order, body.status, actor, body.comment)
    except OrderError as exc:
        raise HTTPException(status.HTTP_409_CONFLICT, str(exc)) from exc
    return {"id": order.id, "status": order.status}
