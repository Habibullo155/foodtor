from datetime import datetime
from decimal import Decimal
from typing import Annotated

from sqlalchemy import DateTime, MetaData, Numeric, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# Единые имена констрейнтов — стабильные миграции Alembic
NAMING = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}

# Деньги — только Numeric, никогда float
Money = Annotated[Decimal, mapped_column(Numeric(12, 2))]
MoneyDefault0 = Annotated[Decimal, mapped_column(Numeric(12, 2), default=Decimal("0.00"), server_default="0")]


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING)


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
