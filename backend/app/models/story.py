from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin


class Story(TimestampMixin, Base):
    """«Кружок» историй на главной: обложка + несколько слайдов. Заводит менеджер в админке."""

    __tablename__ = "stories"
    __table_args__ = (CheckConstraint("color_hex ~ '^#[0-9A-Fa-f]{6}$'", name="color_hex"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(40))  # подпись под кружком
    cover_url: Mapped[str] = mapped_column(String(1024))
    color_hex: Mapped[str] = mapped_column(String(7), default="#0B5D3B")  # фон кружка и слайдов
    position: Mapped[int] = mapped_column(Integer, default=0, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    starts_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))  # показывать с…
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))  # …и до (акция закончилась — скрыть)

    slides: Mapped[list["StorySlide"]] = relationship(
        back_populates="story", cascade="all, delete-orphan", order_by="StorySlide.position", lazy="selectin"
    )


class StorySlide(Base):
    __tablename__ = "story_slides"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id", ondelete="CASCADE"), index=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    image_url: Mapped[str] = mapped_column(String(1024))
    headline: Mapped[str] = mapped_column(String(120))
    caption: Mapped[str | None] = mapped_column(Text)
    cta_label: Mapped[str | None] = mapped_column(String(40))  # «Смотреть ягоды»
    cta_url: Mapped[str | None] = mapped_column(String(300))  # /catalog/yagody, /product/29-…

    story: Mapped[Story] = relationship(back_populates="slides")
