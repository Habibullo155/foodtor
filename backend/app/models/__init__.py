"""Импорт всех моделей — нужен Alembic autogenerate и для разрешения строковых relationship."""

from app.models.address import UserAddress
from app.models.finance import Expense, ExpenseCategory
from app.models.loyalty import DiscountType, LoyaltyTier
from app.models.marketing import Banner, SupportMessage
from app.models.order import (
    DeliveryMethod,
    Order,
    OrderComment,
    OrderItem,
    OrderStatus,
    OrderStatusHistory,
    PaymentMethod,
    PaymentStatus,
)
from app.models.pricing import CategoryDiscount, PriceList, PriceListItem
from app.models.product import CartItem, Category, Favorite, Product, ProductImage, ProductRelation, RelationKind
from app.models.promo import PromoCode
from app.models.review import Review, ReviewStatus
from app.models.settings import ShopSettings
from app.models.story import Story, StorySlide
from app.models.user import (
    AccountType,
    B2BAccount,
    B2BStatus,
    LoginCode,
    Permission,
    RefreshToken,
    Role,
    RolePermission,
    SystemRole,
    User,
)

__all__ = [
    "Banner",
    "SupportMessage",
    "ShopSettings",
    "LoginCode",
    "Story",
    "StorySlide",
    "OrderComment",
    "UserAddress",
    "DeliveryMethod",
    "PaymentMethod",
    "PaymentStatus",
    "PromoCode",
    "AccountType",
    "B2BAccount",
    "B2BStatus",
    "CategoryDiscount",
    "PriceList",
    "PriceListItem",
    "ProductRelation",
    "RelationKind",
    "CartItem",
    "Category",
    "DiscountType",
    "Expense",
    "ExpenseCategory",
    "Favorite",
    "LoyaltyTier",
    "Order",
    "OrderItem",
    "OrderStatus",
    "OrderStatusHistory",
    "Permission",
    "Product",
    "ProductImage",
    "RefreshToken",
    "Review",
    "ReviewStatus",
    "Role",
    "RolePermission",
    "SystemRole",
    "User",
]
