from decimal import Decimal

from sqlalchemy import Boolean, CheckConstraint, Float, Numeric, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin

# Москва, Красная площадь — центр по умолчанию, пока владелец не указал адрес склада
DEFAULT_CENTER = (55.7539, 37.6208)


class ShopSettings(TimestampMixin, Base):
    """Настройки магазина — одна строка (id=1): зона доставки, часы работы, соцсети."""

    __tablename__ = "shop_settings"
    __table_args__ = (
        CheckConstraint("id = 1", name="singleton"),
        CheckConstraint("delivery_radius_km > 0 AND delivery_radius_km <= 500", name="radius_range"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, default=1)
    store_address: Mapped[str] = mapped_column(String(300), default="Москва, Красная площадь")
    store_lat: Mapped[float] = mapped_column(Float, default=DEFAULT_CENTER[0])
    store_lng: Mapped[float] = mapped_column(Float, default=DEFAULT_CENTER[1])
    delivery_radius_km: Mapped[float] = mapped_column(Float, default=20)
    delivery_zone_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    # Города, куда возим в любую точку — даже за пределами радиуса (например, вся Москва целиком)
    delivery_cities: Mapped[list[str]] = mapped_column(JSONB, default=list, server_default="[]")
    # Дни недели: 0 — понедельник … 6 — воскресенье
    work_days: Mapped[list[int]] = mapped_column(JSONB, default=lambda: [0, 1, 2, 3, 4, 5], server_default="[0,1,2,3,4,5]")
    work_from: Mapped[str] = mapped_column(String(5), default="10:00", server_default="10:00")
    work_to: Mapped[str] = mapped_column(String(5), default="22:00", server_default="22:00")
    telegram_url: Mapped[str] = mapped_column(String(200), default="", server_default="")
    instagram_url: Mapped[str] = mapped_column(String(200), default="", server_default="")
    # Оптовик не оформит заказ дешевле этой суммы (по оптовым ценам); 0 — без ограничения
    wholesale_min_order: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("5000"), server_default="5000")
