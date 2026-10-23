import secrets
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import PromoCode, User
from app.services import shop_info
from app.services.geo import get_settings_row

# без похожих символов (0/O, 1/I/L): код диктуют по телефону и вводят руками
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def _random(n: int) -> str:
    return "".join(secrets.choice(ALPHABET) for _ in range(n))


async def code_for(session: AsyncSession, user: User) -> str:
    if user.referral_code:
        return user.referral_code
    while True:
        code = _random(7)
        if await session.scalar(select(User.id).where(User.referral_code == code)) is None:
            user.referral_code = code
            await session.flush()
            return code


async def _issue_promo(session: AsyncSession, owner: User, amount, min_order, source: str, prefix: str) -> PromoCode:
    while True:
        code = f"{prefix}-{_random(6)}"
        if await session.scalar(select(PromoCode.id).where(PromoCode.code == code)) is None:
            break
    promo = PromoCode(
        code=code,
        amount=amount,
        min_order=min_order,
        usage_limit=1,
        owner_user_id=owner.id,
        source=source,
        first_order_only=source == "referral_friend",
    )
    session.add(promo)
    await session.flush()
    return promo


async def attach_referrer(session: AsyncSession, user: User, ref_code: str | None) -> None:
    """Новый покупатель пришёл по ссылке друга: запоминаем пригласившего и дарим промокод на первый заказ."""
    if not ref_code:
        return
    rules = shop_info.from_row(await get_settings_row(session)).referral
    if not rules.enabled:
        return
    inviter = await session.scalar(select(User).where(User.referral_code == ref_code.strip().upper()))
    if inviter is None or inviter.id == user.id or user.referred_by_id is not None:
        return
    user.referred_by_id = inviter.id
    if rules.friend_amount > 0:
        await _issue_promo(session, user, rules.friend_amount, rules.min_order, "referral_friend", "FRIEND")


async def reward_inviter(session: AsyncSession, buyer_id: int) -> PromoCode | None:
    """Друг получил свой первый заказ — пригласившему промокод (один раз на каждого друга)."""
    buyer = await session.get(User, buyer_id)
    if buyer is None or buyer.referred_by_id is None or buyer.referral_rewarded:
        return None
    buyer.referral_rewarded = True
    rules = shop_info.from_row(await get_settings_row(session)).referral
    inviter = await session.get(User, buyer.referred_by_id)
    if not rules.enabled or rules.inviter_amount <= 0 or inviter is None:
        return None
    return await _issue_promo(session, inviter, rules.inviter_amount, rules.min_order, "referral_inviter", "BONUS")


@dataclass
class ReferralSummary:
    code: str
    invited: int
    rewarded: int
    promos: list[PromoCode]


async def summary(session: AsyncSession, user: User) -> ReferralSummary:
    code = await code_for(session, user)
    invited = await session.scalar(select(func.count()).where(User.referred_by_id == user.id)) or 0
    rewarded = (
        await session.scalar(select(func.count()).where(User.referred_by_id == user.id, User.referral_rewarded)) or 0
    )
    promos = (
        await session.scalars(
            select(PromoCode)
            .where(PromoCode.owner_user_id == user.id, PromoCode.is_active)
            .order_by(PromoCode.created_at.desc())
        )
    ).all()
    return ReferralSummary(code, invited, rewarded, list(promos))
