"""
B2B-ценообразование. Приоритет правил при расчёте цены (см. services/pricing.py):

    1. PriceListItem  — явная оптовая цена товара с учётом объёма партии (tiered pricing)
    2. CategoryDiscount — % скидки на категорию в рамках прайс-листа
    3. PriceList.default_discount_percent — общая скидка прайс-листа
    4. Розничная цена

Итоговая цена никогда не превышает розничную.
"""

from datetime import date
from decimal import Decimal

from sqlalchemy import Boolean, CheckConstraint, Date, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Money, TimestampMixin

Percent = Numeric(5, 2)


class PriceList(TimestampMixin, Base):
    """Прайс-лист назначается B2B-компании (B2BAccount.price_list_id). Один прайс — много компаний."""

    __tablename__ = "price_lists"
    __table_args__ = (
        CheckConstraint("default_discount_percent >= 0 AND default_discount_percent < 100", name="default_pct_range"),
        CheckConstraint("valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from", name="validity_order"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)  # «Опт-1», «Партнёры Gold», «Сеть X»
    description: Mapped[str] = mapped_column(Text, default="")
    default_discount_percent: Mapped[Decimal] = mapped_column(Percent, default=Decimal("0"))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    valid_from: Mapped[date | None] = mapped_column(Date)
    valid_to: Mapped[date | None] = mapped_column(Date)

    items: Mapped[list["PriceListItem"]] = relationship(back_populates="price_list", cascade="all, delete-orphan")
    category_discounts: Mapped[list["CategoryDiscount"]] = relationship(
        back_populates="price_list", cascade="all, delete-orphan"
    )


class PriceListItem(Base):
    """
    Оптовая цена товара от N штук. Несколько строк на товар = лестница цен:
        min_quantity=1   → 900 ₽
        min_quantity=10  → 850 ₽
        min_quantity=100 → 790 ₽
    """

    __tablename__ = "price_list_items"
    __table_args__ = (
        UniqueConstraint("price_list_id", "product_id", "min_quantity"),
        CheckConstraint("min_quantity >= 1", name="min_qty_positive"),
        CheckConstraint("unit_price >= 0", name="price_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    price_list_id: Mapped[int] = mapped_column(ForeignKey("price_lists.id", ondelete="CASCADE"))
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    min_quantity: Mapped[int] = mapped_column(Integer, default=1)
    unit_price: Mapped[Money]

    price_list: Mapped[PriceList] = relationship(back_populates="items")


class CategoryDiscount(Base):
    """Скидка на всю категорию в рамках прайс-листа (напр. «бакалея −10% для партнёров»)."""

    __tablename__ = "category_discounts"
    __table_args__ = (
        UniqueConstraint("price_list_id", "category_id"),
        CheckConstraint("percent > 0 AND percent < 100", name="percent_range"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    price_list_id: Mapped[int] = mapped_column(ForeignKey("price_lists.id", ondelete="CASCADE"))
    category_id: Mapped[int] = mapped_column(ForeignKey("categories.id", ondelete="CASCADE"))
    percent: Mapped[Decimal] = mapped_column(Percent)

    price_list: Mapped[PriceList] = relationship(back_populates="category_discounts")
