"""
Зона доставки: адрес → координаты (геокодер) → расстояние до склада → внутри радиуса или нет.

Расстояние — по прямой (формула гаверсинуса). Для продуктовой доставки по городу этого достаточно;
маршрутное расстояние потребовало бы платного routing-API.
"""

import math
import re
from dataclasses import dataclass

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import ShopSettings

# Подмена HTTP-транспорта в тестах
TEST_TRANSPORT: httpx.AsyncBaseTransport | None = None


class GeocoderUnavailable(Exception):
    """Геокодер не ответил (сеть/лимит). Заказ не блокируем — лучше проверить вручную, чем потерять покупателя."""


@dataclass(frozen=True, slots=True)
class Point:
    lat: float
    lng: float


def haversine_km(a: Point, b: Point) -> float:
    r = 6371.0
    p1, p2 = math.radians(a.lat), math.radians(b.lat)
    dp, dl = p2 - p1, math.radians(b.lng - a.lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def _user_agent() -> str:
    """Nominatim требует опознаваемый User-Agent: сайт магазина и (если задан) контактный email."""
    s = get_settings()
    contact = ", ".join(c for c in (s.public_shop_url, s.geocoder_contact_email) if c)
    return f"saasshop/1.0 ({contact})"


async def geocode(address: str) -> Point | None:
    """None — адрес не найден. GeocoderUnavailable — сервис недоступен."""
    found = await _geocode_cached(" ".join(address.lower().split()))
    return found[0] if found else None


async def geocode_house(address: str) -> tuple[Point, bool] | None:
    """(точка, найден_ли_именно_дом). Дом — когда геокодер узнал номер дома, а не только город/улицу."""
    return await _geocode_cached(" ".join(address.lower().split()))


_HOUSE = re.compile(r"(?<![\w])\d+[а-яa-z]?(?:\s*[/к]\s*\d+)?(?![\w])", re.IGNORECASE)


# Слова, которые не являются улицей: города и служебные сокращения
_NOT_STREET = {"москва", "город", "россия", "область", "дом", "корпус", "строение", "квартира", "подъезд", "этаж"}


def looks_like_full_address(address: str, cities: list[str] | None = None) -> bool:
    """Без геокодера: номер дома + хотя бы одно слово, кроме названия города. «Москва, 5» — не адрес."""
    text = " ".join((address or "").split()).lower().replace("ё", "е")
    if not _HOUSE.search(text):
        return False
    skip = _NOT_STREET | {_norm(c) for c in cities or []}
    return any(w not in skip for w in re.findall(r"[а-яa-z]{3,}", text))


_memo: dict[str, tuple[Point, bool] | None] = {}


async def _geocode_cached(q: str) -> tuple[Point, bool] | None:
    if q in _memo:
        return _memo[q]
    s = get_settings()
    try:
        async with httpx.AsyncClient(timeout=6, transport=TEST_TRANSPORT) as client:
            if s.yandex_geocoder_key:
                r = await client.get(
                    "https://geocode-maps.yandex.ru/1.x/",
                    params={
                        "apikey": s.yandex_geocoder_key.get_secret_value(),
                        "geocode": q,
                        "format": "json",
                        "results": 1,
                        "lang": "ru_RU",
                    },
                )
                r.raise_for_status()
                members = r.json()["response"]["GeoObjectCollection"]["featureMember"]
                point = None
                if members:
                    obj = members[0]["GeoObject"]
                    lng, lat = map(float, obj["Point"]["pos"].split())
                    precision = obj["metaDataProperty"]["GeocoderMetaData"].get("precision")
                    point = (Point(lat, lng), precision in ("exact", "number"))
            else:
                r = await client.get(
                    "https://nominatim.openstreetmap.org/search",
                    params={
                        "q": q,
                        "format": "jsonv2",
                        "limit": 1,
                        "countrycodes": "ru",
                        "accept-language": "ru",
                        "addressdetails": 1,
                    },
                    headers={"User-Agent": _user_agent()},
                )
                r.raise_for_status()
                data = r.json()
                point = None
                if data:
                    has_house = bool((data[0].get("address") or {}).get("house_number"))
                    point = (Point(float(data[0]["lat"]), float(data[0]["lon"])), has_house)
    except (httpx.HTTPError, KeyError, ValueError, IndexError) as exc:
        raise GeocoderUnavailable(str(exc)) from exc
    if len(_memo) > 5000:
        _memo.clear()
    _memo[q] = point
    return point


@dataclass(frozen=True, slots=True)
class Place:
    """Адрес точки по частям — чтобы сайт мог показать и подставить город, улицу и дом."""

    city: str | None
    street: str | None
    house: str | None

    @property
    def text(self) -> str | None:
        parts = [p for p in (self.city, self.street, self.house) if p]
        return ", ".join(parts) or None


_reverse_memo: dict[tuple[float, float], Place | None] = {}


async def reverse_geocode(point: Point) -> Place | None:
    """Точка на карте → город, улица, дом. None — адреса рядом нет (поле, вода)."""
    key = (round(point.lat, 5), round(point.lng, 5))
    if key in _reverse_memo:
        return _reverse_memo[key]
    s = get_settings()
    try:
        async with httpx.AsyncClient(timeout=6, transport=TEST_TRANSPORT) as client:
            if s.yandex_geocoder_key:
                r = await client.get(
                    "https://geocode-maps.yandex.ru/1.x/",
                    params={
                        "apikey": s.yandex_geocoder_key.get_secret_value(),
                        "geocode": f"{point.lng},{point.lat}",
                        "kind": "house",
                        "format": "json",
                        "results": 1,
                        "lang": "ru_RU",
                    },
                )
                r.raise_for_status()
                members = r.json()["response"]["GeoObjectCollection"]["featureMember"]
                text = None
                if members:
                    comps = members[0]["GeoObject"]["metaDataProperty"]["GeocoderMetaData"]["Address"]["Components"]
                    by_kind = {c["kind"]: c["name"] for c in comps}
                    text = Place(by_kind.get("locality"), by_kind.get("street"), by_kind.get("house"))
            else:
                r = await client.get(
                    "https://nominatim.openstreetmap.org/reverse",
                    params={
                        "lat": point.lat,
                        "lon": point.lng,
                        "format": "jsonv2",
                        "zoom": 18,
                        "addressdetails": 1,
                        "accept-language": "ru",
                    },
                    headers={"User-Agent": _user_agent()},
                )
                r.raise_for_status()
                text = _nominatim_short(r.json())
    except (httpx.HTTPError, KeyError, ValueError, IndexError) as exc:
        raise GeocoderUnavailable(str(exc)) from exc
    if len(_reverse_memo) > 5000:
        _reverse_memo.clear()
    _reverse_memo[key] = text
    return text


def _nominatim_short(data: dict) -> Place | None:
    """Город, улица, дом — без индекса, района и страны (как пишут люди)."""
    a = data.get("address") or {}
    if not a:
        return None
    city = a.get("city") or a.get("town") or a.get("village") or a.get("municipality") or a.get("state")
    street = a.get("road") or a.get("pedestrian") or a.get("footway") or a.get("square")
    return Place(city, street, a.get("house_number"))


async def get_settings_row(session: AsyncSession) -> ShopSettings:
    row = await session.get(ShopSettings, 1)
    if row is None:
        row = ShopSettings(id=1)
        session.add(row)
        await session.flush()
    return row


@dataclass(frozen=True, slots=True)
class DeliveryCheck:
    ok: bool
    distance_km: float | None
    radius_km: float
    point: Point | None
    reason: str | None  # человекочитаемо, по-русски — показывается покупателю
    city: str | None = None  # сработал список городов

    def as_dict(self) -> dict:
        return {
            "ok": self.ok,
            "distance_km": round(self.distance_km, 1) if self.distance_km is not None else None,
            "radius_km": self.radius_km,
            "lat": self.point.lat if self.point else None,
            "lng": self.point.lng if self.point else None,
            "reason": self.reason,
            "city": self.city,
        }


NEED_HOUSE = "Укажите улицу и номер дома — или выберите точку на карте"


def _norm(text: str) -> str:
    return " ".join(text.lower().replace("ё", "е").split())


def matched_city(address: str, cities: list[str]) -> str | None:
    """Город из списка, упомянутый в адресе как отдельное слово («Москва, …», «г. Химки …»)."""
    words = set(re.findall(r"[a-zа-я0-9-]+", _norm(address)))
    text = _norm(address)
    for city in cities:
        c = _norm(city)
        if (" " in c or "-" in c) and c in text or c in words:
            return city
    return None


async def check_delivery(
    session: AsyncSession, address: str | None = None, point: Point | None = None
) -> DeliveryCheck:
    settings = await get_settings_row(session)
    radius = settings.delivery_radius_km
    if not settings.delivery_zone_enabled:
        return DeliveryCheck(True, None, radius, point, None)
    # Точка с карты точна сама по себе. Строка — только с улицей и домом: «Москва» курьеру ничего не говорит
    if point is None:
        if not looks_like_full_address(address or "", settings.delivery_cities):
            return DeliveryCheck(False, None, radius, None, NEED_HOUSE)
        try:
            found = await geocode_house(address or "")
        except GeocoderUnavailable:
            found = False  # сбой геокодера: текст похож на адрес — не теряем заказ, проверим вручную
        if found is None:
            return DeliveryCheck(False, None, radius, None, "Не нашли такой адрес — уточните город, улицу и дом")
        if found and not found[1]:
            return DeliveryCheck(False, None, radius, found[0], NEED_HOUSE)
        point = found[0] if found else None
    if address and (city := matched_city(address, settings.delivery_cities or [])):
        # Город целиком в зоне — радиус не важен
        distance = haversine_km(Point(settings.store_lat, settings.store_lng), point) if point else None
        return DeliveryCheck(True, distance, radius, point, None, city)
    if point is None:
        return DeliveryCheck(True, None, radius, None, None)
    distance = haversine_km(Point(settings.store_lat, settings.store_lng), point)
    if distance > radius:
        return DeliveryCheck(
            False,
            distance,
            radius,
            point,
            f"Мы не доставляем по этому адресу: {distance:.0f} км от нас, а доставляем в радиусе {radius:.0f} км"
            + (f" и по городам: {', '.join(settings.delivery_cities)}" if settings.delivery_cities else "")
            + ". Можно выбрать самовывоз.",
        )
    return DeliveryCheck(True, distance, radius, point, None)
