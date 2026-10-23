from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Order, OrderStatus, PromoCode, User


class PromoError(ValueError):
    pass


class PromoService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_valid(self, code: str, user: User | None = None) -> PromoCode:
        promo = await self.session.scalar(select(PromoCode).where(PromoCode.code == code.strip().upper()))
        now = datetime.now(UTC)
        if promo is None or not promo.is_active:
            raise PromoError("Промокод не найден")
        if promo.owner_user_id is not None and (user is None or promo.owner_user_id != user.id):
            raise PromoError("Промокод не найден")  # чужой личный код — как будто его нет
        if promo.first_order_only and user is not None and await self._has_orders(user):
            raise PromoError("Промокод действует только на первый заказ")
        if promo.valid_until is not None and promo.valid_until < now:
            raise PromoError("Срок действия промокода истёк")
        if promo.usage_limit is not None and promo.used_count >= promo.usage_limit:
            raise PromoError("Промокод больше не действует")
        return promo

    async def _has_orders(self, user: User) -> bool:
        return (
            await self.session.scalar(
                select(Order.id).where(Order.user_id == user.id, Order.status != OrderStatus.CANCELLED).limit(1)
            )
        ) is not None

    async def apply(
        self, code: str | None, goods: Decimal, user: User | None = None
    ) -> tuple[PromoCode | None, Decimal]:
        """Проверка + атомарное списание использования (UPDATE ... WHERE used_count < limit)."""
        if not code:
            return None, Decimal("0")
        promo = await self.get_valid(code, user)
        if goods < promo.min_order:
            raise PromoError(f"Промокод действует от {promo.min_order:.0f} ₽")
        result = await self.session.execute(
            update(PromoCode)
            .where(
                PromoCode.id == promo.id,
                (PromoCode.usage_limit.is_(None)) | (PromoCode.used_count < PromoCode.usage_limit),
            )
            .values(used_count=PromoCode.used_count + 1)
        )
        if result.rowcount == 0:  # гонка: последний доступный код забрали параллельно
            raise PromoError("Промокод больше не действует")
        return promo, min(promo.amount, goods)

    async def release(self, code: str | None) -> None:
        """Отмена заказа возвращает использование промокода."""
        if code:
            await self.session.execute(
                update(PromoCode)
                .where(PromoCode.code == code, PromoCode.used_count > 0)
                .values(used_count=PromoCode.used_count - 1)
            )
