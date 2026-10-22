from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import DeliveryMethod, PromoCode


class PromoError(ValueError):
    pass


def delivery_fee(method: DeliveryMethod, goods: Decimal) -> Decimal:
    s = get_settings()
    match method:
        case DeliveryMethod.EXPRESS:
            return Decimal(s.express_fee)
        case DeliveryMethod.COURIER:
            return Decimal(0) if goods >= s.free_courier_from else Decimal(s.courier_fee)
        case DeliveryMethod.PICKUP:
            return Decimal(0)


class PromoService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_valid(self, code: str) -> PromoCode:
        promo = await self.session.scalar(select(PromoCode).where(PromoCode.code == code.strip().upper()))
        now = datetime.now(UTC)
        if promo is None or not promo.is_active:
            raise PromoError("Промокод не найден")
        if promo.valid_until is not None and promo.valid_until < now:
            raise PromoError("Срок действия промокода истёк")
        if promo.usage_limit is not None and promo.used_count >= promo.usage_limit:
            raise PromoError("Промокод больше не действует")
        return promo

    async def apply(self, code: str | None, goods: Decimal) -> tuple[PromoCode | None, Decimal]:
        """Проверка + атомарное списание использования (UPDATE ... WHERE used_count < limit)."""
        if not code:
            return None, Decimal("0")
        promo = await self.get_valid(code)
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
