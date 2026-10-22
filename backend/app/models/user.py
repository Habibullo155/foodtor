import enum
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    String,
    Table,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, MoneyDefault0, TimestampMixin

if TYPE_CHECKING:
    from app.models.loyalty import LoyaltyTier
    from app.models.order import Order
    from app.models.pricing import PriceList


class Permission(str, enum.Enum):
    """Гранулярные права. Роль = набор прав, поэтому новые роли создаются без деплоя."""

    DASHBOARD_VIEW = "dashboard:view"
    FINANCE_VIEW = "finance:view"
    EXPENSES_MANAGE = "expenses:manage"
    PRODUCTS_READ = "products:read"
    PRODUCTS_WRITE = "products:write"
    PRODUCTS_IMPORT = "products:import"
    ORDERS_READ_ALL = "orders:read_all"
    ORDERS_PICK = "orders:pick"  # сборщик: только активные заказы
    ORDERS_UPDATE_STATUS = "orders:update_status"
    REVIEWS_MODERATE = "reviews:moderate"
    LOYALTY_MANAGE = "loyalty:manage"
    STAFF_MANAGE = "staff:manage"
    B2B_MANAGE = "b2b:manage"  # верификация оптовиков
    PRICING_MANAGE = "pricing:manage"  # прайс-листы и оптовые цены
    ORDERS_DELIVER = "orders:deliver"  # курьер: свои доставки, чат с покупателем


class SystemRole(str, enum.Enum):
    OWNER = "owner"
    MANAGER = "manager"
    PICKER = "picker"
    COURIER = "courier"
    CUSTOMER = "customer"


DEFAULT_ROLE_PERMISSIONS: dict[SystemRole, set[Permission]] = {
    SystemRole.OWNER: set(Permission),
    SystemRole.MANAGER: {
        Permission.DASHBOARD_VIEW,
        Permission.PRODUCTS_READ,
        Permission.PRODUCTS_WRITE,
        Permission.PRODUCTS_IMPORT,
        Permission.ORDERS_READ_ALL,
        Permission.ORDERS_UPDATE_STATUS,
        Permission.REVIEWS_MODERATE,
        Permission.B2B_MANAGE,
    },
    SystemRole.PICKER: {Permission.ORDERS_PICK},
    SystemRole.COURIER: {Permission.ORDERS_DELIVER},
    SystemRole.CUSTOMER: set(),
}


role_permissions = Table(
    "role_permissions",
    Base.metadata,
    Column("role_id", ForeignKey("roles.id", ondelete="CASCADE"), primary_key=True),
    Column(
        "permission",
        Enum(Permission, name="permission", values_callable=lambda e: [m.value for m in e]),
        primary_key=True,
    ),
)


class AccountType(str, enum.Enum):
    B2C = "b2c"  # розничный покупатель
    B2B = "b2b"  # оптовик / магазин-партнёр


class B2BStatus(str, enum.Enum):
    PENDING = "pending"  # заявка подана — видит розничные цены
    APPROVED = "approved"  # подтверждён — видит цены своего прайс-листа
    REJECTED = "rejected"
    SUSPENDED = "suspended"  # например, просрочка оплаты


def _values(e: type[enum.Enum]) -> list[str]:
    return [m.value for m in e]


class B2BAccount(TimestampMixin, Base):
    """
    Компания-оптовик. Отдельная сущность, а не поля в User: у одного магазина-партнёра
    может быть несколько сотрудников-закупщиков с общим прайс-листом.
    """

    __tablename__ = "b2b_accounts"

    id: Mapped[int] = mapped_column(primary_key=True)
    legal_name: Mapped[str] = mapped_column(String(255))
    tax_id: Mapped[str] = mapped_column(String(32), unique=True)  # ИНН
    status: Mapped[B2BStatus] = mapped_column(
        Enum(B2BStatus, name="b2b_status", values_callable=_values), default=B2BStatus.PENDING, index=True
    )
    price_list_id: Mapped[int | None] = mapped_column(ForeignKey("price_lists.id", ondelete="SET NULL"))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # use_alter: users ↔ b2b_accounts ссылаются друг на друга — FK добавляется отдельным ALTER
    verified_by_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL", use_alter=True, name="fk_b2b_accounts_verified_by_id_users")
    )
    manager_note: Mapped[str | None] = mapped_column(Text)

    price_list: Mapped["PriceList | None"] = relationship(lazy="joined")
    members: Mapped[list["User"]] = relationship(back_populates="b2b_account", foreign_keys="User.b2b_account_id")


