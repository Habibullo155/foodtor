import enum
from datetime import datetime
from decimal import Decimal
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, CheckConstraint, DateTime, Enum, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Money, MoneyDefault0, TimestampMixin

if TYPE_CHECKING:
    from app.models.user import User


class PaymentMethod(str, enum.Enum):
    CASH = "cash"  # при получении
    CARD_ONLINE = "card_online"  # эквайринг (Альфа-Банк)


class PaymentStatus(str, enum.Enum):
    NOT_REQUIRED = "not_required"  # оплата при получении
    PENDING = "pending"  # ждём оплату на странице банка
    PAID = "paid"
    FAILED = "failed"
    REFUNDED = "refunded"


class DeliveryMethod(str, enum.Enum):
    EXPRESS = "express"
    COURIER = "courier"
    PICKUP = "pickup"


def _values(e):
    return [m.value for m in e]


class OrderStatus(str, enum.Enum):
    NEW = "new"
    PICKING = "picking"
    SHIPPED = "shipped"
    DELIVERED = "delivered"  # доставлен → засчитывается в лояльность
    CANCELLED = "cancelled"


# Конечный автомат статусов: защищает от «прыжков» (delivered → new и т.п.)
ORDER_TRANSITIONS: dict[OrderStatus, set[OrderStatus]] = {
    OrderStatus.NEW: {OrderStatus.PICKING, OrderStatus.CANCELLED},
    OrderStatus.PICKING: {OrderStatus.SHIPPED, OrderStatus.CANCELLED},
    OrderStatus.SHIPPED: {OrderStatus.DELIVERED},
    OrderStatus.DELIVERED: set(),
    OrderStatus.CANCELLED: set(),
}
ACTIVE_PICKING_STATUSES = (OrderStatus.NEW, OrderStatus.PICKING)
# В сборку идут только оплаченные онлайн или с оплатой при получении
PICKABLE_PAYMENT = (PaymentStatus.PAID, PaymentStatus.NOT_REQUIRED)

_status_enum = Enum(OrderStatus, name="order_status", values_callable=lambda e: [m.value for m in e])


