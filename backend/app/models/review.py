import enum

from sqlalchemy import CheckConstraint, Enum, ForeignKey, SmallInteger, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin


class ReviewStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class Review(TimestampMixin, Base):
    __tablename__ = "reviews"
    __table_args__ = (
        UniqueConstraint("user_id", "product_id"),  # один отзыв на товар от пользователя
        CheckConstraint("rating BETWEEN 1 AND 5", name="rating_range"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    rating: Mapped[int] = mapped_column(SmallInteger)
    text: Mapped[str] = mapped_column(Text, default="")
    status: Mapped[ReviewStatus] = mapped_column(
        Enum(ReviewStatus, name="review_status", values_callable=lambda e: [m.value for m in e]),
        default=ReviewStatus.PENDING,
        index=True,
    )
    moderated_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    rejection_reason: Mapped[str | None] = mapped_column(Text)
