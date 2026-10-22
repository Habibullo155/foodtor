import enum
from datetime import date

from sqlalchemy import CheckConstraint, Date, Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, Money, TimestampMixin


class ExpenseCategory(str, enum.Enum):
    SHIPPING = "shipping"  # доставка за счёт магазина
    PAYMENT_FEE = "payment_fee"  # эквайринг
    PACKAGING = "packaging"
    MARKETING = "marketing"
    RENT = "rent"
    SALARY = "salary"
    OTHER = "other"


class Expense(TimestampMixin, Base):
    """
    Расходы. order_id задан → прямой расход заказа (входит в Order.net_profit).
    order_id пуст → операционный расход периода (вычитается на дашборде).
    """

    __tablename__ = "expenses"
    __table_args__ = (CheckConstraint("amount > 0", name="amount_positive"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    category: Mapped[ExpenseCategory] = mapped_column(
        Enum(ExpenseCategory, name="expense_category", values_callable=lambda e: [m.value for m in e]), index=True
    )
    amount: Mapped[Money]
    incurred_on: Mapped[date] = mapped_column(Date, index=True)
    description: Mapped[str] = mapped_column(String(500), default="")
    order_id: Mapped[int | None] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), index=True)
    created_by_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
