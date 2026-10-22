"""Возврат покупателя со страницы банка и серверные уведомления (callback) Альфа-Банка."""

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status
from fastapi.responses import PlainTextResponse, RedirectResponse
from sqlalchemy import select

from app.api.deps import SessionDep
from app.core.config import get_settings
from app.models import Order, PaymentStatus
from app.services.payments import AlfaClient, PaymentError, sync_payment

router = APIRouter(prefix="/payments/alfa", tags=["payments"])


async def _sync(session, bank_order_id: str) -> Order:
    order = await session.scalar(select(Order).where(Order.payment_ref == bank_order_id).with_for_update())
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown payment")
    await sync_payment(order, AlfaClient())  # статус берём только из API банка, не из параметров запроса
    return order


@router.get("/return", include_in_schema=False)
async def payment_return(session: SessionDep, order_id: Annotated[str, Query(alias="orderId", max_length=64)]):
    shop = get_settings().public_shop_url.rstrip("/")
    try:
        order = await _sync(session, order_id)
    except (HTTPException, PaymentError):
        return RedirectResponse(f"{shop}/payment/return?result=error", status.HTTP_303_SEE_OTHER)
    result = "success" if order.payment_status is PaymentStatus.PAID else "fail"
    await session.commit()
    return RedirectResponse(f"{shop}/payment/return?result={result}&order={order.id}", status.HTTP_303_SEE_OTHER)


@router.get("/callback", response_class=PlainTextResponse, include_in_schema=False)
async def payment_callback(session: SessionDep, md_order: Annotated[str, Query(alias="mdOrder", max_length=64)]):
    """Банк дёргает этот URL при смене статуса (настраивается в ЛК мерчанта). Идемпотентно."""
    try:
        await _sync(session, md_order)
    except PaymentError as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(exc)) from exc
    return "OK"
