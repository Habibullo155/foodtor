from datetime import UTC, datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import and_, func, or_, select, update
from sqlalchemy.orm import aliased

from app.api.deps import CurrentUser, SessionDep, require
from app.core.rate_limit import limiter
from app.models import Banner, Permission, SupportMessage, User
from app.schemas.catalog import MoneyOut
from app.services import referrals, shop_info

router = APIRouter(tags=["marketing"])

IMAGE = r"^(https://|/media/|/static/)"
LINK = r"^(/($|[^/\\])|https://)"  # свои страницы или внешний https — не javascript: и не //чужой.сайт


class BannerIn(BaseModel):
    title: str = Field(min_length=1, max_length=80)
    text: str = Field(default="", max_length=200)
    image_url: str | None = Field(default=None, max_length=1024, pattern=IMAGE)
    button_label: str | None = Field(default=None, max_length=40)
    link_url: str | None = Field(default=None, max_length=300, pattern=LINK)
    theme: Literal["green", "orange", "cream"] = "green"
    button_color: Literal["orange", "green", "white", "dark"] = "orange"
    is_active: bool = True
    starts_at: datetime | None = None
    ends_at: datetime | None = None

    @model_validator(mode="after")
    def _check(self):
        if self.starts_at and self.ends_at and self.ends_at <= self.starts_at:
            raise ValueError("Дата окончания раньше даты начала")
        if self.button_label and not self.link_url:
            raise ValueError("Для кнопки нужна ссылка")
        return self


class BannerOut(BannerIn):
    id: int
    position: int


def _visible_now():
    now = datetime.now(UTC)
    return and_(
        Banner.is_active,
        or_(Banner.starts_at.is_(None), Banner.starts_at <= now),
        or_(Banner.ends_at.is_(None), Banner.ends_at > now),
    )


async def visible_banners(session) -> list[Banner]:
    return list((await session.scalars(select(Banner).where(_visible_now()).order_by(Banner.position, Banner.id))).all())


@router.get("/banners", response_model=list[BannerOut])
async def public_banners(session: SessionDep) -> list[Banner]:
    return await visible_banners(session)


banners_admin = [Depends(require(Permission.PRODUCTS_WRITE))]


@router.get("/admin/banners", response_model=list[BannerOut], dependencies=banners_admin)
async def admin_banners(session: SessionDep) -> list[Banner]:
    return list((await session.scalars(select(Banner).order_by(Banner.position, Banner.id))).all())


@router.post("/admin/banners", response_model=BannerOut, status_code=201, dependencies=banners_admin)
async def create_banner(body: BannerIn, session: SessionDep) -> Banner:
    last = await session.scalar(select(func.max(Banner.position)))
    banner = Banner(**body.model_dump(), position=(last or 0) + 1)
    session.add(banner)
    await session.flush()
    return banner


async def _banner(session, banner_id: int) -> Banner:
    banner = await session.get(Banner, banner_id)
    if banner is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Баннер не найден")
    return banner


@router.put("/admin/banners/{banner_id}", response_model=BannerOut, dependencies=banners_admin)
async def update_banner(banner_id: int, body: BannerIn, session: SessionDep) -> Banner:
    banner = await _banner(session, banner_id)
    for k, v in body.model_dump().items():
        setattr(banner, k, v)
    await session.flush()
    return banner


@router.delete("/admin/banners/{banner_id}", status_code=204, dependencies=banners_admin)
async def delete_banner(banner_id: int, session: SessionDep) -> None:
    await session.delete(await _banner(session, banner_id))


class OrderIn(BaseModel):
    ids: list[int] = Field(max_length=100)


@router.put("/admin/banners-order", status_code=204, dependencies=banners_admin)
async def reorder_banners(body: OrderIn, session: SessionDep) -> None:
    for pos, banner_id in enumerate(body.ids):
        await session.execute(update(Banner).where(Banner.id == banner_id).values(position=pos))


class PromoOut(BaseModel):
    code: str
    amount: MoneyOut
    min_order: MoneyOut
    used: bool
    source: str
    first_order_only: bool


class ReferralOut(BaseModel):
    enabled: bool
    code: str
    friend_amount: MoneyOut
    inviter_amount: MoneyOut
    min_order: MoneyOut
    invited: int
    rewarded: int
    promos: list[PromoOut]


@router.get("/me/referral", response_model=ReferralOut)
async def my_referral(user: CurrentUser, session: SessionDep) -> ReferralOut:
    rules = (await shop_info.load(session)).referral
    info = await referrals.summary(session, user)
    return ReferralOut(
        enabled=rules.enabled,
        code=info.code,
        friend_amount=rules.friend_amount,
        inviter_amount=rules.inviter_amount,
        min_order=rules.min_order,
        invited=info.invited,
        rewarded=info.rewarded,
        promos=[
            PromoOut(
                code=p.code,
                amount=p.amount,
                min_order=p.min_order,
                used=p.usage_limit is not None and p.used_count >= p.usage_limit,
                source=p.source,
                first_order_only=p.first_order_only,
            )
            for p in info.promos
        ],
    )


class SupportIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)

    @field_validator("text")
    @classmethod
    def _strip(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Напишите сообщение")
        return v.strip()


class SupportMessageOut(BaseModel):
    id: int
    text: str
    from_staff: bool
    author: str
    created_at: datetime


async def _thread(session, user_id: int) -> list[SupportMessageOut]:
    rows = await session.execute(
        select(SupportMessage, User.full_name)
        .outerjoin(User, User.id == SupportMessage.staff_id)
        .where(SupportMessage.user_id == user_id)
        .order_by(SupportMessage.created_at, SupportMessage.id)
    )
    return [
        SupportMessageOut(
            id=m.id,
            text=m.text,
            from_staff=m.staff_id is not None,
            author=(staff_name or "Поддержка").split(" ")[0] if m.staff_id else "Вы",
            created_at=m.created_at,
        )
        for m, staff_name in rows.all()
    ]


async def _mark_read(session, user_id: int, *, by_staff: bool) -> None:
    side = SupportMessage.staff_id.is_(None) if by_staff else SupportMessage.staff_id.is_not(None)
    await session.execute(
        update(SupportMessage)
        .where(SupportMessage.user_id == user_id, side, SupportMessage.read_at.is_(None))
        .values(read_at=datetime.now(UTC))
    )


@router.get("/me/support", response_model=list[SupportMessageOut])
async def my_support(user: CurrentUser, session: SessionDep) -> list[SupportMessageOut]:
    await _mark_read(session, user.id, by_staff=False)
    return await _thread(session, user.id)


@router.post("/me/support", response_model=list[SupportMessageOut], status_code=201)
@limiter.limit("30/hour")
async def write_support(request: Request, body: SupportIn, user: CurrentUser, session: SessionDep):
    session.add(SupportMessage(user_id=user.id, text=body.text))
    await session.flush()
    return await _thread(session, user.id)


class SupportThreadOut(BaseModel):
    user_id: int
    name: str
    phone: str | None
    email: str | None
    last_text: str
    last_at: datetime
    last_from_staff: bool
    unread: int


support_staff = [Depends(require(Permission.ORDERS_READ_ALL))]


@router.get("/admin/support", response_model=list[SupportThreadOut], dependencies=support_staff)
async def support_threads(
    session: SessionDep, limit: Annotated[int, Query(ge=1, le=500)] = 200
) -> list[SupportThreadOut]:
    last = (
        select(SupportMessage.user_id, func.max(SupportMessage.id).label("last_id"))
        .group_by(SupportMessage.user_id)
        .subquery()
    )
    unread_msg = aliased(SupportMessage)
    unread = (
        select(func.count())
        .where(
            unread_msg.user_id == last.c.user_id,
            unread_msg.staff_id.is_(None),
            unread_msg.read_at.is_(None),
        )
        .correlate(last)
        .scalar_subquery()
    )
    rows = await session.execute(
        select(SupportMessage, User, unread)
        .join(last, last.c.last_id == SupportMessage.id)
        .join(User, User.id == SupportMessage.user_id)
        .order_by(SupportMessage.created_at.desc())
        .limit(limit)
    )
    return [
        SupportThreadOut(
            user_id=u.id,
            name=u.full_name,
            phone=u.phone_e164 or u.phone,
            email=u.email,
            last_text=m.text[:200],
            last_at=m.created_at,
            last_from_staff=m.staff_id is not None,
            unread=n,
        )
        for m, u, n in rows.unique().all()
    ]


@router.get("/admin/support/{user_id}", response_model=list[SupportMessageOut], dependencies=support_staff)
async def support_thread(user_id: int, session: SessionDep) -> list[SupportMessageOut]:
    await _mark_read(session, user_id, by_staff=True)
    return await _thread(session, user_id)


@router.post("/admin/support/{user_id}", response_model=list[SupportMessageOut], status_code=201)
async def answer_support(
    user_id: int,
    body: SupportIn,
    session: SessionDep,
    staff: Annotated[User, Depends(require(Permission.ORDERS_READ_ALL))],
) -> list[SupportMessageOut]:
    if await session.get(User, user_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Покупатель не найден")
    session.add(SupportMessage(user_id=user_id, staff_id=staff.id, text=body.text))
    await _mark_read(session, user_id, by_staff=True)
    await session.flush()
    return await _thread(session, user_id)


class UnreadOut(BaseModel):
    unread: int


@router.get("/me/support/unread", response_model=UnreadOut)
async def my_unread(user: CurrentUser, session: SessionDep) -> UnreadOut:
    n = await session.scalar(
        select(func.count()).where(
            SupportMessage.user_id == user.id,
            SupportMessage.staff_id.is_not(None),
            SupportMessage.read_at.is_(None),
        )
    )
    return UnreadOut(unread=n or 0)

