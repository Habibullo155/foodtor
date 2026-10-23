from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Money, MoneyDefault0, TimestampMixin


class PromoCode(TimestampMixin, Base):
    """Фиксированная скидка на заказ от минимальной суммы. Код хранится в верхнем регистре."""

    __tablename__ = "promo_codes"
    __table_args__ = (
        CheckConstraint("amount > 0", name="amount_positive"),
        CheckConstraint("usage_limit IS NULL OR usage_limit > 0", name="usage_limit_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(32), unique=True)
    amount: Mapped[Money]
    min_order: Mapped[MoneyDefault0]
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    valid_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    usage_limit: Mapped[int | None] = mapped_column(Integer)
    used_count: Mapped[int] = mapped_column(Integer, default=0)
    # Личный промокод (реферальный): применить может только владелец
    owner_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    source: Mapped[str] = mapped_column(String(20), default="manual", server_default="manual")  # manual | referral_friend | referral_inviter
    first_order_only: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")

