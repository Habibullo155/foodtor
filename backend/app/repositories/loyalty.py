from collections.abc import Sequence
from decimal import Decimal

from sqlalchemy import func, select

from app.models import LoyaltyTier, Order, OrderStatus, User
from app.repositories.base import BaseRepository


class LoyaltyTierRepository(BaseRepository[LoyaltyTier]):
    model = LoyaltyTier

    async def active_ordered(self) -> Sequence[LoyaltyTier]:
        stmt = select(LoyaltyTier).where(LoyaltyTier.is_active).order_by(LoyaltyTier.min_total_spent)
        return (await self.session.scalars(stmt)).all()


class UserRepository(BaseRepository[User]):
    model = User

    async def get_by_email(self, email: str) -> User | None:
        return await self.session.scalar(select(User).where(func.lower(User.email) == email.lower()))

    async def get_for_update(self, user_id: int) -> User | None:
        """Блокировка строки: два параллельных «доставлено» не испортят total_spent."""
        stmt = select(User).where(User.id == user_id).with_for_update(of=User)
        return (await self.session.scalars(stmt)).unique().one_or_none()

    async def sum_delivered_spent(self, user_id: int) -> Decimal:
        stmt = select(func.coalesce(func.sum(Order.total), 0)).where(
            Order.user_id == user_id, Order.status == OrderStatus.DELIVERED
        )
        return Decimal(await self.session.scalar(stmt))
