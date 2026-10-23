from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator

from app.api.deps import SessionDep, require
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.models import Permission
from app.schemas.catalog import MoneyOut
from app.services import shop_info
from app.services.geo import (
    GeocoderUnavailable,
    Point,
    check_delivery,
    geocode,
    get_settings_row,
    reverse_geocode,
)

router = APIRouter(tags=["delivery"])


class ZoneOut(BaseModel):
    enabled: bool
    store_address: str
    lat: float
    lng: float
    radius_km: float
    cities: list[str]


class CheckIn(BaseModel):
    """Адрес строкой или точка на карте (lat/lng) — точка точнее, геокодер не нужен."""

    address: str | None = Field(default=None, min_length=3, max_length=300)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def _one_of(self):
        if not self.address and (self.lat is None or self.lng is None):
            raise ValueError("Укажите адрес или точку на карте")
        return self


class CheckOut(BaseModel):
    ok: bool
    distance_km: float | None
    radius_km: float
    lat: float | None
    lng: float | None
    reason: str | None
    city: str | None = None


async def _zone(session) -> ZoneOut:
    s = await get_settings_row(session)
    return ZoneOut(
        enabled=s.delivery_zone_enabled,
        store_address=s.store_address,
        lat=s.store_lat,
        lng=s.store_lng,
        radius_km=s.delivery_radius_km,
        cities=list(s.delivery_cities or []),
    )


@router.get("/delivery/zone", response_model=ZoneOut)
async def delivery_zone(session: SessionDep) -> ZoneOut:
    return await _zone(session)


@router.post("/delivery/check", response_model=CheckOut)
@limiter.limit("30/minute")  # геокодер — внешний сервис, не даём им злоупотреблять через нас
async def delivery_check(request: Request, body: CheckIn, session: SessionDep) -> CheckOut:
    point = Point(body.lat, body.lng) if body.lat is not None and body.lng is not None else None
    return CheckOut(**(await check_delivery(session, body.address, point)).as_dict())


class ReverseOut(BaseModel):
    address: str | None  # «Москва, Тверская улица, 12»; None — рядом нет адреса (покупатель допишет вручную)
    city: str | None = None
    street: str | None = None
    house: str | None = None  # None — дом не определился: попросим уточнить


@router.get("/delivery/reverse", response_model=ReverseOut)
@limiter.limit("30/minute")
async def delivery_reverse(
    request: Request,
    lat: Annotated[float, Query(ge=-90, le=90)],
    lng: Annotated[float, Query(ge=-180, le=180)],
) -> ReverseOut:
    """Подпись для точки, выбранной на карте («Моё местоположение» или булавка)."""
    try:
        place = await reverse_geocode(Point(lat, lng))
    except GeocoderUnavailable:
        return ReverseOut(address=None)
    if place is None:
        return ReverseOut(address=None)
    return ReverseOut(address=place.text, city=place.city, street=place.street, house=place.house)


class ZoneIn(BaseModel):
    radius_km: float = Field(gt=0, le=500)
    enabled: bool = True
    store_address: str | None = Field(default=None, min_length=3, max_length=300)
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    cities: list[Annotated[str, Field(min_length=2, max_length=60)]] | None = Field(default=None, max_length=50)