class Order(TimestampMixin, Base):
    """
    Финансовая модель заказа (все суммы — снимок на момент покупки):

        subtotal          = Σ retail_price × qty
        loyalty_discount  = скидка уровня лояльности
        total             = subtotal − loyalty_discount + shipping_price   (платит клиент)
        cost_total        = Σ cost_price × qty                              (себестоимость)
        order_expenses    = доставка за наш счёт + эквайринг + упаковка ...  (Expense с order_id)
        net_profit        = total − cost_total − order_expenses
    """

    __tablename__ = "orders"
    __table_args__ = (CheckConstraint("total >= 0", name="total_non_negative"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    number: Mapped[str] = mapped_column(String(32), unique=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    status: Mapped[OrderStatus] = mapped_column(_status_enum, default=OrderStatus.NEW, index=True)

    subtotal: Mapped[Money]
    loyalty_discount: Mapped[MoneyDefault0]
    shipping_price: Mapped[MoneyDefault0]
    total: Mapped[Money]
    cost_total: Mapped[Money]
    expenses_total: Mapped[MoneyDefault0]  # денормализация Σ Expense.amount по заказу

    # Сегмент на момент покупки — для разреза B2C/B2B на дашборде
    customer_segment: Mapped[str] = mapped_column(String(8), default="b2c", index=True)
    price_list_name: Mapped[str | None] = mapped_column(String(120))

    # Снимок лояльности: если админ поменяет пороги, история заказов не «поплывёт»
    loyalty_tier_name: Mapped[str | None] = mapped_column(String(50))

    shipping_address: Mapped[str] = mapped_column(Text)
    customer_name: Mapped[str] = mapped_column(String(200), default="")
    customer_phone: Mapped[str] = mapped_column(String(32), default="")
    delivery_method: Mapped[DeliveryMethod] = mapped_column(
        Enum(DeliveryMethod, name="delivery_method", values_callable=_values), default=DeliveryMethod.COURIER
    )
    promo_code: Mapped[str | None] = mapped_column(String(32))
    promo_discount: Mapped[MoneyDefault0]

    payment_method: Mapped[PaymentMethod] = mapped_column(
        Enum(PaymentMethod, name="payment_method", values_callable=_values), default=PaymentMethod.CASH
    )
    payment_status: Mapped[PaymentStatus] = mapped_column(
        Enum(PaymentStatus, name="payment_status", values_callable=_values),
        default=PaymentStatus.NOT_REQUIRED,
        index=True,
    )
    payment_ref: Mapped[str | None] = mapped_column(String(64), unique=True)  # orderId (mdOrder) в банке
    payment_url: Mapped[str | None] = mapped_column(String(1024))  # formUrl — для повторного перехода к оплате
    payment_attempts: Mapped[int] = mapped_column(Integer, default=0)  # номер у банка: «260101-ABC123-2»
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    customer_note: Mapped[str | None] = mapped_column(Text)
    picker_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # Доставка курьером. Телефон покупателя курьеру не показываем, пока он не рядом (или не ЧП)
    courier_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    dest_lat: Mapped[float | None] = mapped_column(Float)  # координаты адреса (геокодер при оформлении)
    dest_lng: Mapped[float | None] = mapped_column(Float)
    courier_lat: Mapped[float | None] = mapped_column(Float)
    courier_lng: Mapped[float | None] = mapped_column(Float)
    courier_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    phone_revealed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    phone_reveal_reason: Mapped[str | None] = mapped_column(String(300))  # «рядом» или причина ЧП — для разбора

    user: Mapped["User"] = relationship(back_populates="orders", foreign_keys=[user_id])
    items: Mapped[list["OrderItem"]] = relationship(
        back_populates="order", cascade="all, delete-orphan", lazy="selectin"
    )
    history: Mapped[list["OrderStatusHistory"]] = relationship(
        cascade="all, delete-orphan", order_by="OrderStatusHistory.created_at"
    )

    @hybrid_property
    def gross_profit(self) -> Decimal:
        return self.total - self.cost_total

    @hybrid_property
    def net_profit(self) -> Decimal:
        return self.total - self.cost_total - self.expenses_total

    def can_transition_to(self, new_status: OrderStatus) -> bool:
        return new_status in ORDER_TRANSITIONS[self.status]


class OrderItem(Base):
    __tablename__ = "order_items"
    __table_args__ = (CheckConstraint("quantity > 0", name="qty_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int | None] = mapped_column(ForeignKey("products.id", ondelete="SET NULL"))

    # Снимки товара — цена/себестоимость могут измениться после покупки
    sku: Mapped[str] = mapped_column(String(64))
    name: Mapped[str] = mapped_column(String(255))
    quantity: Mapped[int] = mapped_column(Integer)
    unit_price: Mapped[Money]  # фактическая цена за единицу (розничная или оптовая)
    retail_unit_price: Mapped[Money]  # розничная на момент покупки — видно, сколько «стоил» опт
    price_source: Mapped[str] = mapped_column(String(24), default="retail")
    unit_cost: Mapped[Money]
    discount_amount: Mapped[MoneyDefault0]  # доля скидки заказа, распределённая на строку
    line_total: Mapped[Money]  # unit_price × qty − discount_amount

    order: Mapped[Order] = relationship(back_populates="items")

    @hybrid_property
    def line_profit(self) -> Decimal:
        return self.line_total - self.unit_cost * self.quantity


class OrderStatusHistory(Base):

    __tablename__ = "order_status_history"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), index=True)
    from_status: Mapped[OrderStatus | None] = mapped_column(_status_enum)
    to_status: Mapped[OrderStatus] = mapped_column(_status_enum)
    changed_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    comment: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class OrderComment(Base):
    """Переписка по заказу: покупатель пишет после оформления, магазин отвечает из админки."""

    __tablename__ = "order_comments"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), index=True)
    author_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    from_staff: Mapped[bool] = mapped_column(Boolean, default=False)
    # shop — переписка с магазином; courier — чат покупателя с курьером (без обмена телефонами)
    channel: Mapped[str] = mapped_column(String(16), default="shop", server_default="shop", index=True)
    text: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
