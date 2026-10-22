from datetime import datetime
from decimal import Decimal

from pydantic import BaseModel, Field, field_validator

from app.models import DeliveryMethod, OrderStatus, PaymentMethod, PaymentStatus
from app.schemas.catalog import MoneyOut


class LineIn(BaseModel):
    product_id: int = Field(gt=0)
    quantity: int = Field(gt=0, le=999)


class QuoteIn(BaseModel):
    items: list[LineIn] = Field(min_length=1, max_length=100)
    delivery: DeliveryMethod = DeliveryMethod.COURIER
    promo_code: str | None = Field(default=None, max_length=32)


class CheckoutIn(QuoteIn):
    address: str = Field(min_length=5, max_length=500)
    # Точка, выбранная на карте: проверка зоны по ней (точнее геокодинга строки), курьеру — точный адрес
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    name: str = Field(min_length=2, max_length=200)
    phone: str = Field(pattern=r"^\+?[0-9 ()\-]{7,20}$")
    payment: PaymentMethod = PaymentMethod.CASH
    note: str | None = Field(default=None, max_length=1000)

    @field_validator("address", "name")
    @classmethod
    def _strip(cls, v: str) -> str:
        return v.strip()


class QuoteLineOut(BaseModel):
    product_id: int
    name: str
    quantity: int
    unit_price: MoneyOut
    retail_unit_price: MoneyOut
    line_total: MoneyOut


class QuoteOut(BaseModel):
    lines: list[QuoteLineOut]
    subtotal: MoneyOut
    loyalty_discount: MoneyOut
    promo_discount: MoneyOut
    promo_error: str | None
    delivery_fee: MoneyOut
    total: MoneyOut
    tier_name: str | None
    free_delivery_from: MoneyOut
    wholesale: bool = False
    wholesale_min_order: MoneyOut | None = None  # только для оптовика: меньше — заказ не оформить


class OrderLineOut(BaseModel):
    product_id: int | None
    name: str
    quantity: int
    unit_price: MoneyOut
    line_total: MoneyOut
    image_url: str | None = None
    unit: str | None = None


class OrderOut(BaseModel):
    id: int
    number: str
    status: OrderStatus
    payment_method: PaymentMethod
    payment_status: PaymentStatus
    delivery: DeliveryMethod
    total: MoneyOut
    delivery_fee: MoneyOut
    created_at: datetime
    items: list[OrderLineOut]
    pay_url: str | None = None  # есть, пока заказ ждёт онлайн-оплату


class AdminOrderOut(OrderOut):
    customer_name: str
    customer_phone: str
    customer_email: str
    address: str
    note: str | None
    segment: str
    subtotal: MoneyOut
    discounts: MoneyOut
    cost_total: MoneyOut
    expenses_total: MoneyOut
    profit: MoneyOut


class PayOut(BaseModel):
    pay_url: str


class Totals(BaseModel):
    revenue: MoneyOut
    profit: MoneyOut | None  # None — у роли нет права finance:view
    orders: int
    avg_check: MoneyOut


class DayOut(BaseModel):
    day: str
    revenue: MoneyOut
    expenses: MoneyOut
    orders: int


class FinanceOut(BaseModel):
    days: int
    current: Totals
    previous: Totals
    series: list[DayOut]


def zero() -> Decimal:
    return Decimal("0")
