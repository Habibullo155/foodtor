import enum
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    and_,
    func,
    or_,
    select,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, Money, TimestampMixin


class Category(Base):
    __tablename__ = "categories"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    slug: Mapped[str] = mapped_column(String(140), unique=True)
    parent_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id", ondelete="SET NULL"))
    image_url: Mapped[str | None] = mapped_column(String(1024))
    position: Mapped[int] = mapped_column(Integer, default=0)  # порядок в карусели
    description: Mapped[str] = mapped_column(Text, default="", server_default="")  # текст на странице категории
    # скрытая категория не видна на сайте вместе со всеми своими товарами — ассортимент готовят заранее
    is_visible: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")


class Brand(Base):
    """Справочник фирм-производителей: у товара бренд хранится строкой, здесь — список для выбора в админке."""

    __tablename__ = "brands"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True)
    logo_url: Mapped[str | None] = mapped_column(String(1024))


class RelationKind(str, enum.Enum):
    CROSS_SELL = "cross_sell"  # «С этим товаром часто покупают»: соус к макаронам, сливки к кофе
    UPSELL = "upsell"  # «Похожие товары»: более дорогой аналог


class ProductRelation(Base):
    """
    Ассоциативная таблица self-referential many-to-many для Product.
    Направленная связь source → target: соус — cross-sell для макарон, но не наоборот.
    Объект ассоциации (а не голая Table) нужен ради kind и position — ручной порядок из админки.
    """

    __tablename__ = "product_relations"
    __table_args__ = (
        CheckConstraint("source_id <> target_id", name="no_self_relation"),
        Index("ix_product_relations_target_id", "target_id"),  # «где этот товар рекомендуется»
    )

    source_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), primary_key=True)
    target_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), primary_key=True)
    kind: Mapped[RelationKind] = mapped_column(
        Enum(RelationKind, name="relation_kind", values_callable=lambda e: [m.value for m in e]), primary_key=True
    )
    position: Mapped[int] = mapped_column(Integer, default=0)


def _related_products(kind: RelationKind):
    """
    Read-only коллекция связанных товаров одного типа, отсортированная по position.
    viewonly=True: запись идёт через ProductRelation (иначе ORM не знает, какой kind проставить).
    lazy="raise": в async-коде неявная подгрузка = скрытый N+1, поэтому только явный selectinload.
    """
    return relationship(
        "Product",
        secondary=ProductRelation.__table__,
        primaryjoin=lambda: and_(Product.id == ProductRelation.source_id, ProductRelation.kind == kind),
        secondaryjoin=lambda: Product.id == ProductRelation.target_id,
        order_by=lambda: ProductRelation.position,
        viewonly=True,
        lazy="raise",
    )


class Product(TimestampMixin, Base):
    __tablename__ = "products"
    __table_args__ = (
        CheckConstraint("cost_price >= 0", name="cost_non_negative"),
        CheckConstraint("retail_price >= 0", name="retail_non_negative"),
        CheckConstraint("compare_at_price IS NULL OR compare_at_price >= retail_price", name="compare_at_gte_retail"),
        CheckConstraint("wholesale_price IS NULL OR wholesale_price >= 0", name="wholesale_non_negative"),
        CheckConstraint("stock >= 0", name="stock_non_negative"),
        Index("ix_products_name_trgm", "name", postgresql_using="gin", postgresql_ops={"name": "gin_trgm_ops"}),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    sku: Mapped[str] = mapped_column(String(64), unique=True, index=True)  # ключ для импорта/экспорта
    name: Mapped[str] = mapped_column(String(255))
    description: Mapped[str] = mapped_column(Text, default="")

    cost_price: Mapped[Money]  # себестоимость (видна только при finance:view)
    retail_price: Mapped[Money]
    compare_at_price: Mapped[Money | None]  # «старая» цена для зачёркивания в UI
    wholesale_price: Mapped[Money | None]  # видят только подтверждённые оптовики

    stock: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    brand: Mapped[str | None] = mapped_column(String(120), index=True)  # производитель / ферма
    unit: Mapped[str | None] = mapped_column(String(32))  # фасовка: «1 кг», «500 г», «пучок»
    # Характеристики для фильтров: {"Страна": "Россия"}. JSONB + GIN — быстрые фасеты без EAV-таблиц
    attributes: Mapped[dict] = mapped_column(JSONB, default=dict, server_default="{}")
    is_hit: Mapped[bool] = mapped_column(Boolean, default=False)  # бейдж «Хит» — ставит менеджер
    category_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id", ondelete="SET NULL"), index=True)

    category: Mapped[Category | None] = relationship(lazy="joined")
    images: Mapped[list["ProductImage"]] = relationship(
        back_populates="product", cascade="all, delete-orphan", order_by="ProductImage.position", lazy="selectin"
    )

    cross_sell_products: Mapped[list["Product"]] = _related_products(RelationKind.CROSS_SELL)
    upsell_products: Mapped[list["Product"]] = _related_products(RelationKind.UPSELL)

    @hybrid_property
    def listed(self) -> bool:
        """Виден покупателям: в продаже и категория не скрыта."""
        return self.is_active and (self.category is None or self.category.is_visible)

    @listed.inplace.expression
    @classmethod
    def _listed_expr(cls):
        hidden = select(Category.id).where(Category.is_visible.is_(False))
        return and_(cls.is_active, or_(cls.category_id.is_(None), cls.category_id.not_in(hidden)))

    @hybrid_property
    def unit_margin(self) -> Decimal:
        """Маржа до скидок и расходов. Работает и в Python, и в SQL-выражениях."""
        return self.retail_price - self.cost_price

    @hybrid_property
    def margin_percent(self) -> Decimal:
        if not self.retail_price:
            return Decimal("0")
        return (self.retail_price - self.cost_price) / self.retail_price * 100

    @margin_percent.inplace.expression
    @classmethod
    def _margin_percent_expr(cls):
        return (cls.retail_price - cls.cost_price) / func.nullif(cls.retail_price, 0) * 100


class ProductImage(Base):
    __tablename__ = "product_images"

    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"), index=True)
    url: Mapped[str] = mapped_column(String(1024))
    position: Mapped[int] = mapped_column(Integer, default=0)

    product: Mapped[Product] = relationship(back_populates="images")


class Favorite(Base):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("user_id", "product_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"))


class CartItem(TimestampMixin, Base):
    """Серверная корзина — синхронизируется между устройствами пользователя."""

    __tablename__ = "cart_items"
    __table_args__ = (
        UniqueConstraint("user_id", "product_id"),
        CheckConstraint("quantity > 0", name="qty_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id", ondelete="CASCADE"))
    quantity: Mapped[int] = mapped_column(Integer)

    product: Mapped[Product] = relationship(lazy="joined")
