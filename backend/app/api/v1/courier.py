"""Курьер: свои доставки, геопозиция, чат с покупателем.

Приватность: телефон покупателя курьеру не показываем. Он открывается автоматически, когда курьер
ближе REVEAL_KM к адресу, или вручную по кнопке «ЧП» с обязательной причиной (причина сохраняется
и видна магазину). До этого связь — только через чат внутри приложения. Телефон курьера покупатель
не видит вовсе.
"""

import re
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import or_, select
from sqlalchemy.orm import selectinload

from app.api.deps import CurrentUser, SessionDep, get_order_service, require
from app.api.v1.account import my_order
from app.models import Order, OrderComment, OrderStatus, PaymentMethod, PaymentStatus, Permission, User
from app.schemas.catalog import MoneyOut
from app.services.geo import Point, haversine_km
from app.services.orders import OrderError, OrderService

router = APIRouter(tags=["courier"])

REVEAL_KM = 1.0  # ближе этого к адресу — телефон покупателя открывается курьеру


def mask_phone(phone: str) -> str:
    digits = re.sub(r"\D", "", phone)
    return f"+7 ••• •••-••-{digits[-2:]}" if len(digits) >= 4 else "скрыт"


def first_name(full: str) -> str:
    return (full or "Покупатель").split()[0]


class CourierOrderOut(BaseModel):
    id: int
    number: str
    status: OrderStatus
    customer_name: str  # только имя — фамилия курьеру не нужна
    address: str
    note: str | None
    items_count: int
    total: MoneyOut
    cash_to_collect: MoneyOut | None  # оплата при получении — сколько взять
    phone: str | None  # None, пока номер скрыт
    phone_masked: str
    phone_reveal_reason: str | None
    distance_km: float | None
    dest_lat: float | None
    dest_lng: float | None
    mine: bool


def _distance(o: Order) -> float | None:
    if None in (o.dest_lat, o.dest_lng, o.courier_lat, o.courier_lng):
        return None
    return round(haversine_km(Point(o.courier_lat, o.courier_lng), Point(o.dest_lat, o.dest_lng)), 2)


def _out(o: Order, me: User) -> CourierOrderOut:
    revealed = o.phone_revealed_at is not None and o.courier_id == me.id
    cash = o.payment_method is not PaymentMethod.CARD_ONLINE and o.payment_status is not PaymentStatus.PAID
    return CourierOrderOut(
        id=o.id,
        number=o.number,
        status=o.status,
        customer_name=first_name(o.customer_name),
        address=o.shipping_address,
        note=o.customer_note,
        items_count=sum(i.quantity for i in o.items),
        total=o.total,
        cash_to_collect=o.total if cash else None,
        phone=o.customer_phone if revealed else None,
        phone_masked=mask_phone(o.customer_phone),
        phone_reveal_reason=o.phone_reveal_reason if revealed else None,
        distance_km=_distance(o),
        dest_lat=o.dest_lat,
        dest_lng=o.dest_lng,
        mine=o.courier_id == me.id,
    )


CourierDep = Annotated[User, Depends(require(Permission.ORDERS_DELIVER))]


async def _load(session, order_id: int) -> Order:
    order = await session.scalar(
        select(Order).where(Order.id == order_id).options(selectinload(Order.items)).with_for_update(of=Order)
    )
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    return order


async def _mine(session, order_id: int, me: User) -> Order:
    order = await _load(session, order_id)
    if order.courier_id != me.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Это заказ другого курьера")
    return order


@router.get("/courier/orders", response_model=list[CourierOrderOut])
async def courier_orders(session: SessionDep, me: CourierDep):
    """Отправленные заказы: свободные (можно взять) и мои."""
    rows = await session.scalars(
        select(Order)
        .where(Order.status == OrderStatus.SHIPPED, or_(Order.courier_id.is_(None), Order.courier_id == me.id))
        .order_by(Order.created_at)
        .limit(100)
        .options(selectinload(Order.items))
    )
    return [_out(o, me) for o in rows]


@router.post("/courier/orders/{order_id}/take", response_model=CourierOrderOut)
async def take_order(order_id: int, session: SessionDep, me: CourierDep):
    order = await _load(session, order_id)
    if order.status is not OrderStatus.SHIPPED:
        raise HTTPException(status.HTTP_409_CONFLICT, "Заказ ещё не передан в доставку")
    if order.courier_id not in (None, me.id):
        raise HTTPException(status.HTTP_409_CONFLICT, "Заказ уже везёт другой курьер")
    order.courier_id = me.id
    return _out(order, me)


class LocationIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


@router.post("/courier/orders/{order_id}/location", response_model=CourierOrderOut)
async def courier_location(order_id: int, body: LocationIn, session: SessionDep, me: CourierDep):
    order = await _mine(session, order_id, me)
    order.courier_lat, order.courier_lng, order.courier_seen_at = body.lat, body.lng, datetime.now(UTC)
    d = _distance(order)
    if d is not None and d <= REVEAL_KM and order.phone_revealed_at is None:
        order.phone_revealed_at = datetime.now(UTC)
        order.phone_reveal_reason = f"Курьер рядом с адресом ({d:.1f} км)"
    return _out(order, me)


