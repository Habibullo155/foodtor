from decimal import Decimal

from sqlalchemy import Boolean, CheckConstraint, Float, Integer, Numeric, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin

# Москва, Красная площадь — центр по умолчанию, пока владелец не указал адрес склада
DEFAULT_CENTER = (55.7539, 37.6208)


class ShopSettings(TimestampMixin, Base):
    """Настройки магазина — одна строка (id=1): контакты, доставка, часы работы, соцсети, рефералы, реквизиты."""

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

    contact_phone: Mapped[str] = mapped_column(String(32), default="+7 (985) 394-72-62", server_default="+7 (985) 394-72-62")
    contact_email: Mapped[str] = mapped_column(String(120), default="", server_default="")

    # Доставка: курьер и экспресс — только от минимальной суммы, самовывоз — на любую
    delivery_min_order: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("2500"), server_default="2500")
    courier_fee: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("199"), server_default="199")
    # NULL — курьер всегда платный, 0 — всегда бесплатный
    free_delivery_from: Mapped[Decimal | None] = mapped_column(Numeric(12, 2), default=Decimal("5000"), server_default="5000")
    express_enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    express_fee: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("349"), server_default="349")
    express_hours: Mapped[int] = mapped_column(Integer, default=2, server_default="2")
    pickup_enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

    # «Приведи друга»: промокод другу при регистрации по ссылке и пригласившему — после первого заказа друга
    referral_enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    referral_friend_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("300"), server_default="300")
    referral_inviter_amount: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("300"), server_default="300")
    referral_min_order: Mapped[Decimal] = mapped_column(Numeric(12, 2), default=Decimal("2500"), server_default="2500")

    legal_name: Mapped[str] = mapped_column(String(255), default="", server_default="")
    legal_inn: Mapped[str] = mapped_column(String(12), default="", server_default="")
    legal_ogrn: Mapped[str] = mapped_column(String(15), default="", server_default="")
    legal_address: Mapped[str] = mapped_column(String(300), default="", server_default="")

