"""
Интернет-эквайринг Альфа-Банка (REST API платёжного шлюза).

Поток:
  1. POST /me/orders/{id}/pay → register.do → получаем orderId банка и formUrl, сохраняем orderId в Order.payment_ref
  2. Покупатель платит на странице банка → банк редиректит на returnUrl
  3. Статус НИКОГДА не берём из параметров редиректа/колбэка — всегда переспрашиваем банк
     (getOrderStatusExtended.do): параметры запроса может подделать кто угодно.

Ключи: ALFA_USERNAME / ALFA_PASSWORD (логин API-пользователя магазина «...-api»).
Тестовый стенд: https://alfa.rbsuat.com/payment/rest, боевой: https://pay.alfabank.ru/payment/rest
"""

from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal

import httpx

from app.core.config import get_settings
from app.models import Order, PaymentStatus


class PaymentError(Exception):
    pass


# orderStatus из getOrderStatusExtended.do
_ALFA_STATUS = {
    0: PaymentStatus.PENDING,  # зарегистрирован, не оплачен
    1: PaymentStatus.PENDING,  # предавторизация (двухстадийная оплата)
    2: PaymentStatus.PAID,  # проведена полная авторизация
    3: PaymentStatus.FAILED,  # авторизация отменена
    4: PaymentStatus.REFUNDED,  # возврат
    5: PaymentStatus.PENDING,  # ACS-авторизация (3-D Secure)
    6: PaymentStatus.FAILED,  # отклонена
}


@dataclass(frozen=True, slots=True)
class RegisteredPayment:
    bank_order_id: str
    form_url: str


# Подмена HTTP-транспорта в тестах (httpx.MockTransport) — реальный банк в тестах не вызываем
TEST_TRANSPORT: httpx.AsyncBaseTransport | None = None


class AlfaClient:
    def __init__(self, transport: httpx.AsyncBaseTransport | None = None) -> None:
        s = get_settings()
        if not s.payments_enabled:
            raise PaymentError("Online payments are not configured")
        self._auth = {"userName": s.alfa_username, "password": s.alfa_password.get_secret_value()}
        self._base = s.alfa_api_url.rstrip("/")
        self._transport = transport or TEST_TRANSPORT
        self._shop_url = s.public_shop_url.rstrip("/")
        self._api_url = s.public_api_url.rstrip("/")

    async def _call(self, method: str, params: dict) -> dict:
        async with httpx.AsyncClient(timeout=15, transport=self._transport) as client:
            r = await client.post(f"{self._base}/{method}", data={**self._auth, **params})
        r.raise_for_status()
        data = r.json()
        if str(data.get("errorCode", "0")) not in ("0", ""):
            raise PaymentError(data.get("errorMessage") or f"Alfa error {data.get('errorCode')}")
        return data

    async def register(self, order: Order, email: str | None = None) -> RegisteredPayment:
        kopecks = int((order.total * 100).to_integral_value())
        order.payment_attempts = (order.payment_attempts or 0) + 1
        bank_number = order.number if order.payment_attempts == 1 else f"{order.number}-{order.payment_attempts}"
        params = {
            # orderNumber у банка уникален: повторная попытка оплаты получает суффикс, номер заказа не меняется
            "orderNumber": bank_number,
            "amount": kopecks,
            "currency": "643",
            "language": "ru",
            "description": f"Заказ {order.number}",
            "returnUrl": f"{self._api_url}/api/v1/payments/alfa/return?status=success",
            "failUrl": f"{self._api_url}/api/v1/payments/alfa/return?status=fail",
        }
        if email:
            params["email"] = email
        data = await self._call("register.do", params)
        return RegisteredPayment(data["orderId"], data["formUrl"])

    async def status(self, bank_order_id: str) -> tuple[PaymentStatus, Decimal]:
        data = await self._call("getOrderStatusExtended.do", {"orderId": bank_order_id})
        return _ALFA_STATUS.get(int(data.get("orderStatus", 0)), PaymentStatus.PENDING), Decimal(
            data.get("amount", 0)
        ) / 100


async def sync_payment(order: Order, client: AlfaClient) -> PaymentStatus:
    """Идемпотентно обновляет статус оплаты заказа по ответу банка. Сумма должна совпасть до копейки."""
    if not order.payment_ref:
        return order.payment_status
    status, amount = await client.status(order.payment_ref)
    if status is PaymentStatus.PAID and amount != order.total:
        raise PaymentError(f"Amount mismatch for {order.number}: bank {amount} vs order {order.total}")
    if status is PaymentStatus.PAID and order.paid_at is None:
        order.paid_at = datetime.now(UTC)
    order.payment_status = status
    return status