@router.get(
    "/admin/settings/delivery", response_model=ZoneOut, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def get_zone(session: SessionDep) -> ZoneOut:
    return await _zone(session)


@router.put(
    "/admin/settings/delivery", response_model=ZoneOut, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def set_zone(body: ZoneIn, session: SessionDep) -> ZoneOut:
    s = await get_settings_row(session)
    if body.lat is not None and body.lng is not None:
        s.store_lat, s.store_lng = body.lat, body.lng  # точка выбрана на карте
        if body.store_address:
            s.store_address = body.store_address
    elif body.store_address and body.store_address != s.store_address:
        try:
            point = await geocode(body.store_address)
        except GeocoderUnavailable as exc:
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                "Сервис карт недоступен — попробуйте позже или поставьте точку на карте",
            ) from exc
        if point is None:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Адрес склада не найден — уточните его")
        s.store_address, s.store_lat, s.store_lng = body.store_address, point.lat, point.lng
    if body.cities is not None:
        seen: dict[str, str] = {}
        for c in body.cities:
            seen.setdefault(c.strip().lower(), c.strip())  # без дублей, регистр как ввёл админ
        s.delivery_cities = list(seen.values())
    s.delivery_radius_km = body.radius_km
    s.delivery_zone_enabled = body.enabled
    return await _zone(session)


class PaymentsOut(BaseModel):
    provider: str
    mode: str  # test | prod
    callback_url: str


@router.get(
    "/admin/settings/payments", response_model=PaymentsOut, dependencies=[Depends(require(Permission.DASHBOARD_VIEW))]
)
async def payments_status() -> PaymentsOut:
    s = get_settings()
    if not s.payments_enabled:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not Found")
    return PaymentsOut(
        provider="Альфа-Банк",
        mode="test" if "rbsuat" in s.alfa_api_url else "prod",
        callback_url=f"{s.public_api_url.rstrip('/')}/api/v1/payments/alfa/callback",
    )


class ShopOptionsOut(BaseModel):
    min_order: MoneyOut  # курьер и экспресс — от этой суммы
    courier_fee: MoneyOut
    free_delivery_from: MoneyOut | None
    express_enabled: bool
    express_fee: MoneyOut
    express_hours: int
    pickup_enabled: bool
    hours: str
    phone: str
    email: str
    telegram: str
    instagram: str
    wholesale_min_order: MoneyOut


@router.get("/shop/options", response_model=ShopOptionsOut)
async def shop_options(session: SessionDep) -> ShopOptionsOut:
    """Публичные настройки для оформления заказа (без секретов)."""
    info = await shop_info.load(session)
    d = info.delivery
    return ShopOptionsOut(
        min_order=d.min_order,
        courier_fee=d.courier_fee,
        free_delivery_from=d.free_from,
        express_enabled=d.express_enabled,
        express_fee=d.express_fee,
        express_hours=d.express_hours,
        pickup_enabled=d.pickup_enabled,
        hours=info.hours.text,
        phone=info.contacts.phone,
        email=info.contacts.email,
        telegram=info.socials.telegram,
        instagram=info.socials.instagram,
        wholesale_min_order=(await get_settings_row(session)).wholesale_min_order,
    )


Money = Annotated[Decimal, Field(ge=0, le=1_000_000, max_digits=12, decimal_places=2)]


class ShopSettingsIO(BaseModel):
    contact_phone: str = Field(min_length=5, max_length=32, pattern=r"^\+?[0-9 ()\-]{5,32}$")
    contact_email: EmailStr | Literal[""] = ""
    delivery_min_order: Money
    courier_fee: Money
    free_delivery_from: Money | None
    express_enabled: bool
    express_fee: Money
    express_hours: int = Field(ge=1, le=24)
    pickup_enabled: bool
    legal_name: str = Field(default="", max_length=255)
    legal_inn: str = Field(default="", pattern=r"^(\d{10}|\d{12})?$")
    legal_ogrn: str = Field(default="", pattern=r"^(\d{13}|\d{15})?$")
    legal_address: str = Field(default="", max_length=300)


SHOP_FIELDS = tuple(ShopSettingsIO.model_fields)


@router.get(
    "/admin/settings/shop", response_model=ShopSettingsIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def get_shop_settings(session: SessionDep) -> ShopSettingsIO:
    row = await get_settings_row(session)
    return ShopSettingsIO(**{f: getattr(row, f) for f in SHOP_FIELDS})


@router.put(
    "/admin/settings/shop", response_model=ShopSettingsIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def set_shop_settings(body: ShopSettingsIO, session: SessionDep) -> ShopSettingsIO:
    row = await get_settings_row(session)
    for f in SHOP_FIELDS:
        setattr(row, f, getattr(body, f))
    shop_info.remember(shop_info.from_row(row))
    return body


class ReferralIO(BaseModel):
    referral_enabled: bool
    referral_friend_amount: Money
    referral_inviter_amount: Money
    referral_min_order: Money


REFERRAL_FIELDS = tuple(ReferralIO.model_fields)


@router.get(
    "/admin/settings/referral", response_model=ReferralIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def get_referral_settings(session: SessionDep) -> ReferralIO:
    row = await get_settings_row(session)
    return ReferralIO(**{f: getattr(row, f) for f in REFERRAL_FIELDS})


@router.put(
    "/admin/settings/referral", response_model=ReferralIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def set_referral_settings(body: ReferralIO, session: SessionDep) -> ReferralIO:
    row = await get_settings_row(session)
    for f in REFERRAL_FIELDS:
        setattr(row, f, getattr(body, f))
    shop_info.remember(shop_info.from_row(row))
    return body


HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"


class HoursIO(BaseModel):
    days: list[Annotated[int, Field(ge=0, le=6)]] = Field(max_length=7)
    start: str = Field(pattern=HHMM)
    end: str = Field(pattern=HHMM)
    text: str = ""

    @model_validator(mode="after")
    def _check(self):
        if len(set(self.days)) != len(self.days):
            raise ValueError("Дни недели повторяются")
        if self.end <= self.start:
            raise ValueError("Время закрытия должно быть позже открытия")
        return self


def _hours_out(h: shop_info.WorkHours) -> HoursIO:
    return HoursIO(days=list(h.days), start=h.start, end=h.end, text=h.text)


@router.get(
    "/admin/settings/hours", response_model=HoursIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def get_hours(session: SessionDep) -> HoursIO:
    return _hours_out(shop_info.from_row(await get_settings_row(session)).hours)


@router.put(
    "/admin/settings/hours", response_model=HoursIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def set_hours(body: HoursIO, session: SessionDep) -> HoursIO:
    s = await get_settings_row(session)
    s.work_days, s.work_from, s.work_to = sorted(body.days), body.start, body.end
    info = shop_info.from_row(s)
    shop_info.remember(info)
    return _hours_out(info.hours)


class SocialsIO(BaseModel):
    telegram: str = Field(default="", max_length=200)
    instagram: str = Field(default="", max_length=200)

    @field_validator("telegram")
    @classmethod
    def _telegram(cls, v: str) -> str:
        return shop_info.telegram_url(v)

    @field_validator("instagram")
    @classmethod
    def _instagram(cls, v: str) -> str:
        return shop_info.instagram_url(v)


@router.get(
    "/admin/settings/socials", response_model=SocialsIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def get_socials(session: SessionDep) -> SocialsIO:
    s = shop_info.from_row(await get_settings_row(session)).socials
    return SocialsIO(telegram=s.telegram, instagram=s.instagram)


@router.put(
    "/admin/settings/socials", response_model=SocialsIO, dependencies=[Depends(require(Permission.PRICING_MANAGE))]
)
async def set_socials(body: SocialsIO, session: SessionDep) -> SocialsIO:
    s = await get_settings_row(session)
    s.telegram_url, s.instagram_url = body.telegram, body.instagram
    shop_info.remember(shop_info.from_row(s))
    return body
