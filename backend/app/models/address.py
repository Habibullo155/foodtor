from sqlalchemy import Boolean, Float, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin

MAX_ADDRESSES = 10


class UserAddress(TimestampMixin, Base):
    """Адресная книга покупателя. Один адрес — «по умолчанию» (подставляется при оформлении)."""

    __tablename__ = "user_addresses"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    label: Mapped[str] = mapped_column(String(40), default="Дом")  # «Дом», «Работа», «Дача»
    address: Mapped[str] = mapped_column(String(300))  # город, улица, дом
    apartment: Mapped[str | None] = mapped_column(String(20))
    entrance: Mapped[str | None] = mapped_column(String(10))
    floor: Mapped[str | None] = mapped_column(String(10))
    intercom: Mapped[str | None] = mapped_column(String(20))
    courier_note: Mapped[str | None] = mapped_column(String(300))
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    # Координаты (геокодинг при сохранении) — для проверки зоны доставки без повторных запросов к геокодеру
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)

    def one_line(self) -> str:
        parts = [self.address]
        for title, value in (
            ("кв.", self.apartment),
            ("подъезд", self.entrance),
            ("этаж", self.floor),
            ("домофон", self.intercom),
        ):
            if value:
                parts.append(f"{title} {value}")
        return ", ".join(parts)