class EmergencyIn(BaseModel):
    reason: str = Field(min_length=5, max_length=280)


@router.post("/courier/orders/{order_id}/emergency", response_model=CourierOrderOut)
async def emergency(order_id: int, body: EmergencyIn, session: SessionDep, me: CourierDep):
    """ЧП: курьер открывает номер раньше времени. Причина видна покупателю и магазину."""
    order = await _mine(session, order_id, me)
    if order.phone_revealed_at is None:
        order.phone_revealed_at = datetime.now(UTC)
    order.phone_reveal_reason = f"ЧП: {body.reason.strip()}"
    note = f"Курьер открыл ваш номер телефона. Причина: {body.reason.strip()}"
    session.add(OrderComment(order_id=order.id, author_id=me.id, from_staff=True, channel="courier", text=note))
    session.add(
        OrderComment(
            order_id=order.id,
            author_id=me.id,
            from_staff=True,
            channel="shop",
            text=f"[ЧП курьера] {body.reason.strip()}",
        )
    )
    return _out(order, me)


@router.post("/courier/orders/{order_id}/delivered", response_model=CourierOrderOut)
async def delivered(
    order_id: int,
    session: SessionDep,
    me: CourierDep,
    orders: Annotated[OrderService, Depends(get_order_service)],
):
    order = await _mine(session, order_id, me)
    try:
        await orders.change_status(order, OrderStatus.DELIVERED, me, "Вручен курьером")
    except OrderError as exc:
        raise HTTPException(status.HTTP_409_CONFLICT, str(exc)) from exc
    return _out(order, me)


class ChatIn(BaseModel):
    text: str = Field(min_length=1, max_length=1000)


class ChatOut(BaseModel):
    id: int
    text: str
    from_staff: bool  # true — курьер
    author: str
    created_at: datetime


async def _chat(session, order_id: int) -> list[ChatOut]:
    rows = await session.execute(
        select(OrderComment, User.full_name)
        .outerjoin(User, User.id == OrderComment.author_id)
        .where(OrderComment.order_id == order_id, OrderComment.channel == "courier")
        .order_by(OrderComment.created_at, OrderComment.id)
    )
    return [
        ChatOut(
            id=c.id,
            text=c.text,
            from_staff=c.from_staff,
            created_at=c.created_at,
            author=f"Курьер {first_name(name or '')}" if c.from_staff else first_name(name or ""),
        )
        for c, name in rows
    ]


@router.get("/courier/orders/{order_id}/chat", response_model=list[ChatOut])
async def courier_chat(order_id: int, session: SessionDep, me: CourierDep):
    await _mine(session, order_id, me)
    return await _chat(session, order_id)


@router.post("/courier/orders/{order_id}/chat", response_model=list[ChatOut], status_code=201)
async def courier_say(order_id: int, body: ChatIn, session: SessionDep, me: CourierDep):
    order = await _mine(session, order_id, me)
    if order.status is not OrderStatus.SHIPPED:
        raise HTTPException(status.HTTP_409_CONFLICT, "Order is closed")
    session.add(
        OrderComment(order_id=order.id, author_id=me.id, from_staff=True, channel="courier", text=body.text.strip())
    )
    await session.flush()
    return await _chat(session, order_id)


class CourierInfoOut(BaseModel):
    assigned: bool
    courier_name: str | None
    distance_km: float | None
    seen_at: datetime | None
    phone_opened: bool  # покупатель видит, что курьер получил его номер (и почему)
    phone_reveal_reason: str | None


@router.get("/me/orders/{order_id}/courier", response_model=CourierInfoOut)
async def my_courier(order_id: int, user: CurrentUser, session: SessionDep):
    order = await my_order(session, user, order_id)
    courier = await session.get(User, order.courier_id) if order.courier_id else None
    return CourierInfoOut(
        assigned=courier is not None,
        courier_name=first_name(courier.full_name) if courier else None,
        distance_km=_distance(order),
        seen_at=order.courier_seen_at,
        phone_opened=order.phone_revealed_at is not None,
        phone_reveal_reason=order.phone_reveal_reason,
    )


@router.get("/me/orders/{order_id}/courier-chat", response_model=list[ChatOut])
async def my_courier_chat(order_id: int, user: CurrentUser, session: SessionDep):
    await my_order(session, user, order_id)
    return await _chat(session, order_id)


@router.post("/me/orders/{order_id}/courier-chat", response_model=list[ChatOut], status_code=201)
async def my_courier_say(order_id: int, body: ChatIn, user: CurrentUser, session: SessionDep):
    order = await my_order(session, user, order_id)
    if order.status is not OrderStatus.SHIPPED or order.courier_id is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Курьер ещё не назначен")
    session.add(
        OrderComment(order_id=order.id, author_id=user.id, from_staff=False, channel="courier", text=body.text.strip())
    )
    await session.flush()
    return await _chat(session, order_id)
