import enum
from decimal import Decimal

from sqlalchemy import Boolean, CheckConstraint, Enum, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Money, TimestampMixin


class DiscountType(str, enum.Enum):
    PERCENT = "percent"
    FIXED = "fixed"


class LoyaltyTier(TimestampMixin, Base):
    """Уровень лояльности (Bronze/Silver/Gold/...). Пороги и скидки настраиваются в админке."""

    __tablename__ = "loyalty_tiers"
    __table_args__ = (
        CheckConstraint("min_total_spent >= 0", name="min_spent_non_negative"),
        CheckConstraint("discount_value >= 0", name="discount_non_negative"),
        CheckConstraint("discount_type <> 'percent' OR discount_value <= 100", name="percent_max_100"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(50), unique=True)
    min_total_spent: Mapped[Money] = mapped_column(unique=True)  # порог достижения
    discount_type: Mapped[DiscountType] = mapped_column(
        Enum(DiscountType, name="discount_type", values_callable=lambda e: [m.value for m in e])
    )
    discount_value: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    # Минимальная сумма корзины, с которой применяется фиксированная скидка (защита от минуса)
    min_order_for_fixed: Mapped[Money] = mapped_column(default=Decimal("0"))
    color_hex: Mapped[str] = mapped_column(String(7), default="#CD7F32")  # для UI-бейджа
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