class Role(Base):
    __tablename__ = "roles"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(50), unique=True)  # 'owner', 'manager', 'picker', кастомные
    title: Mapped[str] = mapped_column(String(100))
    is_staff: Mapped[bool] = mapped_column(Boolean, default=True)
    is_system: Mapped[bool] = mapped_column(Boolean, default=False)  # системные роли нельзя удалить

    users: Mapped[list["User"]] = relationship(back_populates="role")


class RolePermission(Base):

    __table__ = role_permissions


class User(TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        # B2B-пользователь обязан принадлежать компании, B2C — не может
        CheckConstraint("(account_type = 'b2b') = (b2b_account_id IS NOT NULL)", name="b2b_account_consistency"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)  # у входящих по SMS может не быть
    phone_e164: Mapped[str | None] = mapped_column(String(16), unique=True)  # подтверждённый по SMS номер, +7XXXXXXXXXX
    phone_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))  # подтверждён кодом из письма
    password_hash: Mapped[str] = mapped_column(String(255))
    full_name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str | None] = mapped_column(String(32))
    avatar_url: Mapped[str | None] = mapped_column(String(512))  # /media/avatars/… — файл пережат сервером
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    # Токены, выпущенные раньше этого момента, недействительны (смена пароля, «выйти везде»)
    tokens_valid_after: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    role_id: Mapped[int] = mapped_column(ForeignKey("roles.id", ondelete="RESTRICT"))
    role: Mapped[Role] = relationship(back_populates="users", lazy="joined")

    # Лояльность: денормализованная сумма покупок (пересчитывается сервисом) + текущий уровень
    total_spent: Mapped[MoneyDefault0]
    loyalty_tier_id: Mapped[int | None] = mapped_column(ForeignKey("loyalty_tiers.id", ondelete="SET NULL"))
    loyalty_tier: Mapped["LoyaltyTier | None"] = relationship(lazy="joined")

    orders: Mapped[list["Order"]] = relationship(back_populates="user", foreign_keys="Order.user_id")

    account_type: Mapped[AccountType] = mapped_column(
        Enum(AccountType, name="account_type", values_callable=_values), default=AccountType.B2C, index=True
    )
    b2b_account_id: Mapped[int | None] = mapped_column(ForeignKey("b2b_accounts.id", ondelete="RESTRICT"), index=True)
    b2b_account: Mapped[B2BAccount | None] = relationship(
        back_populates="members", foreign_keys=[b2b_account_id], lazy="joined"
    )

    @property
    def is_verified_b2b(self) -> bool:
        return (
            self.account_type is AccountType.B2B
            and self.b2b_account is not None
            and self.b2b_account.status is B2BStatus.APPROVED
        )

    @property
    def wholesale_price_list_id(self) -> int | None:
        """Прайс-лист применяется только к подтверждённому B2B — заявка «на рассмотрении» видит розницу."""
        return self.b2b_account.price_list_id if self.is_verified_b2b and self.b2b_account else None


class RefreshToken(Base):
    """Белый список refresh-токенов: ротация, отзыв, logout со всех устройств."""

    __tablename__ = "refresh_tokens"
    __table_args__ = (UniqueConstraint("jti"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    jti: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Заменён новым при ротации (а не отозван выходом). Повтор такого токена в первые секунды — не кража:
    # ответ с новым токеном мог не дойти (перезагрузка страницы, вторая вкладка, обрыв сети)
    rotated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    user_agent: Mapped[str | None] = mapped_column(String(255))


class LoginCode(Base):
    """Одноразовый код входа (SMS или письмо). Храним только HMAC кода — утечка БД не раскрывает коды."""

    __tablename__ = "login_codes"

    id: Mapped[int] = mapped_column(primary_key=True)
    channel: Mapped[str] = mapped_column(String(8), default="sms")  # sms | email
    target: Mapped[str] = mapped_column(String(255), index=True)  # +79161234567 или email в нижнем регистре
    code_hash: Mapped[str] = mapped_column(String(64))
    ip: Mapped[str | None] = mapped_column(String(64))
    attempts: Mapped[int] = mapped_column(default=0)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
