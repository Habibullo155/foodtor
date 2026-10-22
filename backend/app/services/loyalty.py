from collections.abc import Sequence
from decimal import ROUND_HALF_UP, Decimal

from app.models import DiscountType, LoyaltyTier, User
from app.repositories.loyalty import LoyaltyTierRepository, UserRepository
from app.schemas.loyalty import LoyaltyProgress, LoyaltyTierOut

CENT = Decimal("0.01")


def money(value: Decimal) -> Decimal:
    return value.quantize(CENT, rounding=ROUND_HALF_UP)


def resolve_tier(total_spent: Decimal, tiers: Sequence[LoyaltyTier]) -> LoyaltyTier | None:
    """Наивысший уровень, порог которого достигнут. tiers отсортированы по возрастанию порога."""
    current = None
    for tier in tiers:
        if total_spent >= tier.min_total_spent:
            current = tier
        else:
            break
    return current


def calculate_discount(subtotal: Decimal, tier: LoyaltyTier | None) -> Decimal:
    if tier is None or subtotal <= 0:
        return Decimal("0.00")
    if tier.discount_type is DiscountType.PERCENT:
        discount = subtotal * tier.discount_value / 100
    else:
        if subtotal < tier.min_order_for_fixed:
            return Decimal("0.00")
        discount = tier.discount_value
    return money(min(discount, subtotal))  # скидка никогда не уводит сумму в минус


def allocate_discount(line_amounts: list[Decimal], discount: Decimal) -> list[Decimal]:
    """
    Пропорционально распределяет скидку заказа по строкам (для учёта маржи по каждому товару).
    Копеечный остаток от округления уходит в самую крупную строку — сумма сходится точно.
    """
    total = sum(line_amounts)
    if not total or not discount:
        return [Decimal("0.00")] * len(line_amounts)
    shares = [money(discount * amount / total) for amount in line_amounts]
    remainder = discount - sum(shares)
    if remainder:
        biggest = max(range(len(line_amounts)), key=line_amounts.__getitem__)
        shares[biggest] += remainder
    return shares


class LoyaltyService:
    def __init__(self, users: UserRepository, tiers: LoyaltyTierRepository) -> None:
        self.users = users
        self.tiers = tiers

    async def recalculate_for_user(self, user_id: int) -> tuple[LoyaltyTier | None, bool]:
        """
        Вызывается после перевода заказа в DELIVERED (и при отмене/возврате).
        Идемпотентно: сумма считается из БД, а не инкрементом — повторный вызов безопасен.
        Возвращает (новый уровень, был ли повышен) — для push-уведомления «Вы стали Gold!».
        """
        user = await self.users.get_for_update(user_id)
        if user is None:
            raise LookupError(f"User {user_id} not found")

        user.total_spent = await self.users.sum_delivered_spent(user_id)
        tiers = await self.tiers.active_ordered()
        new_tier = resolve_tier(user.total_spent, tiers)

        old_threshold = user.loyalty_tier.min_total_spent if user.loyalty_tier else Decimal("-1")
        upgraded = new_tier is not None and new_tier.min_total_spent > old_threshold
        user.loyalty_tier_id = new_tier.id if new_tier else None
        user.loyalty_tier = new_tier
        return new_tier, upgraded

    async def progress(self, user: User) -> LoyaltyProgress:
        tiers = list(await self.tiers.active_ordered())
        current = resolve_tier(user.total_spent, tiers)
        next_tier = next((t for t in tiers if t.min_total_spent > user.total_spent), None)

        if next_tier is None:
            amount_to_next, progress = None, 1.0
        else:
            floor = current.min_total_spent if current else Decimal("0")
            span = next_tier.min_total_spent - floor
            amount_to_next = next_tier.min_total_spent - user.total_spent
            progress = float((user.total_spent - floor) / span) if span else 1.0

        return LoyaltyProgress(
            current_tier=LoyaltyTierOut.model_validate(current) if current else None,
            next_tier=LoyaltyTierOut.model_validate(next_tier) if next_tier else None,
            total_spent=user.total_spent,
            amount_to_next=amount_to_next,
            progress=max(0.0, min(progress, 1.0)),
        )
